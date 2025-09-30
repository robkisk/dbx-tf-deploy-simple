# Step 1: Create Resource Group
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Step 2: Create Access Connector (Managed Identity for Unity Catalog)
resource "azurerm_databricks_access_connector" "this" {
  name                = var.access_connector_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }

  depends_on = [azurerm_resource_group.this]
}

# Step 3: Create Storage Account with Hierarchical Namespace
resource "azurerm_storage_account" "this" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  tags                     = var.tags
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true

  depends_on = [azurerm_resource_group.this]
}

# Step 4: Assign Storage Blob Data Contributor Role to Access Connector
resource "azurerm_role_assignment" "storage_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id

  depends_on = [
    azurerm_storage_account.this,
    azurerm_databricks_access_connector.this
  ]
}

# Step 5: Create Databricks Workspace
resource "azurerm_databricks_workspace" "this" {
  name                        = var.workspace_name
  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  sku                         = "premium"
  tags                        = var.tags
  managed_resource_group_name = "${var.resource_group_name}-managed"

  # Link the access connector for Unity Catalog support
  access_connector_id              = azurerm_databricks_access_connector.this.id
  default_storage_firewall_enabled = false

  depends_on = [
    azurerm_resource_group.this,
    azurerm_databricks_access_connector.this,
    azurerm_storage_account.this,
    azurerm_role_assignment.storage_contributor
  ]
}