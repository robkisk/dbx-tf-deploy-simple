terraform {
  required_version = "~>1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.46"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~>1.113"
    }
    github = {
      source  = "integrations/github"
      version = "~>6.11"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# Account-level provider for metastore operations
provider "databricks" {
  alias           = "accounts"
  host            = "https://accounts.azuredatabricks.net"
  account_id      = var.databricks_account_id
  azure_tenant_id = var.tenant_id
}

# Workspace-level provider for dev workspace
provider "databricks" {
  host            = "https://${azurerm_databricks_workspace.this.workspace_url}"
  azure_tenant_id = var.tenant_id
}

# GitHub provider for managing Actions secrets/variables
# Authenticates via GITHUB_TOKEN env var
provider "github" {
  owner = local.github_owner
}

# Workspace-level provider for prod workspace
provider "databricks" {
  alias           = "prod"
  host            = "https://${azurerm_databricks_workspace.prod.workspace_url}"
  azure_tenant_id = var.tenant_id
}