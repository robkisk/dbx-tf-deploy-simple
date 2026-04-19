#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "psycopg[binary]",
#   "databricks-sdk",
# ]
# ///
"""Create the logical PG database inside the Lakebase instance.

TF provisions the instance. This script CREATEs the database because there
is no first-class TF resource for PG-level CREATE DATABASE inside a
Databricks managed Lakebase instance.

Idempotent: skips if database already exists.
"""

import os
import sys

import psycopg
from databricks.sdk import WorkspaceClient


def sh(key: str) -> str:
  v = os.environ.get(key, "").strip()
  if not v:
    sys.exit(f"missing env var: {key}")
  return v


def main() -> None:
  instance = sh("LAKEBASE_INSTANCE")
  host = sh("LAKEBASE_HOST")
  dbname = sh("LAKEBASE_DATABASE")
  profile = os.environ.get("DATABRICKS_CONFIG_PROFILE", "dev")

  w = WorkspaceClient(profile=profile)
  cred = w.database.generate_database_credential(
    request_id="bootstrap-create-db",
    instance_names=[instance],
  )
  user = w.current_user.me().user_name
  token = cred.token

  # Connect to the default `postgres` maintenance database first; CREATE
  # DATABASE cannot run inside a transaction on the target database.
  conn = psycopg.connect(
    host=host,
    port=5432,
    user=user,
    password=token,
    dbname="postgres",
    sslmode="require",
    autocommit=True,
  )
  with conn.cursor() as cur:
    cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (dbname,))
    exists = cur.fetchone() is not None
    if exists:
      print(f"  ✓ database '{dbname}' already exists")
    else:
      cur.execute(f'CREATE DATABASE "{dbname}"')
      print(f"  ✓ database '{dbname}' created")
  conn.close()


if __name__ == "__main__":
  main()
