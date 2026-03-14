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
}

# Step 3b: Create Storage Containers
resource "azurerm_storage_container" "containers" {
  for_each              = toset(["dev", "prod"])
  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Step 4: Assign Storage Blob Data Contributor Role to Access Connector
resource "azurerm_role_assignment" "storage_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id
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
}

# Step 5b: Create Databricks Prod Workspace
resource "azurerm_databricks_workspace" "prod" {
  name                        = var.workspace_name_prod
  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  sku                         = "premium"
  tags                        = var.tags
  managed_resource_group_name = "${var.resource_group_name}-prod-managed"

  # Link the same access connector for Unity Catalog support
  access_connector_id              = azurerm_databricks_access_connector.this.id
  default_storage_firewall_enabled = false
}

# ─── Unity Catalog ────────────────────────────────────────────────────────────

# Step 6: Create container for metastore managed storage
resource "azurerm_storage_container" "metastore" {
  name                  = "unity-catalog"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Step 7: Create Unity Catalog Metastore
resource "databricks_metastore" "this" {
  provider = databricks.accounts
  name     = "${var.workspace_name}-metastore"
  storage_root = format("abfss://%s@%s.dfs.core.windows.net/",
    azurerm_storage_container.metastore.name,
    azurerm_storage_account.this.name
  )
  region        = var.location
  force_destroy = true
}

# Step 7b: Configure root storage credential for the metastore
resource "databricks_metastore_data_access" "this" {
  provider     = databricks.accounts
  metastore_id = databricks_metastore.this.id
  name         = "metastore-root-credential"
  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.this.id
  }
  is_default = true
}

# Step 8: Assign Metastore to Workspaces
resource "databricks_metastore_assignment" "this" {
  provider     = databricks.accounts
  workspace_id = azurerm_databricks_workspace.this.workspace_id
  metastore_id = databricks_metastore.this.id
}

resource "databricks_metastore_assignment" "prod" {
  provider     = databricks.accounts
  workspace_id = azurerm_databricks_workspace.prod.workspace_id
  metastore_id = databricks_metastore.this.id
}

# Step 9: Register Access Connector as Storage Credential
resource "databricks_storage_credential" "this" {
  name = var.access_connector_name
  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.this.id
  }
  comment = "Managed by Terraform"

  # Metastore must be assigned before creating workspace-level UC objects
  depends_on = [databricks_metastore_assignment.this]
}

# Step 10: Create External Locations for dev and prod containers
resource "databricks_external_location" "this" {
  for_each = azurerm_storage_container.containers

  name = each.key
  url = format("abfss://%s@%s.dfs.core.windows.net/",
    each.value.name,
    azurerm_storage_account.this.name
  )
  credential_name = databricks_storage_credential.this.id
  comment         = "Managed by Terraform"
}

# ─── SQL Warehouses ───────────────────────────────────────────────────────────

# Step 11: Create serverless SQL warehouse in dev workspace
resource "databricks_sql_endpoint" "dev" {
  name                      = "wh-demo-dev"
  cluster_size              = "2X-Small"
  max_num_clusters          = 1
  auto_stop_mins            = 10
  enable_serverless_compute = true
  enable_photon             = true
  warehouse_type            = "PRO"

  depends_on = [databricks_metastore_assignment.this]
}

# Step 12: Create serverless SQL warehouse in prod workspace
resource "databricks_sql_endpoint" "prod" {
  provider                  = databricks.prod
  name                      = "wh-demo-prod"
  cluster_size              = "2X-Small"
  max_num_clusters          = 1
  auto_stop_mins            = 10
  enable_serverless_compute = true
  enable_photon             = true
  warehouse_type            = "PRO"

  depends_on = [databricks_metastore_assignment.prod]
}