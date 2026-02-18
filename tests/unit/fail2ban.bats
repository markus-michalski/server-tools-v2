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
    source_lib "fail2ban"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# --- fail2ban_installed ---

@test "fail2ban_installed returns success when installed" {
    mock_command "fail2ban-client" 'echo "ok"'
    run fail2ban_installed
    assert_success
}

@test "fail2ban_installed returns failure when missing" {
    command_exists() { return 1; }
    run fail2ban_installed
    assert_failure
}

# --- show_fail2ban_status ---

@test "show_fail2ban_status fails when not installed" {
    command_exists() { return 1; }
    run show_fail2ban_status
    assert_failure
    assert_output --partial "not installed"
}

@test "show_fail2ban_status shows header when installed" {
    mock_command "fail2ban-client" '
        if [[ "$1" == "status" ]] && [[ -z "${2:-}" ]]; then
            echo "Status"
            echo "|- Number of jail: 1"
            echo "\`- Jail list: sshd"
            exit 0
        fi
        if [[ "$1" == "status" ]] && [[ "$2" == "sshd" ]]; then
            echo "Status for the jail: sshd"
            echo "|- Filter"
            echo "   |- Currently failed: 0"
            echo "   \`- Total failed: 5"
            echo "\`- Actions"
            echo "   |- Currently banned: 2"
            echo "   \`- Total banned: 10"
            exit 0
        fi
    '
    run show_fail2ban_status
    assert_success
    assert_output --partial "Fail2Ban Status"
    assert_output --partial "sshd"
}

# --- show_banned ---

@test "show_banned fails when not installed" {
    command_exists() { return 1; }
    run show_banned
    assert_failure
    assert_output --partial "not installed"
}

@test "show_banned shows header" {
    mock_command "fail2ban-client" '
        if [[ "$1" == "status" ]] && [[ -z "${2:-}" ]]; then
            echo "Status"
            echo "|- Number of jail: 1"
            echo "\`- Jail list: sshd"
            exit 0
        fi
        if [[ "$1" == "status" ]] && [[ "$2" == "sshd" ]]; then
            echo "Status for the jail: sshd"
            echo "|- Filter"
            echo "\`- Actions"
            echo "   |- Currently banned: 0"
            echo "   |- Banned IP list:"
            echo "   \`- Total banned: 0"
            exit 0
        fi
    '
    run show_banned
    assert_success
    assert_output --partial "Banned IPs"
}

@test "show_banned reports no IPs when none banned" {
    mock_command "fail2ban-client" '
        if [[ "$1" == "status" ]] && [[ -z "${2:-}" ]]; then
            echo "Status"
            echo "|- Number of jail: 1"
            echo "\`- Jail list: sshd"
            exit 0
        fi
        if [[ "$1" == "status" ]] && [[ "$2" == "sshd" ]]; then
            echo "Status for the jail: sshd"
            echo "|- Filter"
            echo "\`- Actions"
            echo "   |- Currently banned: 0"
            echo "   |- Banned IP list:"
            echo "   \`- Total banned: 0"
            exit 0
        fi
    '
    run show_banned
    assert_success
    assert_output --partial "No IPs currently banned"
}

# --- unban_ip ---

@test "unban_ip fails when not installed" {
    command_exists() { return 1; }
    run unban_ip "1.2.3.4"
    assert_failure
    assert_output --partial "not installed"
}

@test "unban_ip rejects invalid IP address" {
    mock_command "fail2ban-client" 'exit 0'
    run unban_ip "not-an-ip"
    assert_failure
    assert_output --partial "Invalid IP"
}

@test "unban_ip rejects IP with octet > 255" {
    mock_command "fail2ban-client" 'exit 0'
    run unban_ip "192.168.1.256"
    assert_failure
    assert_output --partial "Invalid IP"
}

@test "unban_ip validates IPv4 format" {
    mock_command "fail2ban-client" '
        if [[ "$1" == "status" ]] && [[ -z "${2:-}" ]]; then
            echo "\`- Jail list:"
            exit 0
        fi
    '
    run unban_ip "1.2.3.4"
    assert_failure
    assert_output --partial "not currently banned"
}

# --- get_active_jails ---

@test "get_active_jails parses jail list" {
    mock_command "fail2ban-client" '
        echo "Status"
        echo "|- Number of jail: 2"
        echo "\`- Jail list: sshd, apache-auth"
    '
    run get_active_jails
    assert_success
    assert_output --partial "sshd"
    assert_output --partial "apache-auth"
}

@test "get_active_jails handles empty list" {
    mock_command "fail2ban-client" '
        echo "Status"
        echo "|- Number of jail: 0"
        echo "\`- Jail list:"
    '
    run get_active_jails
    assert_success
}
