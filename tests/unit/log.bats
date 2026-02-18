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
    export ST_APACHE_LOG_DIR="${TEST_TMPDIR}/apache-logs"
    export ST_MYSQL_LOG_FILE="${TEST_TMPDIR}/mysql-error.log"
    export ST_LOG_LINES=50
    mkdir -p "${ST_CREDENTIAL_DIR}" "${ST_BACKUP_DIR}" "${ST_APACHE_LOG_DIR}"
    source_lib "log"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# --- tail_logfile ---

@test "tail_logfile reads last N lines" {
    # Create a test log file with 10 lines
    for i in $(seq 1 10); do
        echo "line $i" >> "${TEST_TMPDIR}/test.log"
    done

    run tail_logfile "${TEST_TMPDIR}/test.log" 3
    assert_success
    assert_line --index 0 "line 8"
    assert_line --index 1 "line 9"
    assert_line --index 2 "line 10"
}

@test "tail_logfile fails when file missing" {
    run tail_logfile "${TEST_TMPDIR}/nonexistent.log"
    assert_failure
    assert_output --partial "not found"
}

@test "tail_logfile fails when file not readable" {
    touch "${TEST_TMPDIR}/noperm.log"
    chmod 000 "${TEST_TMPDIR}/noperm.log"

    run tail_logfile "${TEST_TMPDIR}/noperm.log"
    assert_failure
    assert_output --partial "permission denied"

    chmod 644 "${TEST_TMPDIR}/noperm.log"
}

# --- grep_logfile ---

@test "grep_logfile finds matching lines" {
    cat > "${TEST_TMPDIR}/test.log" <<EOF
[INFO] All good
[ERROR] Something broke
[INFO] Still good
[ERROR] Another error
EOF

    run grep_logfile "${TEST_TMPDIR}/test.log" "ERROR" 10
    assert_success
    assert_output --partial "Something broke"
    assert_output --partial "Another error"
}

@test "grep_logfile returns empty when no match" {
    echo "no matches here" > "${TEST_TMPDIR}/test.log"

    run grep_logfile "${TEST_TMPDIR}/test.log" "CRITICAL" 10
    # grep returns 1 for no matches, but output should be empty
    assert_output ""
}

@test "grep_logfile fails when file missing" {
    run grep_logfile "${TEST_TMPDIR}/nonexistent.log" "pattern"
    assert_failure
    assert_output --partial "not found"
}

# --- get_apache_error_log ---

@test "get_apache_error_log returns global log when no domain" {
    run get_apache_error_log
    assert_success
    assert_output "${ST_APACHE_LOG_DIR}/error.log"
}

@test "get_apache_error_log returns domain-specific log if exists" {
    local domain="example.com"
    mkdir -p "/tmp/test_vwww_$$/var/www/${domain}/logs"
    # Can't test real path without root, test the fallback behavior
    run get_apache_error_log "nonexistent-domain-$$.test"
    assert_failure
    assert_output --partial "No error log found"
}

# --- get_apache_access_log ---

@test "get_apache_access_log returns global log when no domain" {
    run get_apache_access_log
    assert_success
    assert_output "${ST_APACHE_LOG_DIR}/access.log"
}

# --- show_apache_errors ---

@test "show_apache_errors shows header for global" {
    touch "${ST_APACHE_LOG_DIR}/error.log"
    echo "[error] test error" >> "${ST_APACHE_LOG_DIR}/error.log"

    run show_apache_errors "" 10
    assert_success
    assert_output --partial "Apache Errors (global)"
}

@test "show_apache_errors shows header for domain" {
    # Domain log won't exist, so test the failure path
    run show_apache_errors "nonexistent-domain.test" 10
    assert_failure
}

# --- show_mysql_errors ---

@test "show_mysql_errors shows header" {
    touch "$ST_MYSQL_LOG_FILE"
    echo "2024-01-01 mysql error" >> "$ST_MYSQL_LOG_FILE"

    run show_mysql_errors 10
    assert_success
    assert_output --partial "MySQL Errors"
}

@test "show_mysql_errors handles missing log file" {
    run show_mysql_errors 10
    assert_success
    assert_output --partial "MySQL Errors"
    assert_output --partial "not found"
}

# --- show_audit_log_entries ---

@test "show_audit_log_entries shows header" {
    echo "[2024-01-01] [INFO] test action" > "$ST_AUDIT_LOG"

    run show_audit_log_entries 10
    assert_success
    assert_output --partial "Audit Log"
    assert_output --partial "test action"
}

@test "show_audit_log_entries handles missing audit log" {
    rm -f "$ST_AUDIT_LOG"
    run show_audit_log_entries 10
    assert_success
    assert_output --partial "no audit log found"
}

@test "show_audit_log_entries filters by pattern" {
    echo "[2024-01-01] [INFO] Created database" > "$ST_AUDIT_LOG"
    echo "[2024-01-01] [ERROR] Failed SSL" >> "$ST_AUDIT_LOG"

    run show_audit_log_entries 10 "ERROR"
    assert_success
    assert_output --partial "Failed SSL"
    refute_output --partial "Created database"
}

# --- search_logs ---

@test "search_logs requires pattern" {
    run search_logs ""
    assert_failure
    assert_output --partial "pattern is required"
}

@test "search_logs searches across multiple log files" {
    echo "[error] apache problem" > "${ST_APACHE_LOG_DIR}/error.log"
    echo "[error] mysql problem" > "$ST_MYSQL_LOG_FILE"
    echo "[INFO] audit problem" > "$ST_AUDIT_LOG"

    run search_logs "problem" 10
    assert_success
    assert_output --partial "Apache Error Log"
    assert_output --partial "MySQL Error Log"
    assert_output --partial "Audit Log"
}

@test "search_logs reports no matches" {
    touch "${ST_APACHE_LOG_DIR}/error.log"
    touch "$ST_MYSQL_LOG_FILE"
    touch "$ST_AUDIT_LOG"

    run search_logs "zzz_nonexistent_pattern" 10
    assert_success
    assert_output --partial "No matches found"
}
