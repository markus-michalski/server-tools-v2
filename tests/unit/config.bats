#!/usr/bin/env bats

load ../test_helper

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR NO_COLOR=1
    export ST_CONFIG_FILE="${TEST_TMPDIR}/config"
    export ST_CREDENTIAL_DIR="${TEST_TMPDIR}/credentials"
    export ST_AUDIT_LOG="${TEST_TMPDIR}/audit.log"
    export ST_BACKUP_DIR="${TEST_TMPDIR}/backups"
    mkdir -p "${ST_CREDENTIAL_DIR}" "${ST_BACKUP_DIR}"
    source_lib "config"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

@test "load_config succeeds with no config file" {
    run load_config
    assert_success
}

@test "load_config loads values from config file" {
    echo 'ST_PASSWORD_LENGTH=30' > "$ST_CONFIG_FILE"
    chmod 600 "$ST_CONFIG_FILE"

    source_lib "config"
    load_config

    assert_equal "$ST_PASSWORD_LENGTH" "30"
}

@test "load_config skips ownership checks for non-root users" {
    echo 'ST_PASSWORD_LENGTH=30' > "$ST_CONFIG_FILE"
    chmod 644 "$ST_CONFIG_FILE"

    # Non-root: ownership/permission checks are skipped, config loads normally
    run load_config
    assert_success
}

@test "validate_config resets bad password length" {
    ST_PASSWORD_LENGTH=5
    validate_config
    assert_equal "$ST_PASSWORD_LENGTH" "25"
}

@test "validate_config resets bad min password length" {
    ST_PASSWORD_MIN_LENGTH=3
    validate_config
    assert_equal "$ST_PASSWORD_MIN_LENGTH" "12"
}

@test "validate_config resets bad backup retention" {
    ST_BACKUP_RETENTION_DAYS=999
    validate_config
    assert_equal "$ST_BACKUP_RETENTION_DAYS" "30"
}

@test "validate_config accepts valid values" {
    ST_PASSWORD_LENGTH=20
    ST_PASSWORD_MIN_LENGTH=12
    ST_BACKUP_RETENTION_DAYS=60
    run validate_config
    assert_success
}

@test "show_config displays configuration" {
    run show_config
    assert_success
    assert_output --partial "Credentials:"
    assert_output --partial "PHP version:"
    assert_output --partial "Auto-backup:"
}

@test "default values are set" {
    assert_equal "$ST_DEFAULT_PHP_VERSION" "8.3"
    assert_equal "$ST_DEFAULT_CHARSET" "utf8mb4"
    assert_equal "$ST_PASSWORD_LENGTH" "25"
    assert_equal "$ST_AUTO_BACKUP" "true"
}
