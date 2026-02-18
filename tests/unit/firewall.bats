#!/usr/bin/env bats

load ../test_helper

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR NO_COLOR=1
    export ST_CONFIG_FILE="${TEST_TMPDIR}/config"
    export ST_CREDENTIAL_DIR="${TEST_TMPDIR}/credentials"
    export ST_AUDIT_LOG="${TEST_TMPDIR}/audit.log"
    export ST_BACKUP_DIR="${TEST_TMPDIR}/backups"
    export ST_AUTO_BACKUP=true
    export ST_BACKUP_RETENTION_DAYS=30
    export ST_AUDIT_LOGGING=true
    export ST_PASSWORD_LENGTH=25
    export ST_PASSWORD_MIN_LENGTH=12
    export ST_ALLOWED_DOCROOT_PATHS="/var/www:/srv/www"
    export ST_CREDENTIAL_FILE_PERMISSIONS=600
    mkdir -p "${ST_CREDENTIAL_DIR}" "${ST_BACKUP_DIR}"
    source_lib "firewall"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# --- ufw_installed ---

@test "ufw_installed returns success when ufw exists" {
    mock_command "ufw" 'echo "ufw"'
    run ufw_installed
    assert_success
}

@test "ufw_installed returns failure when ufw missing" {
    command_exists() { return 1; }
    run ufw_installed
    assert_failure
}

# --- show_firewall_status ---

@test "show_firewall_status fails when ufw not installed" {
    command_exists() { return 1; }
    run show_firewall_status
    assert_failure
    assert_output --partial "not installed"
}

@test "show_firewall_status shows header when ufw installed" {
    mock_command "ufw" 'echo "Status: active"; echo "To     Action     From"; echo "--     ------     ----"'
    run show_firewall_status
    assert_success
    assert_output --partial "Firewall Status"
}

# --- allow_port ---

@test "allow_port rejects invalid port number" {
    mock_command "ufw" 'exit 0'
    run allow_port "99999"
    assert_failure
    assert_output --partial "Invalid port"
}

@test "allow_port rejects port 0" {
    mock_command "ufw" 'exit 0'
    run allow_port "0"
    assert_failure
    assert_output --partial "Invalid port"
}

@test "allow_port rejects non-numeric port" {
    mock_command "ufw" 'exit 0'
    run allow_port "abc"
    assert_failure
    assert_output --partial "Invalid port"
}

@test "allow_port accepts valid port" {
    mock_command "ufw" 'echo "Rule added"; exit 0'
    run allow_port "8080"
    assert_success
    assert_output --partial "allowed"
}

@test "allow_port accepts valid port with protocol" {
    mock_command "ufw" 'echo "Rule added"; exit 0'
    run allow_port "443" "tcp"
    assert_success
    assert_output --partial "allowed"
}

@test "allow_port rejects invalid protocol" {
    mock_command "ufw" 'exit 0'
    run allow_port "80" "icmp"
    assert_failure
    assert_output --partial "Invalid protocol"
}

@test "allow_port fails when ufw not installed" {
    command_exists() { return 1; }
    run allow_port "80"
    assert_failure
    assert_output --partial "not installed"
}

# --- deny_port ---

@test "deny_port rejects invalid port" {
    mock_command "ufw" 'exit 0'
    run deny_port "70000"
    assert_failure
}

@test "deny_port accepts valid port" {
    mock_command "ufw" 'echo "Rule added"; exit 0'
    run deny_port "3306"
    assert_success
    assert_output --partial "denied"
}

@test "deny_port accepts valid port with protocol" {
    mock_command "ufw" 'echo "Rule added"; exit 0'
    run deny_port "3306" "tcp"
    assert_success
    assert_output --partial "denied"
}

# --- toggle_firewall ---

@test "toggle_firewall fails when ufw not installed" {
    command_exists() { return 1; }
    run toggle_firewall
    assert_failure
    assert_output --partial "not installed"
}

# --- ufw_is_enabled ---

@test "ufw_is_enabled detects active firewall" {
    mock_command "ufw" 'echo "Status: active"'
    run ufw_is_enabled
    assert_success
}

@test "ufw_is_enabled detects inactive firewall" {
    mock_command "ufw" 'echo "Status: inactive"'
    run ufw_is_enabled
    assert_failure
}
