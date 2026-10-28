# Contributing

This document covers development setup, tests, linting, formatting, and type checking for `google-calendar.nvim`. For user-facing usage, see [README.md](README.md) or `:help google-calendar`.

## Development requirements

- Neovim 0.10 or later
- Lua 5.1
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for the test harness
- `stylua` 2.x
- `luacheck` 1.x
- `lua-language-server` 3.x
- Python 3 for the fake `gws` used by tests

## Local setup

```bash
git clone https://github.com/skanehira/google-calendar.nvim.git
cd google-calendar.nvim
```

The test harness looks for plenary at `~/.local/share/nvim/lazy/plenary.nvim` by default. Override it with `PLENARY_PATH`:

```bash
export PLENARY_PATH=/path/to/plenary.nvim
```

If your environment cannot write to the default state directory, point `XDG_STATE_HOME` at a writable directory:

```bash
export XDG_STATE_HOME="$PWD/.tmp-state"
```

## Commands

```bash
# Run the full test suite (plenary busted)
make test

# Run a single spec file
make test-file FILE=lua/google-calendar/config_spec.lua

# Run headless end-to-end tests with the fake gws
make test-e2e

# Lint, format, and type checking
make lint
make format
make format-check
make typecheck

# Run everything: lint -> format-check -> typecheck -> test
make check
```

`make format` rewrites files with stylua. Use `make format-check` in CI or before opening a pull request.

## Tests

Unit and integration specs live under `lua/`. End-to-end tests live under `tests/e2e/` and use `tests/fixtures/fake-gws.py`; they never touch a real Google Calendar.

The fake `gws` can be configured through environment variables:

| Variable | Purpose |
| --- | --- |
| `FAKE_GWS_STATE` | Path to the JSON state file used for events |
| `FAKE_GWS_CALL_LOG` | Path to a log of invoked commands |
| `FAKE_GWS_CWD_LOG` | Path to a log of working directories |
| `FAKE_GWS_ERROR_FIXTURE` | Name of an error fixture to return |
| `FAKE_GWS_PAGE_SIZE` | Page size for pagination tests |

The test harness is described in `lua/google-calendar/test_harness_spec.lua` and `docs/design/features/test-harness.md`.

## CI

GitHub Actions runs `make check` on Neovim 0.10.4 with Lua 5.1. It installs luacheck, stylua 2.6.0, and lua-language-server 3.19.2, clones plenary, and runs the same command locally.

## Design documents

Architecture, use cases, and per-feature design notes are under `docs/design/`. Read `docs/design/DESIGN.md` first, then the relevant file under `docs/design/features/`.

## Pull requests

- Keep changes focused and include tests for behavior changes.
- Run `make check` before opening a pull request.
- Update `README.md`, `doc/google-calendar.txt`, and the relevant design document when behavior or configuration changes.
- Use the repository's existing commit message style.
