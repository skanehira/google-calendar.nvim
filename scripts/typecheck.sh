#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p .tmp-state
out=.tmp-state/typecheck.json
log=.tmp-state/luals-log

set +e
lua-language-server --check . --configpath=.luarc.json --check_format=json --check_out_path="$out" --logpath="$log" >/dev/null
luals_code=$?
set -e

python3 - "$out" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as file:
    diagnostics = json.load(file)

count = 0
if isinstance(diagnostics, dict):
    for uri, items in diagnostics.items():
        for item in items:
            count += 1
            start = item["range"]["start"]
            print(f"{uri}:{start['line'] + 1}:{start['character'] + 1} [{item['code']}] {item['message']}")
else:
    count = len(diagnostics)
    for item in diagnostics:
        print(item)

if count:
    print(f"{count} problems found", file=sys.stderr)
    sys.exit(1)
PY

if [ "$luals_code" -ne 0 ]; then
  echo "lua-language-server exited with $luals_code" >&2
  exit "$luals_code"
fi
