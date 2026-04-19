#!/usr/bin/env bash
# Seed DAIS26 base tables into bu1_dev.mcp_demo.
# Reads seed SQL from the DAIS26 repo (authoritative source) and executes
# each statement via the aitools CLI. Must run BEFORE `tf apply` for
# resources that depend on `zone_descriptions` existing (VS index).

. "$(dirname "$0")/_lib.sh"
load_outputs

section "Seed $MCP_DEMO_SCHEMA_FULL base tables"
SEED_FILE="$DAIS26_REPO/scripts/seed_mcp_demo_tables.sql"
[ -f "$SEED_FILE" ] || { err "seed SQL not found: $SEED_FILE"; exit 1; }

python3 - "$SEED_FILE" <<'PY'
import os, re, subprocess, sys

src = open(sys.argv[1]).read()
src = re.sub(r'--[^\n]*', '', src)
stmts = [s.strip() for s in re.split(r';\s*\n(?=\S|$)', src) if s.strip()]

profile = os.environ['DATABRICKS_CONFIG_PROFILE']
wh = os.environ['WAREHOUSE_ID']
for s in stmts:
  first_line = ' '.join(s.split())[:80]
  print(f'  → {first_line}…')
  subprocess.run(
    ['databricks', 'experimental', 'aitools', 'tools', 'query',
     '--profile', profile, '-w', wh, s],
    check=True, capture_output=True,
  )
PY
ok "seed complete"
