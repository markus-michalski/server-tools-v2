.PHONY: help install uninstall test test-verbose lint format format-check check clean setup-tests

SHELL := /bin/bash
PROJECT_ROOT := $(dir $(abspath $(firstword $(MAKEFILE_LIST))))

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Install server-tools system-wide (requires root)
	@"$(PROJECT_ROOT)bin/server-tools" install

uninstall: ## Remove server-tools from system (requires root)
	@"$(PROJECT_ROOT)bin/server-tools" uninstall

setup-tests: ## Install BATS test dependencies
	@if [ ! -d tests/libs/bats-support ]; then \
		echo "Installing bats-support..."; \
		git clone --depth 1 https://github.com/bats-core/bats-support.git tests/libs/bats-support; \
	fi
	@if [ ! -d tests/libs/bats-assert ]; then \
		echo "Installing bats-assert..."; \
		git clone --depth 1 https://github.com/bats-core/bats-assert.git tests/libs/bats-assert; \
	fi
	@if [ ! -d tests/libs/bats-file ]; then \
		echo "Installing bats-file..."; \
		git clone --depth 1 https://github.com/bats-core/bats-file.git tests/libs/bats-file; \
	fi
	@echo "Test dependencies ready"

test: setup-tests ## Run BATS tests
	@command -v bats >/dev/null 2>&1 || { echo "bats not found. Install: npm i -g bats"; exit 1; }
	bats tests/unit/*.bats

test-verbose: setup-tests ## Run BATS tests with verbose output
	@command -v bats >/dev/null 2>&1 || { echo "bats not found. Install: npm i -g bats"; exit 1; }
	bats --trace tests/unit/*.bats

lint: ## Run ShellCheck on all scripts
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found. Install: apt install shellcheck"; exit 1; }
	shellcheck --color=auto -x bin/server-tools lib/*.sh lib/webserver/*.sh
	@echo "ShellCheck passed"

format: ## Format scripts with shfmt
	@command -v shfmt >/dev/null 2>&1 || { echo "shfmt not found. Install: go install mvdan.cc/sh/v3/cmd/shfmt@latest"; exit 1; }
	shfmt -i 4 -bn -ci -w bin/server-tools lib/*.sh lib/webserver/*.sh

format-check: ## Check formatting without changes
	@command -v shfmt >/dev/null 2>&1 || { echo "shfmt not found. Install: go install mvdan.cc/sh/v3/cmd/shfmt@latest"; exit 1; }
	shfmt -i 4 -bn -ci -d bin/server-tools lib/*.sh lib/webserver/*.sh
	@echo "Format check passed"

check: lint format-check test ## Run all checks (lint + format + test)
	@echo "All checks passed"

clean: ## Remove test artifacts
	rm -rf tests/libs
	@echo "Cleaned"
