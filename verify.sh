#!/usr/bin/env bash
# Post-apply verification for dbx-tf-deploy-simple.
# Failures print full error; passes print one-liner.

set -u
FAIL=0

# Auto-load GITHUB_TOKEN for terraform github provider
[ -f .env ] && . ./.env

pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m✗\033[0m %s\n    %s\n" "$1" "$2"; FAIL=1; }

section() { printf "\n\033[1m%s\033[0m\n" "$1"; }

# ─── Load outputs ─────────────────────────────────────────────────────────────
OUT=$(terraform output -json)
RG=$(jq -r .resource_group_name.value <<<"$OUT")
DEV_URL=$(jq -r .workspace_url.value <<<"$OUT" | sed 's|https://||;s|/$||')
PROD_URL=$(jq -r .workspace_url_prod.value <<<"$OUT" | sed 's|https://||;s|/$||')
DEV_WS_ID=$(jq -r .workspace_workspace_id.value <<<"$OUT")
PROD_WS_ID=$(jq -r .workspace_workspace_id_prod.value <<<"$OUT")
METASTORE=$(jq -r .metastore_id.value <<<"$OUT")
CAT_DEV=$(jq -r .catalog_name_dev.value <<<"$OUT")
CAT_PROD=$(jq -r .catalog_name_prod.value <<<"$OUT")
SCHEMA=$(jq -r .schema_name.value <<<"$OUT")
SP_APP_ID=$(jq -r .cicd_sp_application_id.value <<<"$OUT")
SP_ID=$(jq -r .cicd_sp_id.value <<<"$OUT")
ACCOUNT_ID=$(jq -r .databricks_account_id.value <<<"$OUT")
WH_DEV=$(jq -r .sql_warehouse_dev_id.value <<<"$OUT")
WH_PROD=$(jq -r .sql_warehouse_prod_id.value <<<"$OUT")

# ─── 1. State drift ───────────────────────────────────────────────────────────
section "1. State drift"
if terraform plan -detailed-exitcode -lock=false >/dev/null 2>&1; then
  pass "terraform plan clean (no drift)"
else
  rc=$?
  if [ $rc -eq 2 ]; then fail "terraform plan" "drift detected — run 'tf plan' to see"
  else fail "terraform plan" "plan errored (exit $rc)"; fi
fi

# ─── 2. Azure resources ───────────────────────────────────────────────────────
section "2. Azure"
az group show -n "$RG" -o none 2>/dev/null && pass "RG $RG exists" || fail "RG" "$RG not found"
az resource list -g "$RG" --resource-type Microsoft.Databricks/workspaces --query "length(@)" -o tsv 2>/dev/null | grep -q "^2$" \
  && pass "2 workspaces in RG" || fail "workspaces" "expected 2 in RG"

# ─── 3. Databricks workspace auth + UC ────────────────────────────────────────
section "3. Databricks (dev workspace)"
if DATABRICKS_HOST="https://$DEV_URL" databricks current-user me -o json >/dev/null 2>&1; then
  pass "dev workspace auth OK"
  DATABRICKS_HOST="https://$DEV_URL" databricks catalogs get "$CAT_DEV" -o json >/dev/null 2>&1 \
    && pass "catalog $CAT_DEV exists" || fail "catalog $CAT_DEV" "not found"
  DATABRICKS_HOST="https://$DEV_URL" databricks schemas get "$CAT_DEV.$SCHEMA" -o json >/dev/null 2>&1 \
    && pass "schema $CAT_DEV.$SCHEMA exists" || fail "schema" "$CAT_DEV.$SCHEMA not found"
  DATABRICKS_HOST="https://$DEV_URL" databricks warehouses get "$WH_DEV" -o json >/dev/null 2>&1 \
    && pass "warehouse $WH_DEV exists" || fail "warehouse dev" "$WH_DEV not found"
else
  fail "dev workspace auth" "databricks CLI cannot reach $DEV_URL"
fi

section "3. Databricks (prod workspace)"
if DATABRICKS_HOST="https://$PROD_URL" databricks current-user me -o json >/dev/null 2>&1; then
  pass "prod workspace auth OK"
  DATABRICKS_HOST="https://$PROD_URL" databricks catalogs get "$CAT_PROD" -o json >/dev/null 2>&1 \
    && pass "catalog $CAT_PROD exists" || fail "catalog $CAT_PROD" "not found"
  DATABRICKS_HOST="https://$PROD_URL" databricks schemas get "$CAT_PROD.$SCHEMA" -o json >/dev/null 2>&1 \
    && pass "schema $CAT_PROD.$SCHEMA exists" || fail "schema" "$CAT_PROD.$SCHEMA not found"
  DATABRICKS_HOST="https://$PROD_URL" databricks warehouses get "$WH_PROD" -o json >/dev/null 2>&1 \
    && pass "warehouse $WH_PROD exists" || fail "warehouse prod" "$WH_PROD not found"
else
  fail "prod workspace auth" "databricks CLI cannot reach $PROD_URL"
fi

# ─── 4. GitHub resources ──────────────────────────────────────────────────────
section "4. GitHub"
for ENV in dev prod; do
  gh api "repos/robkisk/dbx-devx-workshop/environments/$ENV" -q .name >/dev/null 2>&1 \
    && pass "env '$ENV' exists" || fail "env '$ENV'" "not found"
  gh api "repos/robkisk/dbx-devx-workshop/environments/$ENV/variables/DATABRICKS_CATALOG" -q .name >/dev/null 2>&1 \
    && pass "var DATABRICKS_CATALOG ($ENV)" || fail "var DATABRICKS_CATALOG ($ENV)" "not found"
  gh api "repos/robkisk/dbx-devx-workshop/environments/$ENV/secrets/DATABRICKS_HOST" -q .name >/dev/null 2>&1 \
    && pass "secret DATABRICKS_HOST ($ENV)" || fail "secret DATABRICKS_HOST ($ENV)" "not found"
done
gh api "repos/robkisk/dbx-devx-workshop/actions/secrets/DATABRICKS_CLIENT_ID" -q .name >/dev/null 2>&1 \
  && pass "repo secret DATABRICKS_CLIENT_ID" || fail "secret DATABRICKS_CLIENT_ID" "not found"

# ─── 5. OIDC federation (functional check) ────────────────────────────────────
section "5. OIDC federation policies"
TOKEN=$(az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv 2>/dev/null)
POLICIES_JSON=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "https://accounts.azuredatabricks.net/api/2.0/accounts/$ACCOUNT_ID/servicePrincipals/$SP_ID/federationPolicies")
for POLICY in github-oidc-env-dev github-oidc-env-prod github-oidc-branch github-oidc-pr; do
  jq -e --arg p "$POLICY" '.policies[]? | select(.name | endswith($p))' <<<"$POLICIES_JSON" >/dev/null 2>&1 \
    && pass "policy $POLICY" || fail "policy $POLICY" "not found on SP $SP_ID"
done

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ $FAIL -eq 0 ]; then
  printf "\033[32mALL CHECKS PASSED\033[0m\n"
  exit 0
else
  printf "\033[31mFAILURES above\033[0m\n"
  exit 1
fi
