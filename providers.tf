terraform {
  required_version = "~>1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.9"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~>1.81"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

provider "databricks" {
  host = "https://${azurerm_databricks_workspace.this.workspace_url}"
}