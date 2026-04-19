variable "tenant_id" {
  type        = string
  description = "Azure tenant ID"
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "location" {
  type        = string
  description = "Azure region for resources"
}

variable "access_connector_name" {
  type        = string
  description = "Name of the Databricks access connector"
}

variable "storage_account_name" {
  type        = string
  description = "Name of the storage account (must be globally unique)"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters, lowercase letters and numbers only."
  }
}

variable "workspace_name" {
  type        = string
  description = "Name of the Databricks dev workspace"
}

variable "workspace_name_prod" {
  type        = string
  description = "Name of the Databricks prod workspace"
}

variable "databricks_account_id" {
  type        = string
  description = "Databricks account ID"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}

# ─── CI/CD & Unity Catalog Variables ──────────────────────────────────────────

variable "github_repo" {
  type        = string
  description = "GitHub repository in 'owner/repo' format for OIDC federation"
  default     = "robkisk/dbx-devx-workshop"
}

variable "catalog_name_dev" {
  type        = string
  description = "Unity Catalog name for dev environment"
  default     = "bu1_dev"
}

variable "catalog_name_prod" {
  type        = string
  description = "Unity Catalog name for prod environment"
  default     = "bu1_prod"
}

variable "schema_name" {
  type        = string
  description = "Schema name within catalogs"
  default     = "devx_workshop"
}

variable "cicd_sp_display_name" {
  type        = string
  description = "Display name for the CI/CD service principal"
  default     = "sp-robkisk-devx-workshop-cicd"
}

# ─── DAIS26 MCP Demo Variables ────────────────────────────────────────────────
# Everything below is gated on `enable_dais26_demos`. When false, `demos.tf`
# creates zero resources. Set to true on a fresh workspace to materialize the
# MCP demo assets: mcp_demo schema, SDP pipeline, Vector Search, Lakebase,
# custom-mcp app, AI Gateway endpoint, plus per-asset grants.

variable "enable_dais26_demos" {
  type        = bool
  description = "Master toggle for DAIS26 MCP demo assets (demos.tf)"
  default     = false
}

variable "mcp_demo_schema_name" {
  type        = string
  description = "Schema under catalog_name_dev that holds DAIS26 demo tables + functions"
  default     = "mcp_demo"
}

variable "dais26_repo_path" {
  type        = string
  description = "Absolute path to the vibe-coding-databricks-dais26 repo on the local machine. Used by bootstrap scripts to read seed SQL and rewrite .mcp.json + gateway config files after apply."
  default     = "/Users/robby.kiskanyan/dev/dais/vibe-coding-databricks-dais26"
}

variable "custom_mcp_app_name" {
  type        = string
  description = "Name of the custom MCP Databricks App"
  default     = "custom-mcp-demo"
}

variable "custom_mcp_source_workspace_path" {
  type        = string
  description = "Workspace path the custom MCP app is deployed from. Bootstrap script syncs source here before `databricks apps deploy` runs."
  default     = "/Workspace/Users/robby.kiskanyan@databricks.com/custom-mcp-demo"
}

variable "sdp_pipeline_name" {
  type        = string
  description = "Name of the SDP (Spark Declarative Pipelines) pipeline that produces silver + gold taxi tables"
  default     = "mcp_demo_sdp_pipeline"
}

variable "sdp_source_workspace_path" {
  type        = string
  description = "Workspace path the SDP pipeline reads its SQL sources from. Bootstrap syncs these .sql files before TF applies the pipeline."
  default     = "/Workspace/Users/robby.kiskanyan@databricks.com/mcp_demo_pipeline"
}

variable "vs_endpoint_name" {
  type        = string
  description = "Mosaic AI Vector Search endpoint name"
  default     = "mcp-demo-vs-endpoint"
}

variable "vs_index_name" {
  type        = string
  description = "Mosaic AI Vector Search index short name (joined with catalog.schema at runtime)"
  default     = "zone_descriptions_index"
}

variable "vs_embedding_model_endpoint_name" {
  type        = string
  description = "Workspace-provided embedding model endpoint used by the VS index"
  default     = "databricks-gte-large-en"
}

variable "lakebase_instance_name" {
  type        = string
  description = "Lakebase Postgres instance name"
  default     = "mcp-demo-lakebase"
}

variable "lakebase_database_name" {
  type        = string
  description = "Logical PG database created inside the Lakebase instance. Created by bootstrap script (no TF resource covers PG-level CREATE DATABASE)."
  default     = "demo_db"
}

variable "lakebase_capacity" {
  type        = string
  description = "Lakebase capacity unit. Valid: CU_1, CU_2, CU_4, CU_8"
  default     = "CU_2"
}

variable "gateway_model_name" {
  type        = string
  description = "Databricks-hosted Claude Foundation Model endpoint name. Pre-deployed in every workspace — no TF resource or external API key. Pick one from `databricks serving-endpoints list` output (e.g. databricks-claude-opus-4-7, databricks-claude-sonnet-4-6)."
  default     = "databricks-claude-opus-4-7"
}