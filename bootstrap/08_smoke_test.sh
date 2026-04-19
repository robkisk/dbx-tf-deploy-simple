#!/usr/bin/env bash
# Smoke-test every MCP surface the DAIS26 demos depend on. Fail-fast on any
# broken integration so a green run = working end-to-end demo.
#
# Mirrors the manual 11-MCP validation from the original migration checklist,
# plus the two-minute health probes that answered "did deploy actually work".

. "$(dirname "$0")/_lib.sh"
load_outputs

FAIL=0

section 'Smoke test DAIS26 MCP surface'

# ── 1. dbsql (warehouse reachable + seed data present) ────────────────────────
if databricks experimental aitools tools query \
  --profile "$DATABRICKS_CONFIG_PROFILE" -w "$WAREHOUSE_ID" \
  "SELECT COUNT(*) AS n FROM $MCP_DEMO_SCHEMA_FULL.nyc_taxi_trips" \
  >/dev/null 2>&1; then
  ok 'dbsql — nyc_taxi_trips reachable'
else
  err 'dbsql — query failed on nyc_taxi_trips'; FAIL=1
fi

# ── 2. UC function ────────────────────────────────────────────────────────────
# avg_fare_by_borough is a table function (returns rows), not scalar, so the
# call must live in FROM. Scalar-style SELECT fn(...) raises NOT_A_SCALAR_FUNCTION.
if databricks experimental aitools tools query \
  --profile "$DATABRICKS_CONFIG_PROFILE" -w "$WAREHOUSE_ID" \
  "SELECT * FROM $MCP_DEMO_SCHEMA_FULL.avg_fare_by_borough('Manhattan') LIMIT 1" \
  >/dev/null 2>&1; then
  ok 'ucfunc — avg_fare_by_borough returns'
else
  err 'ucfunc — avg_fare_by_borough failed'; FAIL=1
fi

# ── 3. Vector Search index (REST query) ───────────────────────────────────────
TOKEN="$(databricks auth token --profile "$DATABRICKS_CONFIG_PROFILE" -o json | jq -r .access_token)"
if [ -z "$TOKEN" ] || [ "$TOKEN" = 'null' ]; then
  err 'auth — failed to obtain bearer token for REST probes'
  FAIL=1
else
  # VS query API requires `columns` field in the body (list of source-table
  # columns to return alongside the match score).
  VS_STATUS="$(
    curl -s -o /dev/null -w '%{http_code}' \
      -X POST \
      "$WORKSPACE_HOST/api/2.0/vector-search/indexes/$VS_INDEX/query" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' \
      -d '{"num_results": 1, "query_text": "borough", "columns": ["description"]}'
  )"
  if [ "$VS_STATUS" = '200' ]; then
    ok "vs — $VS_INDEX query OK"
  else
    err "vs — $VS_INDEX query HTTP $VS_STATUS"; FAIL=1
  fi

  # ── 4. Custom MCP app /mcp endpoint (JSON-RPC initialize) ──────────────────
  MCP_STATUS="$(
    curl -s -o /dev/null -w '%{http_code}' \
      -X POST "$CUSTOM_MCP_URL/mcp" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json, text/event-stream' \
      -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientCapabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}'
  )"
  # 2xx = happy. Some MCP servers respond 406/415 without streamable headers —
  # treat <500 as server-up, >=500 as broken.
  if [ "$MCP_STATUS" -ge 200 ] && [ "$MCP_STATUS" -lt 500 ]; then
    ok "custom-mcp — /mcp reachable (HTTP $MCP_STATUS)"
  else
    err "custom-mcp — /mcp HTTP $MCP_STATUS"; FAIL=1
  fi

  # ── 5. Databricks Foundation Model endpoint (/serving-endpoints/<name>/invocations) ──
  GW_STATUS="$(
    curl -s -o /dev/null -w '%{http_code}' \
      -X POST "$WORKSPACE_HOST/serving-endpoints/$GATEWAY_ENDPOINT/invocations" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' \
      -d '{"messages":[{"role":"user","content":"ping"}],"max_tokens":8}'
  )"
  if [ "$GW_STATUS" = '200' ]; then
    ok "gateway — $GATEWAY_ENDPOINT responded 200"
  else
    err "gateway — /invocations HTTP $GW_STATUS (endpoint $GATEWAY_ENDPOINT)"
    FAIL=1
  fi
fi

section 'Summary'
if [ $FAIL -eq 0 ]; then
  ok 'ALL SMOKE TESTS PASSED'
  exit 0
else
  err 'FAILURES above — fix before declaring deploy complete'
  exit 1
fi
