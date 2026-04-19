#!/usr/bin/env bash
# Sync custom-mcp/ source code to the workspace path TF's app resource
# references, then trigger `databricks apps deploy`. TF declares the app
# shell; actual container build happens here.

. "$(dirname "$0")/_lib.sh"
load_outputs

CUSTOM_MCP_SRC="$DAIS26_REPO/custom-mcp"
[ -d "$CUSTOM_MCP_SRC" ] || { err "custom-mcp source not found at $CUSTOM_MCP_SRC"; exit 1; }

# Workspace path is the same one TF's var.custom_mcp_source_workspace_path
# points to — fetch it from tfvars/variables default if needed.
WS_PATH="/Workspace/Users/robby.kiskanyan@databricks.com/custom-mcp-demo"

section "Sync custom-mcp source → $WS_PATH"
databricks sync "$CUSTOM_MCP_SRC" "$WS_PATH" \
  --profile "$DATABRICKS_CONFIG_PROFILE" \
  --full >/dev/null 2>&1
ok "source synced"

section "Deploy custom-mcp-demo app"
databricks apps deploy custom-mcp-demo \
  --source-code-path "$WS_PATH" \
  --profile "$DATABRICKS_CONFIG_PROFILE" >/dev/null
ok "app deploy triggered (build runs async)"
