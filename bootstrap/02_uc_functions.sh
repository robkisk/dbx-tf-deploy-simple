#!/usr/bin/env bash
# Create UC functions in bu1_dev.mcp_demo. Reads create_uc_functions.sql from
# DAIS26 repo. Functions depend on base tables (nyc_taxi_trips,
# zip_borough_lookup) — run after 01_seed_tables.sh.

. "$(dirname "$0")/_lib.sh"
load_outputs

section "Create UC functions under $MCP_DEMO_SCHEMA_FULL"
FUNC_FILE="$DAIS26_REPO/scripts/create_uc_functions.sql"
[ -f "$FUNC_FILE" ] || { err "function SQL not found: $FUNC_FILE"; exit 1; }

# Functions are multi-statement (CREATE OR REPLACE FUNCTION ... RETURN ...;)
# where the body itself contains CASE expressions and nested queries.
# Simplest: pass the whole file via statement execute (warehouses support
# multi-statement submission via the REST API).
python3 - "$FUNC_FILE" <<'PY'
import re, sys, subprocess, os
src = open(sys.argv[1]).read()
src = re.sub(r'--[^\n]*', '', src)
# Split only on `;` that are at column 0 of a new line (end of CREATE FUNCTION).
stmts = [s.strip() for s in re.split(r';\s*\n(?=\S|$)', src) if s.strip()]
profile = os.environ['DATABRICKS_CONFIG_PROFILE']
wh = os.environ['WAREHOUSE_ID']
for i, s in enumerate(stmts, 1):
  name = re.search(r'CREATE OR REPLACE FUNCTION\s+([^\s(]+)', s, re.I)
  label = name.group(1) if name else f'stmt {i}'
  print(f'  → {label}')
  subprocess.run(
    ['databricks', 'experimental', 'aitools', 'tools', 'query',
     '--profile', profile, '-w', wh, s],
    check=True, capture_output=True,
  )
PY
ok "UC functions created"
