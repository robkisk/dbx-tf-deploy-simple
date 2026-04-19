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

output "catalog_storage_root_dev" {
  description = "Storage root of the dev catalog for managed tables"
  value       = databricks_catalog.dev.storage_root
}

output "catalog_storage_root_prod" {
  description = "Storage root of the prod catalog for managed tables"
  value       = databricks_catalog.prod.storage_root
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

# ─── Catalog & Schema Outputs ─────────────────────────────────────────────────

output "catalog_name_dev" {
  description = "Name of the dev Unity Catalog"
  value       = databricks_catalog.dev.name
}

output "catalog_name_prod" {
  description = "Name of the prod Unity Catalog"
  value       = databricks_catalog.prod.name
}

output "schema_name" {
  description = "Schema name used in both catalogs"
  value       = var.schema_name
}

# ─── CI/CD Service Principal Outputs ─────────────────────────────────────────

output "cicd_sp_application_id" {
  description = "Application ID of the CI/CD service principal (use as DATABRICKS_CLIENT_ID GitHub secret)"
  value       = databricks_service_principal.cicd.application_id
}

output "cicd_sp_id" {
  description = "Databricks numeric ID of the CI/CD service principal"
  value       = databricks_service_principal.cicd.id
}

output "databricks_account_id" {
  description = "Databricks account ID (for federation policy API calls in verify.sh)"
  value       = var.databricks_account_id
  sensitive   = true
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

# ─── DAIS26 MCP Demo Outputs ──────────────────────────────────────────────────
# All outputs use try() so disabling demos does not break `terraform output`.
# Consumed by bootstrap/07_rewrite_config.py to render .mcp.json and gateway
# config files in the DAIS26 repo.

output "dais26_enabled" {
  description = "Whether DAIS26 demo assets are materialized"
  value       = var.enable_dais26_demos
}

output "dais26_workspace_host" {
  description = "Workspace host (without trailing slash) for DAIS26 bootstrap scripts"
  value       = "https://${azurerm_databricks_workspace.this.workspace_url}"
}

output "mcp_demo_schema_full" {
  description = "Fully qualified schema name holding DAIS26 demo tables"
  value       = try(local.mcp_demo_schema_full, "")
}

output "sdp_pipeline_id" {
  description = "SDP pipeline ID (use with databricks pipelines start-update to trigger)"
  value       = try(databricks_pipeline.mcp_demo[0].id, "")
}

output "vs_endpoint_name" {
  description = "Vector Search endpoint name"
  value       = try(databricks_vector_search_endpoint.mcp_demo[0].name, "")
}

output "vs_index_name" {
  description = "Vector Search index full name (catalog.schema.index)"
  value       = try(databricks_vector_search_index.zone_descriptions[0].name, "")
}

output "lakebase_instance_name" {
  description = "Lakebase instance name (for databricks lakebase CLI)"
  value       = try(databricks_database_instance.mcp_demo[0].name, "")
}

output "lakebase_host" {
  description = "Lakebase read-write DNS endpoint (for psycopg connections in bootstrap)"
  value       = try(databricks_database_instance.mcp_demo[0].read_write_dns, "")
}

output "lakebase_database_name" {
  description = "PG database name inside the Lakebase instance (created by bootstrap, not TF)"
  value       = var.lakebase_database_name
}

output "custom_mcp_app_url" {
  description = "Custom MCP app base URL — append /mcp for the MCP endpoint"
  value       = try(databricks_app.custom_mcp[0].url, "")
}

output "custom_mcp_sp_client_id" {
  description = "Custom MCP app service principal client_id UUID (use in GRANT statements)"
  value       = try(databricks_app.custom_mcp[0].service_principal_client_id, "")
}

output "gateway_endpoint_name" {
  description = "Databricks-hosted Claude Foundation Model endpoint name (pre-deployed by Databricks, not managed by TF)"
  value       = var.gateway_model_name
}

output "gateway_base_url" {
  description = "Base URL for the Foundation Model endpoint. Use for curl/REST probes (POST /invocations) and as a reference in the gateway demo scripts."
  value       = "https://${azurerm_databricks_workspace.this.workspace_url}/serving-endpoints/${var.gateway_model_name}"
}

output "dais26_repo_path" {
  description = "Local path to the DAIS26 repo — bootstrap scripts use this to locate seed SQL and write config files"
  value       = var.dais26_repo_path
}