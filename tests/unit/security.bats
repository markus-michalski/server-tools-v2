#!/usr/bin/env bats

load ../test_helper

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR NO_COLOR=1
    export ST_CONFIG_FILE="${TEST_TMPDIR}/config"
    export ST_CREDENTIAL_DIR="${TEST_TMPDIR}/credentials"
    export ST_AUDIT_LOG="${TEST_TMPDIR}/audit.log"
    export ST_BACKUP_DIR="${TEST_TMPDIR}/backups"
    export ST_ALLOWED_DOCROOT_PATHS="/var/www:/srv/www"
    export ST_PASSWORD_MIN_LENGTH=12
    export ST_PASSWORD_LENGTH=25
    export ST_AUDIT_LOGGING=true
    mkdir -p "${ST_CREDENTIAL_DIR}" "${ST_BACKUP_DIR}"
    source_lib "security"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# --- Domain validation ---

@test "validate_input accepts valid domain" {
    run validate_input "example.com" "domain"
    assert_success
}

@test "validate_input accepts subdomain" {
    run validate_input "sub.example.com" "domain"
    assert_success
}

@test "validate_input rejects domain with path traversal" {
    run validate_input "../etc/passwd" "domain"
    assert_failure
}

@test "validate_input rejects domain with spaces" {
    run validate_input "exam ple.com" "domain"
    assert_failure
}

@test "validate_input rejects empty domain" {
    run validate_input "" "domain"
    assert_failure
}

# --- Database validation ---

@test "validate_input accepts valid database name" {
    run validate_input "my_database" "database"
    assert_success
}

@test "validate_input rejects database with special chars" {
    run validate_input "my;database" "database"
    assert_failure
}

@test "validate_input rejects database with SQL injection" {
    run validate_input "db'; DROP TABLE--" "database"
    assert_failure
}

@test "validate_input rejects database name over 64 chars" {
    local long_name
    long_name=$(printf 'a%.0s' {1..65})
    run validate_input "$long_name" "database"
    assert_failure
}

# --- Username validation ---

@test "validate_input accepts valid username" {
    run validate_input "db_user" "username"
    assert_success
}

@test "validate_input rejects username over 32 chars" {
    local long_name
    long_name=$(printf 'a%.0s' {1..33})
    run validate_input "$long_name" "username"
    assert_failure
}

# --- Email validation ---

@test "validate_input accepts valid email" {
    run validate_input "user@example.com" "email"
    assert_success
}

@test "validate_input rejects email without @" {
    run validate_input "userexample.com" "email"
    assert_failure
}

# --- Password validation ---

@test "validate_input accepts password meeting min length" {
    run validate_input "abcdefghijklmnop" "password"
    assert_success
}

@test "validate_input rejects short password" {
    run validate_input "short" "password"
    assert_failure
}

# --- PHP version validation ---

@test "validate_input accepts valid PHP version" {
    run validate_input "8.3" "php_version"
    assert_success
}

@test "validate_input rejects unsupported PHP version" {
    run validate_input "5.6" "php_version"
    assert_failure
}

# --- Cron schedule validation ---

@test "validate_input accepts valid cron schedule" {
    run validate_input "0 4 * * *" "cron_schedule"
    assert_success
}

@test "validate_input rejects invalid cron schedule" {
    run validate_input "every day at 4" "cron_schedule"
    assert_failure
}

# --- Unknown type ---

@test "validate_input rejects unknown type" {
    run validate_input "test" "unknown_type"
    assert_failure
    assert_output --partial "Unknown validation type"
}

# --- MySQL escaping ---

@test "mysql_escape escapes single quotes" {
    run mysql_escape "it's a test"
    assert_output "it\\'s a test"
}

@test "mysql_escape escapes backslashes" {
    run mysql_escape 'back\slash'
    assert_output 'back\\slash'
}

# --- Password generation ---

@test "generate_password creates password of correct length" {
    local pw
    pw=$(generate_password 20)
    assert_equal "${#pw}" "20"
}

@test "generate_password uses default length from config" {
    ST_PASSWORD_LENGTH=15
    local pw
    pw=$(generate_password)
    assert_equal "${#pw}" "15"
}

# --- Audit logging ---

@test "audit_log creates log file" {
    audit_log "INFO" "Test action"
    assert_file_exists "$ST_AUDIT_LOG"
}

@test "audit_log writes correct format" {
    audit_log "INFO" "Test action"
    run cat "$ST_AUDIT_LOG"
    assert_output --regexp "\[.*\] \[INFO\] user=.* action=Test action"
}

@test "audit_log skips when disabled" {
    ST_AUDIT_LOGGING="false"
    audit_log "INFO" "Should not appear"
    assert_file_not_exists "$ST_AUDIT_LOG"
}

# --- Safe file write ---

@test "safe_write_file creates file with content" {
    local test_file="${TEST_TMPDIR}/test.txt"
    safe_write_file "$test_file" "hello world" 644

    assert_file_exists "$test_file"
    run cat "$test_file"
    assert_output "hello world"
}

@test "safe_write_file sets correct permissions" {
    local test_file="${TEST_TMPDIR}/secret.txt"
    safe_write_file "$test_file" "secret" 600

    local perms
    perms=$(stat -c '%a' "$test_file")
    assert_equal "$perms" "600"
}
