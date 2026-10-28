#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PLENARY_PATH="${PLENARY_PATH:-$HOME/.local/share/nvim/lazy/plenary.nvim}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$ROOT/.tmp-state}"
TEST_DIR="${TEST_DIR:-lua/}"
export PLENARY_PATH XDG_STATE_HOME

mkdir -p "$XDG_STATE_HOME"

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

set +e
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory $TEST_DIR {minimal_init = 'tests/minimal_init.lua', sequential = true}" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
set -e

counts="$(sed -E $'s/\x1b\\[[0-9;]*m//g' "$log" | awk -F: '
  /^Success:/ { s += $2 }
  /^Failed[[:space:]]*:/ { f += $2 }
  /^Errors[[:space:]]*:/ { e += $2 }
  END { printf "%d %d %d", s, f, e }
')"
read -r success failed errors <<< "$counts"

echo "Success: $success, Failed: $failed, Errors: $errors" >&2

if [ "$code" -ne 0 ]; then
  exit "$code"
fi

if [ "$failed" -gt 0 ] || [ "$errors" -gt 0 ]; then
  echo "テスト失敗を検出しました" >&2
  exit 1
fi

if [ "$success" -eq 0 ] && [ "$failed" -eq 0 ] && [ "$errors" -eq 0 ]; then
  echo "テストが 0 件のため失敗とします" >&2
  exit 1
fi
