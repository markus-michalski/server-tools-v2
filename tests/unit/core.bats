#!/usr/bin/env bats

load ../test_helper

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR NO_COLOR=1
    source_lib "core"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

@test "log_info writes to stderr" {
    run log_info "test message"
    assert_success
    assert_output --partial "[INFO]"
    assert_output --partial "test message"
}

@test "log_warn writes to stderr" {
    run log_warn "warning message"
    assert_success
    assert_output --partial "[WARN]"
    assert_output --partial "warning message"
}

@test "log_error writes to stderr" {
    run log_error "error message"
    assert_success
    assert_output --partial "[ERROR]"
    assert_output --partial "error message"
}

@test "log_debug is silent when ST_DEBUG is not set" {
    unset ST_DEBUG
    run log_debug "debug message"
    assert_success
    refute_output --partial "debug message"
}

@test "log_debug outputs when ST_DEBUG=1" {
    export ST_DEBUG=1
    run log_debug "debug message"
    assert_success
    assert_output --partial "[DEBUG]"
    assert_output --partial "debug message"
}

@test "die exits with code 1" {
    run die "fatal error"
    assert_failure
    assert_output --partial "[ERROR]"
    assert_output --partial "fatal error"
}

@test "command_exists returns 0 for existing command" {
    run command_exists "bash"
    assert_success
}

@test "command_exists returns 1 for missing command" {
    run command_exists "nonexistent_command_xyz"
    assert_failure
}

@test "require_command succeeds for existing command" {
    run require_command "bash"
    assert_success
}

@test "require_command dies for missing command" {
    run require_command "nonexistent_command_xyz" "apt install xyz"
    assert_failure
    assert_output --partial "nonexistent_command_xyz"
    assert_output --partial "apt install xyz"
}

@test "check_root fails for non-root user" {
    # Skip if actually running as root
    if [[ "$EUID" -eq 0 ]]; then
        skip "Running as root"
    fi
    run check_root
    assert_failure
    assert_output --partial "must be run as root"
}

@test "print_header formats correctly" {
    run print_header "Test Section"
    assert_success
    assert_output --partial "=== Test Section ==="
}

# --- mysql_available ---

@test "mysql_available returns success when mysql and mysqldump exist" {
    mock_command "mysql" 'exit 0'
    mock_command "mysqldump" 'exit 0'
    run mysql_available
    assert_success
}

@test "mysql_available returns failure when mysql is missing" {
    mock_command "mysqldump" 'exit 0'
    PATH="${TEST_TMPDIR}/bin" run mysql_available
    assert_failure
}

@test "mysql_available returns failure when mysqldump is missing" {
    mock_command "mysql" 'exit 0'
    PATH="${TEST_TMPDIR}/bin" run mysql_available
    assert_failure
}

@test "mysql_available returns failure when neither is installed" {
    PATH="${TEST_TMPDIR}/bin" run mysql_available
    assert_failure
}

@test "mysql_available returns success when only mariadb and mariadb-dump exist" {
    mock_command "mariadb" 'exit 0'
    mock_command "mariadb-dump" 'exit 0'
    PATH="${TEST_TMPDIR}/bin" run mysql_available
    assert_success
}

@test "mysql_available returns failure when mariadb exists but dump tool is missing" {
    mock_command "mariadb" 'exit 0'
    PATH="${TEST_TMPDIR}/bin" run mysql_available
    assert_failure
}

# --- mysql_bin / mysqldump_bin ---

@test "mysql_bin returns mysql when mysql is available" {
    mock_command "mysql" 'exit 0'
    run mysql_bin
    assert_output "mysql"
}

@test "mysql_bin returns mariadb when only mariadb is available" {
    mock_command "mariadb" 'exit 0'
    PATH="${TEST_TMPDIR}/bin" run mysql_bin
    assert_output "mariadb"
}

@test "mysqldump_bin returns mysqldump when mysqldump is available" {
    mock_command "mysqldump" 'exit 0'
    run mysqldump_bin
    assert_output "mysqldump"
}

@test "mysqldump_bin returns mariadb-dump when only mariadb-dump is available" {
    mock_command "mariadb-dump" 'exit 0'
    PATH="${TEST_TMPDIR}/bin" run mysqldump_bin
    assert_output "mariadb-dump"
}
