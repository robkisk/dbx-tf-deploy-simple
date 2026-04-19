#!/usr/bin/env python3
"""Render config templates from terraform outputs + Genie space ID file.

Writes rendered files into $DAIS26_REPO:
  - .mcp.json                        (from bootstrap/templates/mcp.json.tftpl)
  - gateway/ai-gateway-anthropic.py  (from bootstrap/templates/gateway-anthropic.py.tftpl)
  - gateway/ai-gateway-tracing.py    (from bootstrap/templates/gateway-tracing.py.tftpl)

Treating `.mcp.json` as a generated artifact is the single biggest durability
win of this pipeline — no more hand-editing on every workspace change.

Prereqs:
  - terraform apply has completed (outputs available)
  - bootstrap/06_genie_space.py has written .genie_space_id
"""

import json
import os
import pathlib
import string
import subprocess


PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent
TEMPLATES = PROJECT_DIR / 'bootstrap' / 'templates'


def tf_outputs() -> dict:
  """Return a flat dict of terraform output name -> value."""
  out = subprocess.check_output(['terraform', 'output', '-json'], cwd=PROJECT_DIR)
  return {k: v['value'] for k, v in json.loads(out).items()}


def render(template_name: str, **subs) -> str:
  """Render a .tftpl file using Python's string.Template.

  `${var}` syntax matches Terraform tftpl. We use `safe_substitute` so any
  unmatched `$...` tokens survive rather than raising — guards against future
  templates that reference vars not wired in here yet.
  """
  src = (TEMPLATES / template_name).read_text()
  return string.Template(src).safe_substitute(**subs)


def write(path: pathlib.Path, content: str) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text(content)
  print(f'  ✓ wrote {path}')


def main() -> None:
  o = tf_outputs()
  if not o.get('dais26_enabled'):
    print('SKIP: enable_dais26_demos=false')
    return

  genie_file = PROJECT_DIR / '.genie_space_id'
  if not genie_file.exists():
    raise SystemExit('ERROR: .genie_space_id not found — run 06_genie_space.py first')
  genie_space_id = genie_file.read_text().strip()
  if not genie_space_id:
    raise SystemExit('ERROR: .genie_space_id is empty')

  dais26_repo = pathlib.Path(o['dais26_repo_path']).expanduser()
  if not dais26_repo.is_dir():
    raise SystemExit(f'ERROR: dais26_repo_path {dais26_repo} is not a directory')

  profile = os.environ.get('DATABRICKS_CONFIG_PROFILE', 'dev')

  schema_full = o['mcp_demo_schema_full']
  if not schema_full or '.' not in schema_full:
    raise SystemExit(f'ERROR: mcp_demo_schema_full unexpected value: {schema_full!r}')
  catalog, schema = schema_full.split('.', 1)

  mcp_json = render(
    'mcp.json.tftpl',
    databricks_profile=profile,
    warehouse_id=o['sql_warehouse_dev_id'],
    genie_space_id=genie_space_id,
    catalog=catalog,
    schema=schema,
    custom_mcp_url=o['custom_mcp_app_url'],
    lakebase_instance=o['lakebase_instance_name'],
    lakebase_database=o['lakebase_database_name'],
  )
  write(dais26_repo / '.mcp.json', mcp_json)

  gateway_py = render(
    'gateway-anthropic.py.tftpl',
    gateway_endpoint_name=o['gateway_endpoint_name'],
  )
  write(dais26_repo / 'gateway' / 'ai-gateway-anthropic.py', gateway_py)

  gateway_tracing_py = render(
    'gateway-tracing.py.tftpl',
    gateway_endpoint_name=o['gateway_endpoint_name'],
  )
  write(dais26_repo / 'gateway' / 'ai-gateway-tracing.py', gateway_tracing_py)


if __name__ == '__main__':
  main()
