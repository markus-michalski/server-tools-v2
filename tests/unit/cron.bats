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
    export ST_APACHE_SERVER_ADMIN="webmaster@localhost"
    export ST_ALLOWED_DOCROOT_PATHS="/var/www:/srv/www"
    export ST_CREDENTIAL_FILE_PERMISSIONS=600
    mkdir -p "${ST_CREDENTIAL_DIR}" "${ST_BACKUP_DIR}"
    source_lib "cron"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# --- cron_file_name (pure function) ---

@test "cron_file_name sanitizes special characters" {
    run cron_file_name "My Cron Job!"
    assert_success
    assert_output "my_cron_job_"
}

@test "cron_file_name lowercases input" {
    run cron_file_name "SSL_RENEWAL"
    assert_success
    assert_output "ssl_renewal"
}

@test "cron_file_name preserves valid characters" {
    run cron_file_name "backup-daily"
    assert_success
    assert_output "backup-daily"
}

# --- generate_cron_content (pure function) ---

@test "generate_cron_content includes schedule and command" {
    run generate_cron_content "0 4 * * *" "/usr/local/bin/backup.sh"
    assert_success
    assert_output --partial "0 4 * * * root /usr/local/bin/backup.sh"
}

@test "generate_cron_content uses custom user" {
    run generate_cron_content "*/5 * * * *" "/opt/check.sh" "www-data"
    assert_success
    assert_output --partial "*/5 * * * * www-data /opt/check.sh"
}

@test "generate_cron_content includes creation comment" {
    run generate_cron_content "0 0 * * *" "/bin/true"
    assert_success
    assert_output --partial "Created"
    assert_output --partial "server-tools"
}

# --- cron_exists ---

@test "cron_exists returns failure for nonexistent cron" {
    run cron_exists "nonexistent-cron-job"
    assert_failure
}

# --- add_cron input validation ---

@test "add_cron rejects empty schedule" {
    run add_cron "" "/bin/true" "test-job"
    assert_failure
    assert_output --partial "required"
}

@test "add_cron rejects empty command" {
    run add_cron "0 4 * * *" "" "test-job"
    assert_failure
    assert_output --partial "required"
}

@test "add_cron rejects invalid schedule format" {
    run add_cron "invalid schedule" "/bin/true" "test-job"
    assert_failure
    assert_output --partial "Invalid cron"
}

@test "add_cron accepts valid 5-field schedule" {
    # Validate that the schedule passes validation
    run validate_input "0 4 * * *" "cron_schedule"
    assert_success
}

@test "add_cron accepts schedule with ranges and steps" {
    run validate_input "*/15 0-6 1,15 * 1-5" "cron_schedule"
    assert_success
}

# --- remove_cron input validation ---

@test "remove_cron rejects empty pattern" {
    run remove_cron ""
    assert_failure
    assert_output --partial "required"
}

# --- list_crons ---

@test "list_crons shows header" {
    run list_crons
    assert_output --partial "Cron Jobs"
}
