# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
terraform init              # Initialize providers and backend
terraform fmt -recursive    # Format all .tf files
terraform validate          # Syntax and reference check (run after init)
terraform plan              # Preview changes
terraform apply             # Deploy (requires interactive 'yes' confirmation)
terraform destroy           # Tear down all resources
```

Authentication prerequisite: `az login` with an account that has Contributor/Owner on the target subscription.
GitHub prerequisite: `source .env` to load `GITHUB_TOKEN` (required for `apply` and `destroy`).

## Architecture

This project deploys **two Azure Databricks workspaces** (dev + prod) with shared Unity Catalog, designed to showcase CI/CD with Asset Bundles.

**Three-tier Databricks provider** pattern:

- **`databricks.accounts`** (aliased) -- points at `accounts.azuredatabricks.net` for account-level operations: metastore, SP, OIDC, workspace assignments.
- **Default `databricks`** (no alias) -- points at the dev workspace URL for UC objects, dev catalog/schema/grants, dev SQL warehouse, dev git credential/repo.
- **`databricks.prod`** (aliased) -- points at the prod workspace URL for prod catalog/schema/grants, prod SQL warehouse, prod git credential/repo.

All Databricks providers set `azure_tenant_id` explicitly to avoid tenant mismatch when authenticating via Azure CLI.

### Resource dependency chain

```
Resource Group
  +-- Access Connector (SystemAssigned MI)
  +-- Storage Account (HNS / ADLS Gen2)
        +-- Storage Containers (dev, prod via for_each/toset)
  +-- Role Assignment (Storage Blob Data Contributor -> Access Connector)
  +-- Databricks Dev Workspace (premium, linked to Access Connector)
  +-- Databricks Prod Workspace (premium, linked to Access Connector)

[account-level provider]
  Metastore (no storage_root) --> Metastore Assignment (dev workspace)
                              --> Metastore Assignment (prod workspace)

[workspace-level provider - dev]
  Storage Credential --> External Locations (dev, prod via for_each, force_destroy)
  Catalog (bu1_dev, storage_root=dev container) --> Schema (devx_workshop)
  Grants (catalog + schema for CI/CD SP)
  SQL Warehouse (wh-demo-dev, serverless)
  Git Credential --> Git Repo (dbx-devx-workshop clone)

[workspace-level provider - prod]
  Catalog (bu1_prod, storage_root=prod container) --> Schema (devx_workshop)
  Grants (catalog + schema for CI/CD SP)
  SQL Warehouse (wh-demo-prod, serverless)
  Git Credential --> Git Repo (dbx-devx-workshop clone)

[account-level provider - CI/CD]
  Service Principal --> Workspace Assignments (dev, prod)
    --> time_sleep (30s propagation delay)
      --> OIDC Federation Policies (serialized: env:dev -> env:prod -> branch -> PR)

[github provider]
  Environments (dev, prod)
  Secrets (DATABRICKS_CLIENT_ID, DATABRICKS_HOST per env)
  Variables (DATABRICKS_CATALOG, DATABRICKS_SCHEMA per env)
```

### `depends_on` philosophy

Implicit dependencies (attribute references) handle ordering everywhere except these hidden dependency cases:

- **`databricks_storage_credential` depends_on `databricks_metastore_assignment.this`** -- workspace must have a metastore before creating UC objects.
- **`databricks_sql_endpoint.*` depends_on `databricks_metastore_assignment.*`** -- warehouse needs UC attached.
- **`databricks_catalog.*` depends_on `databricks_external_location.this`** -- catalogs need external locations (which transitively need metastore assignment + storage credential).
- **`databricks_mws_permission_assignment.cicd_*` depends_on `databricks_metastore_assignment.*`** -- account-level permission API requires the workspace to be fully registered; metastore assignment acts as a gate.
- **`databricks_grants.catalog_*` / `databricks_grants.schema_*` depends_on `databricks_mws_permission_assignment.cicd_*`** -- SP must be assigned to workspace before granting privileges.
- **`databricks_repo.*` depends_on `databricks_git_credential.*`** -- git folders need credentials configured first.
- **OIDC federation policies** are chained sequentially (`env_dev` -> `env_prod` -> `branch` -> `pr`) with a 30s `time_sleep` before the first, to avoid concurrent creation failures on the Databricks account API.

Do not add `depends_on` elsewhere unless there is a similar hidden dependency with no attribute-level link.

### Catalog-level storage_root

The metastore has **no `storage_root`** — storage is defined at the catalog level instead (recommended pattern per Databricks docs). Each catalog points to its own container (`dev` or `prod`) via `storage_root`. This eliminates the need for `databricks_metastore_data_access` and avoids the destroy ordering issue where that resource couldn't be deleted before its parent metastore.

### Drift gotchas

- `azurerm_storage_account` must pin `allow_nested_items_to_be_public = false` — Azure tenant policy forces `false` post-create; unset field defaults to `true` and produces perpetual drift.
- `./verify.sh` requires `.env` sourced (auto-handled inside script) — missing `GITHUB_TOKEN` makes `terraform plan -detailed-exitcode` return 2, misreported as drift.

### Scope: serverless-only demos

Bundle demos use serverless pipelines, serverless SQL warehouses, and pipeline-task jobs exclusively. Do not add `databricks_entitlements` (e.g., `allow-cluster-create`) — not needed, and `USER` permission assignment gives implicit workspace-access.

## Project layout

```
providers.tf     -- terraform/provider blocks, version constraints
variables.tf     -- all input variables (with validation on storage_account_name)
main.tf          -- all resources, sequenced by step comments (Steps 1-22)
outputs.tf       -- resource IDs, names, URLs, SP application ID
terraform.tfvars -- variable values (gitignored, contains Azure/Databricks IDs)
.env             -- exports GITHUB_TOKEN from gh auth (gitignored)
```

## Sensitive data

`.gitignore` excludes `*.tfstate`, `*.tfstate.*`, `*.tfvars`, `*.tfvars.json`, `.env`, and plan output files. Never commit these. `terraform.tfvars` is gitignored and contains sandbox/demo Azure and Databricks IDs.

For values needed by post-apply scripts (e.g., `verify.sh`), add a `sensitive = true` output and read via `terraform output -json` + `jq`. Never hardcode UUIDs or IDs directly in scripts checked into git — `terraform.tfvars` and state are gitignored, outputs are the canonical source.

## Provider versions

Pinned with pessimistic constraints: `azurerm ~>4.46`, `databricks ~>1.111`, `github ~>6.11`, `time` (hashicorp, auto-versioned), Terraform `~>1.9`.

## Destroy/recreate notes

Always use `tf destroy` before recreating — never delete Azure resources manually. The metastore, storage credential, and external locations are Databricks account-level resources that survive Azure deletion and require manual `terraform import` to recover.

The GitHub provider requires a `GITHUB_TOKEN` env var. Source from `.env` before running: `source .env && tf apply`.
If you switch GitHub accounts (`gh auth switch`), regenerate `.env` first: `echo "export GITHUB_TOKEN=$(gh auth token)" > .env`.

## Terraform MCP usage

When adding or modifying resources, always use the Terraform MCP server to validate against the latest provider documentation:

1. **Before writing resource blocks**: Use `get_latest_provider_version` to check current versions, then `search_providers` → `get_provider_details` to fetch the full resource docs (argument reference, attribute reference, Azure-specific examples).
2. **Cross-reference with Context7**: Use the `context7` MCP (`resolve-library-id` → `query-docs` for `/databricks/terraform-provider-databricks`) to get source-level examples and guide content that may not appear in the registry docs.
3. **Check capabilities**: Use `get_provider_capabilities` when unsure what resource types exist for a given provider.

This two-source approach (Terraform registry via MCP + Context7 source docs) catches deprecated arguments, new required fields, and Azure-specific patterns that a single source might miss.

## DAIS26 demo assets

The DAIS26 course workspace (MCP/Skills demos over `bu1_dev.mcp_demo`) is wired in via `demos.tf` + `bootstrap/`. Everything is gated on `var.enable_dais26_demos = true`; leaving it false is a no-op so this config is safe to keep in-repo on workspaces that don't need it.

### One-shot deploy

```bash
# 1. Opt in. Gateway now uses a pre-deployed native Databricks FM endpoint
#    (default: databricks-claude-opus-4-7) — no API key needed. Override via
#    var.gateway_model_name if a different FM is desired.
echo 'enable_dais26_demos = true' >> terraform.tfvars

# 2. Apply + bootstrap in one go (two-phase apply handled by run.sh).
./run.sh

# Alternative flags:
./run.sh --dry-run                               # terraform plan only
./run.sh --skip-tf                               # bootstrap-only
./run.sh --dais26-repo /alt/path/to/dais26       # override TF var
```

### Layout

```
demos.tf                          -- All DAIS26 TF resources (count-gated)
bootstrap/
  _lib.sh                         -- Shared helpers, loads `terraform output -json` into env vars
  01_seed_tables.sh               -- Seeds bu1_dev.mcp_demo base tables via aitools CLI
  02_uc_functions.sh              -- Creates UC functions (avg_fare_by_borough, top_zones, trip_summary)
  03_trigger_pipeline.sh          -- Kicks off the SDP pipeline created by TF
  04_lakebase_db.py               -- CREATE DATABASE inside the Lakebase instance (psycopg + OAuth)
  05_app_deploy.sh                -- `databricks sync` + `databricks apps deploy` for custom-mcp
  06_genie_space.py               -- Creates/reuses the Genie space, writes .genie_space_id
  07_rewrite_config.py            -- Renders .mcp.json + gateway files into the DAIS26 repo from TF outputs
  08_smoke_test.sh                -- 5-point smoke test (dbsql, UC func, VS, custom-mcp, gateway)
  sql/                            -- SDP source SQL (pushed to workspace by databricks_notebook)
  templates/                      -- .mcp.json + gateway tftpl templates
run.sh                            -- Orchestrator (two-phase TF apply + bootstrap/*)
```

### Why a two-phase apply

`databricks_vector_search_index.zone_descriptions` binds to a source Delta table that TF does not own. `run.sh` target-applies `databricks_schema.mcp_demo` + `databricks_sql_endpoint.dev`, then runs `01_seed_tables.sh` to materialize `zone_descriptions` (with CDF enabled), then runs the full `terraform apply` so the VS index's dependency is satisfied.

### Generated files in the DAIS26 repo

`bootstrap/07_rewrite_config.py` overwrites these files in `$DAIS26_REPO` — do NOT hand-edit them (any changes will be clobbered on the next deploy):

- `.mcp.json` — MCP server config (warehouse ID, Genie space ID, catalog/schema, custom-mcp URL, lakebase instance/db)
- `gateway/ai-gateway-anthropic.py` — rendered from `templates/gateway-anthropic.py.tftpl`; Databricks SDK `serving_endpoints.query` against the native FM endpoint name
- `gateway/ai-gateway-tracing.py` — rendered from `templates/gateway-tracing.py.tftpl`; same native-FM pattern wrapped in `@mlflow.trace` + `mlflow.genai.evaluate`

### Known risks surfaced during migration

Documented in the plan at `/Users/robby.kiskanyan/.claude/plans/dbx-tf-deploy-simple-dais26-integration.md` (Gotchas section). Summary: SP UUID vs display-name in GRANTs, app warehouse access via Permissions API, `user_api_scopes` preview flag, gateway swapped to native Databricks FM (no external API key, no shard-URL assumption), manual Lakebase CREATE DATABASE, Genie SDK surface drift.
