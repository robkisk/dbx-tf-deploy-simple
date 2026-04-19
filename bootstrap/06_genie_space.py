#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "databricks-sdk",
# ]
# ///
"""Create (or reuse) the DAIS26 Genie space.

No TF resource covers Genie spaces yet. This script:
  1. Looks for an existing space matching DAIS26_GENIE_TITLE.
  2. If not found, creates one scoped to bu1_dev.mcp_demo tables.
  3. Writes the space ID to `.genie_space_id` next to terraform.tfstate so
     step 07 can embed it into .mcp.json.
"""

import json
import os
import pathlib
import sys

from databricks.sdk import WorkspaceClient

GENIE_TITLE = "DAIS26 MCP Demo Analytics"
GENIE_DESCRIPTION = (
  "Natural language Q&A over bu1_dev.mcp_demo: NYC taxi trips with borough "
  "enrichment (bronze/silver/gold), supply chain shipments with planted "
  "anomalies, customers, and orders."
)


def main() -> None:
  profile = os.environ.get("DATABRICKS_CONFIG_PROFILE", "dev")
  catalog = os.environ["CATALOG_DEV"]
  schema = os.environ["MCP_DEMO_SCHEMA_FULL"].split(".")[-1]
  warehouse_id = os.environ["WAREHOUSE_ID"]

  w = WorkspaceClient(profile=profile)

  existing = None
  page_token = None
  while True:
    resp = w.genie.list_spaces(page_token=page_token)
    for s in (resp.spaces or []):
      if s.title == GENIE_TITLE:
        existing = s
        break
    if existing or not resp.next_page_token:
      break
    page_token = resp.next_page_token

  if existing:
    space_id = existing.space_id
    print(f"  ✓ reusing existing Genie space: {space_id}")
  else:
    tables = [
      "nyc_taxi_trips",
      "zip_borough_lookup",
      "silver_taxi_trips",
      "gold_borough_metrics",
      "customers",
      "orders",
      "supply_chain_shipments",
    ]
    created = w.genie.create_space(
      title=GENIE_TITLE,
      description=GENIE_DESCRIPTION,
      warehouse_id=warehouse_id,
      table_identifiers=[f"{catalog}.{schema}.{t}" for t in tables],
    )
    space_id = created.space_id
    print(f"  ✓ created Genie space: {space_id}")

  out = pathlib.Path(__file__).resolve().parent.parent / ".genie_space_id"
  out.write_text(space_id)
  print(f"  wrote {out}")


if __name__ == "__main__":
  try:
    main()
  except (AttributeError, TypeError) as e:
    # SDK Genie API surface changes often. `create_space` in particular moved
    # from `(title, description, warehouse_id, table_identifiers)` → positional
    # `(warehouse_id, serialized_space, *, title, description, parent_path)`,
    # which requires a pre-rendered serialized_space JSON blob. If reuse fails
    # and create fails, create the space in the UI and pin the ID manually.
    print(f"  ! Genie SDK call failed: {e}", file=sys.stderr)
    print("  ! Create the space manually in the UI, then:", file=sys.stderr)
    print("  !   echo '<space-id>' > .genie_space_id", file=sys.stderr)
    sys.exit(1)
