# ─── DAIS26 MCP Demo Assets ───────────────────────────────────────────────────
# All resources here are gated on `var.enable_dais26_demos`. When the flag is
# false, `count = 0` materializes nothing — safe to keep in-repo on workspaces
# that don't need the demo assets.
#
# TF owns everything that has a first-class provider resource. Imperative steps
# (data seed, app source-deploy, Lakebase PG database create, Genie space,
# config-file rewrite) live in `bootstrap/*`.

locals {
  dais26               = var.enable_dais26_demos ? 1 : 0
  mcp_demo_schema_full = var.enable_dais26_demos ? "${databricks_catalog.dev.name}.${databricks_schema.mcp_demo[0].name}" : ""
  vs_index_full_name   = var.enable_dais26_demos ? "${databricks_catalog.dev.name}.${var.mcp_demo_schema_name}.${var.vs_index_name}" : ""
}

# ─── Schema under bu1_dev ─────────────────────────────────────────────────────

resource "databricks_schema" "mcp_demo" {
  count         = local.dais26
  catalog_name  = databricks_catalog.dev.name
  name          = var.mcp_demo_schema_name
  force_destroy = true
  comment       = "DAIS26 MCP demo schema — taxi trips + retail zones + supply chain"
}

# ─── SDP pipeline source (SQL notebooks synced via TF) ────────────────────────
# databricks_notebook pushes local .sql files to workspace. databricks_pipeline
# references these workspace paths via `library.notebook.path`.

resource "databricks_notebook" "sdp_silver" {
  count    = local.dais26
  path     = "${var.sdp_source_workspace_path}/silver_taxi_trips"
  language = "SQL"
  source   = "${path.module}/bootstrap/sql/silver_taxi_trips.sql"
}

resource "databricks_notebook" "sdp_gold" {
  count    = local.dais26
  path     = "${var.sdp_source_workspace_path}/gold_borough_metrics"
  language = "SQL"
  source   = "${path.module}/bootstrap/sql/gold_borough_metrics.sql"
}

# ─── SDP Pipeline (serverless, Unity Catalog) ─────────────────────────────────

resource "databricks_pipeline" "mcp_demo" {
  count      = local.dais26
  name       = var.sdp_pipeline_name
  catalog    = databricks_catalog.dev.name
  schema     = databricks_schema.mcp_demo[0].name
  serverless = true
  channel    = "CURRENT"

  library {
    notebook {
      path = databricks_notebook.sdp_silver[0].path
    }
  }

  library {
    notebook {
      path = databricks_notebook.sdp_gold[0].path
    }
  }

  # Pipeline needs the source tables (nyc_taxi_trips, zip_borough_lookup)
  # seeded by bootstrap/01_seed_tables.sh. TF can create the pipeline before
  # seed runs; triggering the pipeline happens post-seed via bootstrap.
  depends_on = [databricks_schema.mcp_demo]
}

# ─── Vector Search ────────────────────────────────────────────────────────────

resource "databricks_vector_search_endpoint" "mcp_demo" {
  count         = local.dais26
  name          = var.vs_endpoint_name
  endpoint_type = "STANDARD"
}

resource "databricks_vector_search_index" "zone_descriptions" {
  count         = local.dais26
  name          = local.vs_index_full_name
  endpoint_name = databricks_vector_search_endpoint.mcp_demo[0].name
  primary_key   = "id"
  index_type    = "DELTA_SYNC"

  delta_sync_index_spec {
    source_table  = "${local.mcp_demo_schema_full}.zone_descriptions"
    pipeline_type = "TRIGGERED"

    embedding_source_columns {
      name                          = "description"
      embedding_model_endpoint_name = var.vs_embedding_model_endpoint_name
    }
  }

  # Source Delta table must exist + have CDF enabled before index creation.
  # bootstrap/01_seed_tables.sh creates zone_descriptions with CDF on.
  # Assumes seed has run before `tf apply` reaches this resource — enforce
  # via run.sh ordering (seed first, then apply).
  depends_on = [databricks_schema.mcp_demo]
}

# ─── Lakebase Postgres Instance ───────────────────────────────────────────────

resource "databricks_database_instance" "mcp_demo" {
  count    = local.dais26
  name     = var.lakebase_instance_name
  capacity = var.lakebase_capacity
}

# ─── Custom MCP Databricks App ────────────────────────────────────────────────
# TF declares the app shell. Source-code deploy is a separate step handled by
# bootstrap/04_app_deploy.sh (databricks sync + databricks apps deploy) — TF
# intentionally does not manage source-code artifacts.
#
# `resources` block auto-grants the app's SP warehouse access via the
# Permissions API. UC grants (catalog/schema/SELECT) are separate
# `databricks_grants` resources below because the app's SP UUID is only known
# after app creation.

resource "databricks_app" "custom_mcp" {
  count       = local.dais26
  name        = var.custom_mcp_app_name
  description = "DAIS26 custom MCP server exposing demo tools (health, whoami, run_sql, list_tables)"

  user_api_scopes = ["sql"]

  resources = [
    {
      name = "wh-demo-dev"
      sql_warehouse = {
        id         = databricks_sql_endpoint.dev.id
        permission = "CAN_USE"
      }
    }
  ]
}

# UC grants for the app's service principal. Principal is the SP's
# client_id UUID (not display name) — display names error with
# PRINCIPAL_DOES_NOT_EXIST.

resource "databricks_grants" "custom_mcp_catalog" {
  count   = local.dais26
  catalog = databricks_catalog.dev.name

  grant {
    principal  = databricks_app.custom_mcp[0].service_principal_client_id
    privileges = ["USE_CATALOG"]
  }

  depends_on = [databricks_app.custom_mcp]
}

resource "databricks_grants" "custom_mcp_schema" {
  count  = local.dais26
  schema = local.mcp_demo_schema_full

  grant {
    principal  = databricks_app.custom_mcp[0].service_principal_client_id
    privileges = ["USE_SCHEMA", "SELECT"]
  }

  depends_on = [databricks_schema.mcp_demo, databricks_app.custom_mcp]
}

# ─── AI Gateway (Databricks Foundation Model) ─────────────────────────────────
# No TF resource: Claude endpoints are pre-deployed in every Databricks workspace
# (`databricks-claude-opus-4-7`, `databricks-claude-sonnet-4-6`, etc.) and billed
# through the Databricks enterprise plan. Selection happens via var.gateway_model_name;
# the endpoint is referenced by outputs + rendered into gateway templates.
