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
    export ST_DEFAULT_PHP_VERSION=8.3
    export ST_PHP_VERSIONS_TO_SCAN="7.4 8.0 8.1 8.2 8.3 8.4"
    export ST_ALLOWED_DOCROOT_PATHS="/var/www:/srv/www"
    export ST_CREDENTIAL_FILE_PERMISSIONS=600
    mkdir -p "${ST_CREDENTIAL_DIR}" "${ST_BACKUP_DIR}"
    source_lib "status"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# --- check_service ---

@test "check_service returns 'running' for active service" {
    mock_command "systemctl" '
        if [[ "$1" == "list-unit-files" ]]; then
            exit 0
        elif [[ "$1" == "is-active" ]]; then
            exit 0
        fi
    '
    run check_service "apache2"
    assert_success
    assert_output "running"
}

@test "check_service returns 'stopped' for inactive service" {
    mock_command "systemctl" '
        if [[ "$1" == "list-unit-files" ]]; then
            exit 0
        elif [[ "$1" == "is-active" ]]; then
            exit 1
        fi
    '
    run check_service "mysql"
    assert_failure
    assert_output "stopped"
}

# --- get_disk_usage ---

@test "get_disk_usage produces output" {
    run get_disk_usage
    assert_success
    # Should produce some output (may use fallback)
    [[ -n "$output" ]]
}

# --- get_memory_usage ---

@test "get_memory_usage produces output" {
    run get_memory_usage
    assert_success
    [[ -n "$output" ]]
}

# --- get_load_average ---

@test "get_load_average produces output" {
    run get_load_average
    assert_success
    [[ -n "$output" ]]
}

# --- get_os_info ---

@test "get_os_info produces output" {
    run get_os_info
    assert_success
    [[ -n "$output" ]]
}

# --- show_service_status ---

@test "show_service_status includes header" {
    mock_command "systemctl" '
        if [[ "$1" == "list-unit-files" ]]; then
            exit 0
        elif [[ "$1" == "is-active" ]]; then
            exit 0
        fi
    '
    run show_service_status
    assert_success
    assert_output --partial "Service Status"
}

@test "show_service_status lists core services" {
    mock_command "systemctl" '
        if [[ "$1" == "list-unit-files" ]]; then
            exit 0
        elif [[ "$1" == "is-active" ]]; then
            exit 0
        fi
    '
    run show_service_status
    assert_success
    assert_output --partial "apache2"
    assert_output --partial "mysql"
}

# --- show_system_resources ---

@test "show_system_resources includes all sections" {
    run show_system_resources
    assert_success
    assert_output --partial "System Resources"
    assert_output --partial "Load:"
    assert_output --partial "Memory:"
    assert_output --partial "Disk:"
}
