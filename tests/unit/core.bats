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
