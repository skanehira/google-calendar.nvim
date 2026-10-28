#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PLENARY_PATH="${PLENARY_PATH:-$HOME/.local/share/nvim/lazy/plenary.nvim}"
export PLENARY_PATH

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/state"
ln -s "$ROOT/tests/fixtures/fake-gws.py" "$tmp/bin/gws"
chmod +x "$ROOT/tests/fixtures/fake-gws.py"

export PATH="$tmp/bin:$PATH"
export FAKE_GWS_STATE="$tmp/fake-gws-state.json"
export FAKE_GWS_CWD_LOG="$tmp/cwd.log"
export FAKE_GWS_CALL_LOG="$tmp/calls.log"
export XDG_STATE_HOME="$tmp/state"

nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/e2e {minimal_init = 'tests/minimal_init.lua', sequential = true}"
