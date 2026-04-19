#!/usr/bin/env bash
# End-to-end deployer for the DAIS26 demo assets.
#
# Two-phase terraform apply (schema/warehouse → seed → everything) + the
# imperative bootstrap tail. Safe to re-run: TF resources are idempotent,
# bootstrap scripts guard on pre-existing state.
#
# Usage:
#   ./run.sh                                         # full deploy
#   ./run.sh --dry-run                               # terraform plan only
#   ./run.sh --skip-tf                               # bootstrap-only (TF already applied)
#   ./run.sh --dais26-repo /abs/path/to/dais26-repo  # override TF var
#
# Pre-reqs:
#   - `terraform init` has been run at least once
#   - DATABRICKS_CONFIG_PROFILE points at the target workspace (default: dev)
#   - enable_dais26_demos = true in terraform.tfvars
#   - gateway uses a pre-deployed native Databricks FM endpoint; pick which
#     via `var.gateway_model_name` (default: databricks-claude-opus-4-7).
#     No anthropic API key required.

set -euo pipefail

DRY=false
SKIP_TF=false
REPO_OVERRIDE=''

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)       DRY=true; shift ;;
    --skip-tf)       SKIP_TF=true; shift ;;
    --dais26-repo)   REPO_OVERRIDE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Allow override of the DAIS26 repo path via flag. Only export if non-empty so
# the TF default wins otherwise.
[ -n "$REPO_OVERRIDE" ] && export TF_VAR_dais26_repo_path="$REPO_OVERRIDE"

# Load .env if present (matches CLAUDE.md convention for GITHUB_TOKEN).
if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

: "${DATABRICKS_CONFIG_PROFILE:=dev}"
export DATABRICKS_CONFIG_PROFILE

# Terraform must NOT inherit DATABRICKS_CONFIG_PROFILE: the `databricks.accounts`
# provider points at accounts.azuredatabricks.net, and the workspace-scoped OAuth
# token cached by profile `dev` fails auth against the account host. Unsetting
# here lets the provider fall through to azure-cli auth (az login, same tenant)
# which works for both account + workspace hosts. Bootstrap scripts below keep
# the profile so `databricks experimental aitools` + SDK calls still work.
tf() { (unset DATABRICKS_CONFIG_PROFILE && terraform "$@"); }

if [ "$DRY" = true ]; then
  echo '── terraform plan (dry-run) ──'
  tf plan
  exit 0
fi

if [ "$SKIP_TF" = false ]; then
  # Phase A: schema + warehouse must exist before seed can target them.
  echo '── phase A: target-apply schema + warehouse ──'
  tf apply -auto-approve \
    -target=databricks_schema.mcp_demo \
    -target=databricks_sql_endpoint.dev

  # Phase B: seed base tables. `zone_descriptions` (source for VS index) must
  # exist with CDF enabled BEFORE the VS index resource is applied.
  echo '── phase B: seed base tables ──'
  bootstrap/01_seed_tables.sh

  # Phase C: full apply — creates pipeline, VS endpoint+index, lakebase, app,
  # gateway, grants.
  echo '── phase C: full terraform apply ──'
  tf apply -auto-approve
else
  echo '── skipping terraform (--skip-tf) ──'
  bootstrap/01_seed_tables.sh
fi

# Phase D: imperative tail — ordering matters (Genie before config rewrite,
# app deploy before smoke test).
#
# Pre-source _lib.sh and load_outputs so the Python bootstrap scripts (04, 06)
# inherit the TF-output env vars they need. Bash scripts re-source _lib.sh on
# their own and are unaffected.
echo '── phase D: bootstrap imperative tail ──'
# shellcheck source=bootstrap/_lib.sh
. bootstrap/_lib.sh
load_outputs
bootstrap/02_uc_functions.sh
bootstrap/03_trigger_pipeline.sh
bootstrap/04_lakebase_db.py
bootstrap/05_app_deploy.sh
bootstrap/06_genie_space.py
bootstrap/07_rewrite_config.py
bootstrap/08_smoke_test.sh

echo '── DAIS26 deploy complete ──'
