locals {
  tags = merge(var.tags, {
    RemoveAfter = formatdate("YYYY-MM-DD", timeadd(plantimestamp(), "720h"))
  })
  github_owner      = split("/", var.github_repo)[0]
  github_repository = split("/", var.github_repo)[1]
}

# Step 1: Create Resource Group
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

# Step 2: Create Access Connector (Managed Identity for Unity Catalog)
resource "azurerm_databricks_access_connector" "this" {
  name                = var.access_connector_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags

  identity {
    type = "SystemAssigned"
  }
}

# Step 3: Create Storage Account with Hierarchical Namespace
resource "azurerm_storage_account" "this" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  tags                     = local.tags
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
  tags                        = local.tags
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
  tags                        = local.tags
  managed_resource_group_name = "${var.resource_group_name}-prod-managed"

  # Link the same access connector for Unity Catalog support
  access_connector_id              = azurerm_databricks_access_connector.this.id
  default_storage_firewall_enabled = false
}

# ─── Unity Catalog ────────────────────────────────────────────────────────────

# Step 6: Create Unity Catalog Metastore (no storage_root — set at catalog level instead)
resource "databricks_metastore" "this" {
  provider      = databricks.accounts
  name          = "${var.workspace_name}-metastore"
  region        = var.location
  force_destroy = true
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
  force_destroy   = true
}

# ─── Unity Catalog: Catalogs & Schemas ────────────────────────────────────────

# Step 11: Create catalogs for dev and prod
resource "databricks_catalog" "dev" {
  name          = var.catalog_name_dev
  force_destroy = true
  comment       = "Dev catalog - managed by Terraform"
  storage_root = format("abfss://%s@%s.dfs.core.windows.net/",
    azurerm_storage_container.containers["dev"].name,
    azurerm_storage_account.this.name
  )

  depends_on = [databricks_external_location.this]
}

resource "databricks_catalog" "prod" {
  provider      = databricks.prod
  name          = var.catalog_name_prod
  force_destroy = true
  comment       = "Prod catalog - managed by Terraform"
  storage_root = format("abfss://%s@%s.dfs.core.windows.net/",
    azurerm_storage_container.containers["prod"].name,
    azurerm_storage_account.this.name
  )

  depends_on = [databricks_external_location.this]
}

# Step 12: Create schemas within each catalog
resource "databricks_schema" "dev" {
  catalog_name  = databricks_catalog.dev.name
  name          = var.schema_name
  force_destroy = true
  comment       = "Dev schema - managed by Terraform"
}

resource "databricks_schema" "prod" {
  provider      = databricks.prod
  catalog_name  = databricks_catalog.prod.name
  name          = var.schema_name
  force_destroy = true
  comment       = "Prod schema - managed by Terraform"
}

# ─── CI/CD Service Principal & OIDC Federation ───────────────────────────────

# Step 13: Create service principal for GitHub Actions CI/CD
resource "databricks_service_principal" "cicd" {
  provider     = databricks.accounts
  display_name = var.cicd_sp_display_name
  active       = true
}

# Step 14: Assign SP to both workspaces
resource "databricks_mws_permission_assignment" "cicd_dev" {
  provider     = databricks.accounts
  workspace_id = azurerm_databricks_workspace.this.workspace_id
  principal_id = databricks_service_principal.cicd.id
  permissions  = ["USER"]
  depends_on   = [databricks_metastore_assignment.this]
}

resource "databricks_mws_permission_assignment" "cicd_prod" {
  provider     = databricks.accounts
  workspace_id = azurerm_databricks_workspace.prod.workspace_id
  principal_id = databricks_service_principal.cicd.id
  permissions  = ["USER"]
  depends_on   = [databricks_metastore_assignment.prod]
}

# Wait for SP to fully propagate before creating federation policies
resource "time_sleep" "sp_propagation" {
  depends_on      = [databricks_service_principal.cicd]
  create_duration = "30s"
}

# Step 15: OIDC federation policies for GitHub Actions
#   - environment:dev/prod — for jobs using GitHub environments
#   - branch refs — for workflow_dispatch and push triggers
#   - pull_request — for PR validation workflows
resource "databricks_service_principal_federation_policy" "github_env_dev" {
  provider             = databricks.accounts
  service_principal_id = databricks_service_principal.cicd.id
  policy_id            = "github-oidc-env-dev"
  oidc_policy = {
    issuer        = "https://token.actions.githubusercontent.com"
    audiences     = ["https://accounts.azuredatabricks.net/oidc/v1/token"]
    subject       = "repo:${var.github_repo}:environment:dev"
    subject_claim = "sub"
  }
  depends_on = [time_sleep.sp_propagation]
}

resource "databricks_service_principal_federation_policy" "github_env_prod" {
  provider             = databricks.accounts
  service_principal_id = databricks_service_principal.cicd.id
  policy_id            = "github-oidc-env-prod"
  oidc_policy = {
    issuer        = "https://token.actions.githubusercontent.com"
    audiences     = ["https://accounts.azuredatabricks.net/oidc/v1/token"]
    subject       = "repo:${var.github_repo}:environment:prod"
    subject_claim = "sub"
  }
  depends_on = [databricks_service_principal_federation_policy.github_env_dev]
}

resource "databricks_service_principal_federation_policy" "github_branch" {
  provider             = databricks.accounts
  service_principal_id = databricks_service_principal.cicd.id
  policy_id            = "github-oidc-branch"
  oidc_policy = {
    issuer        = "https://token.actions.githubusercontent.com"
    audiences     = ["https://accounts.azuredatabricks.net/oidc/v1/token"]
    subject       = "repo:${var.github_repo}:ref:refs/heads/*"
    subject_claim = "sub"
  }
  depends_on = [databricks_service_principal_federation_policy.github_env_prod]
}

resource "databricks_service_principal_federation_policy" "github_pr" {
  provider             = databricks.accounts
  service_principal_id = databricks_service_principal.cicd.id
  policy_id            = "github-oidc-pr"
  oidc_policy = {
    issuer        = "https://token.actions.githubusercontent.com"
    audiences     = ["https://accounts.azuredatabricks.net/oidc/v1/token"]
    subject       = "repo:${var.github_repo}:pull_request"
    subject_claim = "sub"
  }
  depends_on = [databricks_service_principal_federation_policy.github_branch]
}

# Step 16: Grant SP access to catalogs and schemas
resource "databricks_grants" "catalog_dev" {
  catalog = databricks_catalog.dev.name

  grant {
    principal  = databricks_service_principal.cicd.application_id
    privileges = ["USE_CATALOG", "USE_SCHEMA", "CREATE_SCHEMA", "CREATE_TABLE"]
  }

  depends_on = [databricks_mws_permission_assignment.cicd_dev]
}

resource "databricks_grants" "catalog_prod" {
  provider = databricks.prod
  catalog  = databricks_catalog.prod.name

  grant {
    principal  = databricks_service_principal.cicd.application_id
    privileges = ["USE_CATALOG", "USE_SCHEMA", "CREATE_SCHEMA", "CREATE_TABLE"]
  }

  depends_on = [databricks_mws_permission_assignment.cicd_prod]
}

resource "databricks_grants" "schema_dev" {
  schema = "${databricks_catalog.dev.name}.${databricks_schema.dev.name}"

  grant {
    principal  = databricks_service_principal.cicd.application_id
    privileges = ["ALL_PRIVILEGES"]
  }

  depends_on = [databricks_mws_permission_assignment.cicd_dev]
}

resource "databricks_grants" "schema_prod" {
  provider = databricks.prod
  schema   = "${databricks_catalog.prod.name}.${databricks_schema.prod.name}"

  grant {
    principal  = databricks_service_principal.cicd.application_id
    privileges = ["ALL_PRIVILEGES"]
  }

  depends_on = [databricks_mws_permission_assignment.cicd_prod]
}

# ─── SQL Warehouses ───────────────────────────────────────────────────────────

# Step 17: Create serverless SQL warehouse in dev workspace
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

# Step 18: Create serverless SQL warehouse in prod workspace
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

# ─── Git Repo Integration ────────────────────────────────────────────────────

# Step 18b: Configure Git credentials (uses GITHUB_TOKEN env var automatically)
resource "databricks_git_credential" "dev" {
  git_username = local.github_owner
  git_provider = "gitHub"
  force        = true
}

resource "databricks_git_credential" "prod" {
  provider     = databricks.prod
  git_username = local.github_owner
  git_provider = "gitHub"
  force        = true
}

# Step 18c: Clone workshop repo into both workspaces
resource "databricks_repo" "dev" {
  url  = "https://github.com/${var.github_repo}.git"
  path = "/Repos/${var.github_repo}"

  depends_on = [databricks_git_credential.dev]
}

resource "databricks_repo" "prod" {
  provider = databricks.prod
  url      = "https://github.com/${var.github_repo}.git"
  path     = "/Repos/${var.github_repo}"

  depends_on = [databricks_git_credential.prod]
}

# ─── GitHub Actions Configuration ─────────────────────────────────────────────

# Step 19: Create GitHub environments
resource "github_repository_environment" "dev" {
  repository  = local.github_repository
  environment = "dev"
}

resource "github_repository_environment" "prod" {
  repository  = local.github_repository
  environment = "prod"
}

# Step 20: Repo-level secret — SP application ID for OIDC auth
resource "github_actions_secret" "databricks_client_id" {
  repository      = local.github_repository
  secret_name     = "DATABRICKS_CLIENT_ID"
  plaintext_value = databricks_service_principal.cicd.application_id
}

# Step 21: Environment secrets — workspace host URLs
resource "github_actions_environment_secret" "dev_host" {
  repository      = local.github_repository
  environment     = github_repository_environment.dev.environment
  secret_name     = "DATABRICKS_HOST"
  plaintext_value = "https://${azurerm_databricks_workspace.this.workspace_url}"
}

resource "github_actions_environment_secret" "prod_host" {
  repository      = local.github_repository
  environment     = github_repository_environment.prod.environment
  secret_name     = "DATABRICKS_HOST"
  plaintext_value = "https://${azurerm_databricks_workspace.prod.workspace_url}"
}

# Step 22: Environment variables — catalog and schema names
resource "github_actions_environment_variable" "dev_catalog" {
  repository    = local.github_repository
  environment   = github_repository_environment.dev.environment
  variable_name = "DATABRICKS_CATALOG"
  value         = databricks_catalog.dev.name
}

resource "github_actions_environment_variable" "dev_schema" {
  repository    = local.github_repository
  environment   = github_repository_environment.dev.environment
  variable_name = "DATABRICKS_SCHEMA"
  value         = var.schema_name
}

resource "github_actions_environment_variable" "prod_catalog" {
  repository    = local.github_repository
  environment   = github_repository_environment.prod.environment
  variable_name = "DATABRICKS_CATALOG"
  value         = databricks_catalog.prod.name
}

resource "github_actions_environment_variable" "prod_schema" {
  repository    = local.github_repository
  environment   = github_repository_environment.prod.environment
  variable_name = "DATABRICKS_SCHEMA"
  value         = var.schema_name
}