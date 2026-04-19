#!/usr/bin/env bash
# Trigger an update on the SDP pipeline TF just created. TF creates the
# pipeline but doesn't run it — this script starts the first update so
# silver_taxi_trips + gold_borough_metrics are populated.

. "$(dirname "$0")/_lib.sh"
load_outputs

section "Trigger SDP pipeline update (id=$SDP_PIPELINE_ID)"
[ -n "$SDP_PIPELINE_ID" ] || { err "sdp_pipeline_id output is empty"; exit 1; }

databricks pipelines start-update "$SDP_PIPELINE_ID" \
  --profile "$DATABRICKS_CONFIG_PROFILE" >/dev/null
ok "pipeline update started (check UI for completion)"
