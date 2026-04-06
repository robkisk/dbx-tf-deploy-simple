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
- **`databricks_grants.catalog_*` depends_on `databricks_mws_permission_assignment.cicd_*`** -- SP must be assigned to workspace before granting privileges.
- **`databricks_repo.*` depends_on `databricks_git_credential.*`** -- git folders need credentials configured first.
- **OIDC federation policies** are chained sequentially (`env_dev` -> `env_prod` -> `branch` -> `pr`) with a 30s `time_sleep` before the first, to avoid concurrent creation failures on the Databricks account API.

Do not add `depends_on` elsewhere unless there is a similar hidden dependency with no attribute-level link.

### Catalog-level storage_root

The metastore has **no `storage_root`** — storage is defined at the catalog level instead (recommended pattern per Databricks docs). Each catalog points to its own container (`dev` or `prod`) via `storage_root`. This eliminates the need for `databricks_metastore_data_access` and avoids the destroy ordering issue where that resource couldn't be deleted before its parent metastore.

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

## Provider versions

Pinned with pessimistic constraints: `azurerm ~>4.46`, `databricks ~>1.111`, `github ~>6.11`, `time` (hashicorp, auto-versioned), Terraform `~>1.9`.

## Destroy/recreate notes

Always use `tf destroy` before recreating — never delete Azure resources manually. The metastore, storage credential, and external locations are Databricks account-level resources that survive Azure deletion and require manual `terraform import` to recover.

The GitHub provider requires a `GITHUB_TOKEN` env var. Source from `.env` before running: `source .env && tf apply`.

## Terraform MCP usage

When adding or modifying resources, always use the Terraform MCP server to validate against the latest provider documentation:

1. **Before writing resource blocks**: Use `get_latest_provider_version` to check current versions, then `search_providers` → `get_provider_details` to fetch the full resource docs (argument reference, attribute reference, Azure-specific examples).
2. **Cross-reference with Context7**: Use the `context7` MCP (`resolve-library-id` → `query-docs` for `/databricks/terraform-provider-databricks`) to get source-level examples and guide content that may not appear in the registry docs.
3. **Check capabilities**: Use `get_provider_capabilities` when unsure what resource types exist for a given provider.

This two-source approach (Terraform registry via MCP + Context7 source docs) catches deprecated arguments, new required fields, and Azure-specific patterns that a single source might miss.
