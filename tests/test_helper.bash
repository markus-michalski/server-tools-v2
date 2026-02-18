#!/bin/bash
# BATS test helper - loaded by all test files

# Project paths
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT

# Load BATS extensions
load "${PROJECT_ROOT}/tests/libs/bats-support/load.bash"
load "${PROJECT_ROOT}/tests/libs/bats-assert/load.bash"
load "${PROJECT_ROOT}/tests/libs/bats-file/load.bash"

# Per-test isolation: each test gets its own temp directory
setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR

    # Override paths for testing (prevents touching real system)
    export ST_CREDENTIAL_DIR="${TEST_TMPDIR}/credentials"
    export ST_AUDIT_LOG="${TEST_TMPDIR}/audit.log"
    export ST_BACKUP_DIR="${TEST_TMPDIR}/backups"
    export ST_CONFIG_FILE="${TEST_TMPDIR}/config"

    mkdir -p "${ST_CREDENTIAL_DIR}" "${ST_BACKUP_DIR}"
}

teardown() {
    if [[ -d "${TEST_TMPDIR:-}" ]]; then
        rm -rf "${TEST_TMPDIR}"
    fi
}

# Mock a system command with custom behavior
# Usage: mock_command "mysql" 'echo "mocked"; exit 0'
mock_command() {
    local cmd="$1"
    local body="$2"

    mkdir -p "${TEST_TMPDIR}/bin"
    cat > "${TEST_TMPDIR}/bin/${cmd}" <<EOF
#!/bin/bash
${body}
EOF
    chmod +x "${TEST_TMPDIR}/bin/${cmd}"
    export PATH="${TEST_TMPDIR}/bin:${PATH}"
}

# Source a library for testing
# Usage: source_lib "core"
source_lib() {
    local lib="$1"
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/lib/${lib}.sh"
}
