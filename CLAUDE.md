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

- **`databricks.accounts`** (aliased) -- points at `accounts.azuredatabricks.net` for account-level operations: metastore, metastore data access, workspace assignments.
- **Default `databricks`** (no alias) -- points at the dev workspace URL for workspace-level UC objects and dev SQL warehouse.
- **`databricks.prod`** (aliased) -- points at the prod workspace URL for prod SQL warehouse.

All Databricks providers set `azure_tenant_id` explicitly to avoid tenant mismatch when authenticating via Azure CLI.

### Resource dependency chain

```
Resource Group
  +-- Access Connector (SystemAssigned MI)
  +-- Storage Account (HNS / ADLS Gen2)
        +-- Storage Containers (dev, prod via for_each/toset)
        +-- Metastore Container (unity-catalog)
  +-- Role Assignment (Storage Blob Data Contributor -> Access Connector)
  +-- Databricks Dev Workspace (premium, linked to Access Connector)
  +-- Databricks Prod Workspace (premium, linked to Access Connector)

[account-level provider]
  Metastore --> Metastore Data Access (root credential, is_default=true)
           --> Metastore Assignment (dev workspace)
           --> Metastore Assignment (prod workspace)

[workspace-level provider - dev]
  Storage Credential --> External Locations (dev, prod via for_each)
  Catalog (bu1_dev) --> Schema (devx_workshop)
  Grants (catalog + schema for CI/CD SP)
  SQL Warehouse (wh-demo-dev, serverless)
  Git Repo (dbx-devx-workshop clone)

[workspace-level provider - prod]
  Catalog (bu1_prod) --> Schema (devx_workshop)
  Grants (catalog + schema for CI/CD SP)
  SQL Warehouse (wh-demo-prod, serverless)
  Git Repo (dbx-devx-workshop clone)

[account-level provider - CI/CD]
  Service Principal --> Workspace Assignments (dev, prod)
                   --> OIDC Federation Policies (env:dev, env:prod, branch, PR)

[github provider]
  Environments (dev, prod)
  Secrets (DATABRICKS_CLIENT_ID, DATABRICKS_HOST per env)
  Variables (DATABRICKS_CATALOG, DATABRICKS_SCHEMA per env)
```

### `depends_on` philosophy

Implicit dependencies (attribute references) handle ordering everywhere except these hidden dependency cases:

- **`databricks_storage_credential` depends_on `databricks_metastore_assignment.this`** -- workspace must have a metastore before creating UC objects.
- **`databricks_sql_endpoint.dev` depends_on `databricks_metastore_assignment.this`** -- warehouse needs UC attached.
- **`databricks_sql_endpoint.prod` depends_on `databricks_metastore_assignment.prod`** -- same for prod.
- **`databricks_catalog.*` depends_on `databricks_metastore_assignment.*`** -- catalogs need metastore assigned.
- **`databricks_grants.catalog_*` depends_on `databricks_mws_permission_assignment.cicd_*`** -- SP must be assigned to workspace before granting privileges.
- **`databricks_repo.*` depends_on `databricks_metastore_assignment.*`** -- git folders need workspace ready.

Do not add `depends_on` elsewhere unless there is a similar hidden dependency with no attribute-level link.

### Metastore root credential

A metastore with `storage_root` **must** have a `databricks_metastore_data_access` with `is_default = true`. Without it, managed tables and SDP pipelines fail with `DAC_DOES_NOT_EXIST`. This binds the access connector's managed identity as the credential the metastore uses to access its root storage.

## Project layout

```
providers.tf    -- terraform/provider blocks, version constraints
variables.tf    -- all input variables (with validation on storage_account_name)
main.tf         -- all resources, sequenced by step comments
outputs.tf      -- resource IDs, names, URLs, external location map
terraform.tfvars -- variable values (gitignored, contains Azure/Databricks IDs)
```

## Sensitive data

`.gitignore` excludes `*.tfstate`, `*.tfstate.*`, `*.tfvars`, `*.tfvars.json`, `.env`, and plan output files. Never commit these. `terraform.tfvars` is gitignored and contains sandbox/demo Azure and Databricks IDs.

## Provider versions

Pinned with pessimistic constraints: `azurerm ~>4.46`, `databricks ~>1.111`, `github ~>6.11`, Terraform `~>1.9`.

## Destroy/recreate notes

Always use `tf destroy` before recreating — never delete Azure resources manually. The metastore, storage credential, and external locations are Databricks account-level resources that survive Azure deletion and require manual `terraform import` to recover.

On destroy, `databricks_metastore_data_access` may fail because Terraform tries to delete it before the metastore. Fix: `terraform state rm databricks_metastore_data_access.this` then re-run destroy. The metastore's `force_destroy` cascades the cleanup.

The GitHub provider requires a `GITHUB_TOKEN` env var for authentication.

## Terraform MCP usage

When adding or modifying resources, always use the Terraform MCP server to validate against the latest provider documentation:

1. **Before writing resource blocks**: Use `get_latest_provider_version` to check current versions, then `search_providers` → `get_provider_details` to fetch the full resource docs (argument reference, attribute reference, Azure-specific examples).
2. **Cross-reference with Context7**: Use the `context7` MCP (`resolve-library-id` → `query-docs` for `/databricks/terraform-provider-databricks`) to get source-level examples and guide content that may not appear in the registry docs.
3. **Check capabilities**: Use `get_provider_capabilities` when unsure what resource types exist for a given provider.

This two-source approach (Terraform registry via MCP + Context7 source docs) catches deprecated arguments, new required fields, and Azure-specific patterns that a single source might miss.
