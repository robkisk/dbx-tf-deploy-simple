# Simple Azure Databricks Workspace Demo

A minimal "hello world" Terraform configuration for deploying an Azure Databricks workspace with Unity Catalog support.

## Overview

This demo creates a basic Azure Databricks workspace with the minimum required resources:
- Resource Group
- Databricks Access Connector (Managed Identity)
- Storage Account with Hierarchical Namespace
- Role Assignment for storage access
- Databricks Premium Workspace

**Key Features:**
- ✅ No VNet injection (uses default networking)
- ✅ Public network access enabled
- ✅ Unity Catalog ready
- ✅ Minimal configuration for learning purposes

## Prerequisites

1. **Azure CLI** installed and authenticated:
   ```bash
   az login
   az account set --subscription edd4cc45-85c7-4aec-8bf5-648062d519bf
   ```

2. **Terraform** installed (version ~> 1.9):
   ```bash
   terraform version
   ```

3. **Permissions**: Ensure you have Contributor or Owner role on the subscription

## Project Structure

```
demo/
├── README.md              # This file
├── DEPLOYMENT_STEPS.md    # Detailed deployment tracking
├── providers.tf           # Provider configuration
├── variables.tf           # Input variable definitions
├── main.tf               # Resource definitions
├── outputs.tf            # Output values
└── terraform.tfvars      # Variable values (configured for sandbox)
```

## Quick Start

### 1. Initialize Terraform
```bash
cd /Users/robby.kiskanyan/dev/terraform/demo
terraform init
```

### 2. Review the Plan
```bash
terraform plan
```

### 3. Deploy Resources
```bash
terraform apply
```
Type `yes` when prompted to confirm.

### 4. View Outputs
```bash
terraform output
```

Expected outputs:
- Workspace URL
- Resource IDs
- Storage account details
- Access connector information

## Resource Details

### Resource Group
- **Name**: `databricks-eus2-robkisk-rg-tf`
- **Location**: East US 2

### Access Connector
- **Name**: `ext-storage-mi-acc-robkisk-tf`
- **Type**: System-Assigned Managed Identity
- **Purpose**: Authenticates Databricks to storage for Unity Catalog

### Storage Account
- **Name**: `storaccrobkisktf`
- **Features**:
  - Hierarchical Namespace: Enabled (ADLS Gen2)
  - Tier: Standard
  - Replication: LRS
  - Network: Public access (default)

### Databricks Workspace
- **Name**: `dev-eus2-robkisk-tf`
- **SKU**: Premium
- **Network**: Default (no custom VNet)
- **Unity Catalog**: Access connector linked

## Architecture Patterns Used

Based on comprehensive review of Azure Databricks patterns in the codebase:

1. **Access Connector Pattern**: Follows `adb-uc-metastore` module pattern for managed identity
2. **Storage Configuration**: Uses `is_hns_enabled = true` for ADLS Gen2 compatibility
3. **Role Assignment**: Implements "Storage Blob Data Contributor" pattern
4. **Workspace Linking**: Connects access connector via `access_connector_id`
5. **Dependency Management**: Explicit `depends_on` for proper resource ordering

## Verification

After deployment, verify resources using Azure CLI:

```bash
# Verify Resource Group
az group show --name databricks-eus2-robkisk-rg-tf

# Verify Databricks Workspace
az databricks workspace show \
  --resource-group databricks-eus2-robkisk-rg-tf \
  --name dev-eus2-robkisk-tf

# Verify Storage Account
az storage account show \
  --name storaccrobkisktf \
  --resource-group databricks-eus2-robkisk-rg-tf

# Verify Access Connector
az databricks access-connector show \
  --resource-group databricks-eus2-robkisk-rg-tf \
  --name ext-storage-mi-acc-robkisk-tf
```

## Cleanup

To remove all deployed resources:

```bash
terraform destroy
```
Type `yes` when prompted to confirm.

**Note**: This will delete all resources including the workspace and storage account.

## Configuration Details

### Environment
- **Tenant ID**: bf465dc7-3bc8-4944-b018-092572b5c20d
- **Subscription**: edd4cc45-85c7-4aec-8bf5-648062d519bf
- **Region**: East US 2

### Provider Versions
- **terraform**: ~> 1.9
- **azurerm**: ~> 4.9
- **databricks**: ~> 1.81

## Notes

- This is a **demo configuration** optimized for simplicity
- Not recommended for production use without additional security hardening
- Public network access is enabled for ease of initial access
- No VNet injection keeps the configuration minimal
- Unity Catalog support is configured but not activated (requires metastore)

## Next Steps

After deployment, you can:

1. **Access the workspace**: Use the `workspace_url` output
2. **Configure Unity Catalog**: Create metastore and catalogs
3. **Create clusters**: Use the Databricks UI or Terraform
4. **Add security**: Implement private endpoints, VNet injection, etc.

## Troubleshooting

### Storage Account Name Conflict
If `storaccrobkisktf` is already taken (globally unique), update in `terraform.tfvars`:
```hcl
storage_account_name = "storaccrobkisktf2"  # Must be unique
```

### Authentication Issues
Ensure Azure CLI is authenticated:
```bash
az account show
az account set --subscription edd4cc45-85c7-4aec-8bf5-648062d519bf
```

### Provider Download Issues
```bash
terraform init -upgrade
```

## References

- [Azure Databricks Documentation](https://learn.microsoft.com/en-us/azure/databricks/)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Terraform Databricks Provider](https://registry.terraform.io/providers/databricks/databricks/latest/docs)
- Project CLAUDE.md for detailed patterns and best practices