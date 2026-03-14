output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.this.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.this.id
}

output "access_connector_name" {
  description = "Name of the Databricks access connector"
  value       = azurerm_databricks_access_connector.this.name
}

output "access_connector_id" {
  description = "ID of the Databricks access connector"
  value       = azurerm_databricks_access_connector.this.id
}

output "access_connector_principal_id" {
  description = "Principal ID of the access connector's managed identity"
  value       = azurerm_databricks_access_connector.this.identity[0].principal_id
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.this.id
}

output "storage_account_primary_dfs_endpoint" {
  description = "Primary DFS endpoint for ADLS Gen2"
  value       = azurerm_storage_account.this.primary_dfs_endpoint
}

output "workspace_name" {
  description = "Name of the Databricks dev workspace"
  value       = azurerm_databricks_workspace.this.name
}

output "workspace_id" {
  description = "ID of the Databricks dev workspace"
  value       = azurerm_databricks_workspace.this.id
}

output "workspace_url" {
  description = "URL of the Databricks dev workspace"
  value       = "https://${azurerm_databricks_workspace.this.workspace_url}/"
}

output "workspace_workspace_id" {
  description = "Workspace ID (numeric) of the dev workspace"
  value       = azurerm_databricks_workspace.this.workspace_id
}

output "workspace_name_prod" {
  description = "Name of the Databricks prod workspace"
  value       = azurerm_databricks_workspace.prod.name
}

output "workspace_id_prod" {
  description = "ID of the Databricks prod workspace"
  value       = azurerm_databricks_workspace.prod.id
}

output "workspace_url_prod" {
  description = "URL of the Databricks prod workspace"
  value       = "https://${azurerm_databricks_workspace.prod.workspace_url}/"
}

output "workspace_workspace_id_prod" {
  description = "Workspace ID (numeric) of the prod workspace"
  value       = azurerm_databricks_workspace.prod.workspace_id
}

# ─── Unity Catalog Outputs ────────────────────────────────────────────────────

output "metastore_id" {
  description = "ID of the Unity Catalog metastore"
  value       = databricks_metastore.this.id
}

output "metastore_storage_root" {
  description = "Storage root of the metastore for managed tables"
  value = format("abfss://%s@%s.dfs.core.windows.net/",
    azurerm_storage_container.metastore.name,
    azurerm_storage_account.this.name
  )
}

output "storage_credential_name" {
  description = "Name of the storage credential for Unity Catalog"
  value       = databricks_storage_credential.this.name
}

output "external_locations" {
  description = "External location URLs for dev and prod containers"
  value = {
    for k, v in databricks_external_location.this : k => v.url
  }
}

# ─── SQL Warehouse Outputs ────────────────────────────────────────────────────

output "sql_warehouse_dev_id" {
  description = "ID of the dev SQL warehouse"
  value       = databricks_sql_endpoint.dev.id
}

output "sql_warehouse_prod_id" {
  description = "ID of the prod SQL warehouse"
  value       = databricks_sql_endpoint.prod.id
}