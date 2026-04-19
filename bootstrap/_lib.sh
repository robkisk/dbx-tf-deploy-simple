#!/usr/bin/env bash
# Shared helpers for bootstrap scripts. Source this at the top of each script.

set -euo pipefail

# Script dir is always bootstrap/; project root is one up.
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$BOOTSTRAP_DIR/.." && pwd)"
cd "$PROJECT_DIR"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing '$1' on PATH" >&2; exit 1; }
}

require_cmd terraform
require_cmd databricks
require_cmd jq

# Cache `terraform output -json` once per invocation.
tf_out() { jq -r ".$1.value" <<<"$TF_OUT"; }

load_outputs() {
  TF_OUT="$(terraform output -json)"
  export DAIS26_ENABLED="$(tf_out dais26_enabled)"
  export WORKSPACE_HOST="$(tf_out dais26_workspace_host)"
  export WAREHOUSE_ID="$(tf_out sql_warehouse_dev_id)"
  export CATALOG_DEV="$(tf_out catalog_name_dev)"
  export MCP_DEMO_SCHEMA_FULL="$(tf_out mcp_demo_schema_full)"
  export SDP_PIPELINE_ID="$(tf_out sdp_pipeline_id)"
  export VS_ENDPOINT="$(tf_out vs_endpoint_name)"
  export VS_INDEX="$(tf_out vs_index_name)"
  export LAKEBASE_INSTANCE="$(tf_out lakebase_instance_name)"
  export LAKEBASE_HOST="$(tf_out lakebase_host)"
  export LAKEBASE_DATABASE="$(tf_out lakebase_database_name)"
  export CUSTOM_MCP_URL="$(tf_out custom_mcp_app_url)"
  export CUSTOM_MCP_SP="$(tf_out custom_mcp_sp_client_id)"
  export GATEWAY_ENDPOINT="$(tf_out gateway_endpoint_name)"
  export GATEWAY_BASE_URL="$(tf_out gateway_base_url)"
  export DAIS26_REPO="$(tf_out dais26_repo_path)"

  if [ "$DAIS26_ENABLED" != "true" ]; then
    echo "SKIP: enable_dais26_demos=false — bootstrap no-op" >&2
    exit 0
  fi
}

# Profile — CLI + SDK use this. Assume `dev` unless overridden.
: "${DATABRICKS_CONFIG_PROFILE:=dev}"
export DATABRICKS_CONFIG_PROFILE

section() { printf "\n\033[1m── %s ──\033[0m\n" "$1"; }
info()    { printf "  %s\n" "$1"; }
ok()      { printf "  \033[32m✓\033[0m %s\n" "$1"; }
err()     { printf "  \033[31m✗\033[0m %s\n" "$1" >&2; }
