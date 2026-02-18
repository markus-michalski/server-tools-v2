# Contributing to Server Tools v2

## Development Setup

```bash
git clone https://github.com/markusmichalski/server-tools-v2.git
cd server-tools-v2
make setup-tests    # Install BATS test framework
make test           # Run tests
```

## Code Style

- **Shell:** Bash 4.4+, `set -euo pipefail` at entry point only
- **Indentation:** 4 spaces (see `.editorconfig`)
- **Linting:** ShellCheck (`make lint`)
- **Formatting:** shfmt with 4-space indent (`make format`)
- **Comments:** English

## Architecture

Every module in `lib/` follows the **Composable Building Blocks** pattern:

1. **Building blocks** - Small functions that do exactly one thing
2. **High-level operations** - Compose building blocks into workflows

### Adding a New Feature

1. Identify which building blocks already exist
2. Write a new function that composes them
3. Add a menu entry in `lib/menu.sh`
4. Write tests in `tests/unit/`

### Library Guard Clauses

Every library starts with:

```bash
[[ -n "${_MODULE_SOURCED:-}" ]] && return
_MODULE_SOURCED=1
```

This prevents double-sourcing.

## Testing

Tests use [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

```bash
make test              # Run all tests
make test-verbose      # Run with verbose output
npx bats tests/unit/database.bats  # Run specific file
```

### Writing Tests

- Test pure functions directly (no mocking needed)
- Use `mock_command` from `test_helper.bash` for system commands
- Each test gets an isolated temp directory via `TEST_TMPDIR`

### Test Structure

```bash
@test "description of what is being tested" {
    run function_under_test "arg1" "arg2"
    assert_success
    assert_output --partial "expected text"
}
```

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add new feature
fix: correct a bug
docs: update documentation
refactor: restructure code
test: add or modify tests
chore: maintenance tasks
```

## Pull Requests

1. Create a feature branch from `main`
2. Make your changes
3. Ensure `make check` passes (lint + format + tests)
4. Open a PR with a clear description
