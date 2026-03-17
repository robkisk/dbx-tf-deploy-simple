# Azure Databricks Workspace Deploy (Simple)

Terraform configuration that deploys two Azure Databricks workspaces (dev + prod) with shared Unity Catalog, CI/CD service principal, GitHub Actions integration, and git repo cloning. Designed for demo environments showcasing CI/CD with Databricks Asset Bundles.

## What Gets Deployed

### Shared Azure Infrastructure
- Resource Group
- Databricks Access Connector (System-Assigned Managed Identity)
- Storage Account (ADLS Gen2 with Hierarchical Namespace)
- Storage Containers: `dev`, `prod`
- Role Assignment (Storage Blob Data Contributor -> Access Connector)

### Databricks Workspaces
- **Dev workspace** -- `dev-eus2-robkisk-tf`
- **Prod workspace** -- `prod-eus2-robkisk-tf`
- Both: Premium SKU, public network access, linked to access connector

### Unity Catalog
- Metastore (no storage_root -- defined at catalog level instead)
- Metastore assigned to both workspaces
- Storage credential registered from the access connector
- External locations for `dev` and `prod` containers
- Catalogs: `bu1_dev` (storage_root=dev container), `bu1_prod` (storage_root=prod container), both with `force_destroy`
- Schemas: `devx_workshop` in each catalog (with `force_destroy`)

### CI/CD Service Principal
- `sp-robkisk-devx-workshop-cicd` at account level
- Assigned to both workspaces with USER permissions
- 4 OIDC federation policies for GitHub Actions (environment:dev, environment:prod, branch refs, pull_request)
- UC grants: `USE_CATALOG`, `USE_SCHEMA`, `CREATE_SCHEMA`, `CREATE_TABLE` on catalogs, `ALL_PRIVILEGES` on schemas

### SQL Warehouses
- `wh-demo-dev` -- serverless SQL warehouse in dev workspace
- `wh-demo-prod` -- serverless SQL warehouse in prod workspace

### Git Repo Integration
- `dbx-devx-workshop` cloned into `/Repos/robkisk/dbx-devx-workshop` in both workspaces

### GitHub Actions Configuration
- GitHub environments: `dev`, `prod`
- Repo secret: `DATABRICKS_CLIENT_ID` (SP application ID)
- Environment secrets: `DATABRICKS_HOST` (workspace URLs)
- Environment variables: `DATABRICKS_CATALOG`, `DATABRICKS_SCHEMA`

## Prerequisites

1. **Azure CLI** authenticated:
   ```bash
   az login
   az account set --subscription <subscription_id>
   ```

2. **Terraform** >= 1.9

3. **Permissions**: Contributor or Owner on the Azure subscription, plus Databricks account admin access

4. **GitHub token**: `GITHUB_TOKEN` env var set for the GitHub provider

## Quick Start

```bash
source .env         # loads GITHUB_TOKEN from gh auth
terraform init
terraform plan
terraform apply
```

## Provider Architecture

| Provider | Alias | Target | Used For |
|----------|-------|--------|----------|
| `azurerm` | -- | Azure subscription | All Azure resources |
| `databricks.accounts` | `accounts` | `accounts.azuredatabricks.net` | Metastore, SP, OIDC, workspace assignments |
| `databricks` | (default) | Dev workspace URL | UC objects, dev catalog/schema/grants, dev SQL warehouse, dev git repo |
| `databricks.prod` | `prod` | Prod workspace URL | Prod catalog/schema/grants, prod SQL warehouse, prod git repo |
| `github` | -- | GitHub API | Environments, secrets, variables |

All Databricks providers set `azure_tenant_id` explicitly to avoid tenant mismatch with Azure CLI.

## Project Structure

```
providers.tf     -- Provider blocks and version constraints
variables.tf     -- Input variables (with validation on storage_account_name)
main.tf          -- All resources, sequenced by step comments (Steps 1-22)
outputs.tf       -- Resource IDs, names, URLs, SP application ID
terraform.tfvars -- Variable values (gitignored)
```

## Cleanup

```bash
terraform destroy
```

The metastore has `force_destroy = true` -- this cascades deletion through all child UC objects (catalogs, schemas, tables). Always use `terraform destroy` rather than deleting Azure resources manually.

## Provider Versions

- Terraform: `~>1.9`
- azurerm: `~>4.46`
- databricks: `~>1.111`
- github: `~>6.11`
