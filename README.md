# Azure Databricks Workspace Deploy (Simple)

Terraform configuration that deploys two Azure Databricks workspaces (dev + prod) with shared Unity Catalog infrastructure. Designed for demo environments and CI/CD with Databricks Asset Bundles.

## What Gets Deployed

### Shared Azure Infrastructure
- Resource Group
- Databricks Access Connector (System-Assigned Managed Identity)
- Storage Account (ADLS Gen2 with Hierarchical Namespace)
- Storage Containers: `dev`, `prod`, `unity-catalog`
- Role Assignment (Storage Blob Data Contributor → Access Connector)

### Databricks Workspaces
- **Dev workspace** — `dev-eus2-robkisk-tf`
- **Prod workspace** — `prod-eus2-robkisk-tf`
- Both: Premium SKU, public network access, linked to access connector

### Unity Catalog
- Metastore with root storage in the `unity-catalog` container
- Metastore data access credential (access connector, `is_default = true`)
- Metastore assigned to both workspaces
- Storage credential registered from the access connector
- External locations for `dev` and `prod` containers

### SQL Warehouses
- `wh-demo-dev` — serverless SQL warehouse in dev workspace
- `wh-demo-prod` — serverless SQL warehouse in prod workspace

## Prerequisites

1. **Azure CLI** authenticated:
   ```bash
   az login
   az account set --subscription <subscription_id>
   ```

2. **Terraform** >= 1.9

3. **Permissions**: Contributor or Owner on the Azure subscription, plus Databricks account admin access

## Quick Start

```bash
terraform init
terraform plan
terraform apply
```

## Provider Architecture

Three Databricks provider configurations:

| Provider | Alias | Target | Used For |
|----------|-------|--------|----------|
| `databricks.accounts` | `accounts` | `accounts.azuredatabricks.net` | Metastore, data access, workspace assignments |
| `databricks` | (default) | Dev workspace URL | Storage credential, external locations, dev SQL warehouse |
| `databricks.prod` | `prod` | Prod workspace URL | Prod SQL warehouse |

All providers set `azure_tenant_id` explicitly to avoid tenant mismatch with Azure CLI.

## Project Structure

```
providers.tf     — Provider blocks and version constraints
variables.tf     — Input variables (with validation on storage_account_name)
main.tf          — All resources, sequenced by step comments
outputs.tf       — Resource IDs, names, URLs, external location map
terraform.tfvars — Variable values (gitignored)
```

## Cleanup

```bash
terraform destroy
```

The metastore has `force_destroy = true` — this cascades deletion through all child UC objects (catalogs, schemas, tables).

## Provider Versions

- Terraform: `~>1.9`
- azurerm: `~>4.46`
- databricks: `~>1.111`
