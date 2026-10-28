SHELL := /bin/bash

NVIM ?= nvim
PLENARY_PATH ?= $(HOME)/.local/share/nvim/lazy/plenary.nvim
XDG_STATE_HOME ?= $(CURDIR)/.tmp-state
TEST_DIR ?= lua/

export PLENARY_PATH
export XDG_STATE_HOME
export TEST_DIR

.PHONY: test test-file test-e2e lint format format-check typecheck check

test:
	@scripts/test.sh

test-file:
	@if [ -z "$(FILE)" ]; then echo "FILE=... を指定してください" >&2; exit 1; fi
	@mkdir -p "$(XDG_STATE_HOME)"
	@$(NVIM) --headless -u tests/minimal_init.lua -c "PlenaryBustedFile $(FILE)"

test-e2e:
	@scripts/e2e.sh

lint:
	@luacheck lua/ plugin/ tests/

format:
	@stylua lua/ plugin/ tests/

format-check:
	@stylua --check lua/ plugin/ tests/

typecheck:
	@scripts/typecheck.sh

check: lint format-check typecheck test
