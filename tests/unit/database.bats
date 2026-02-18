#!/usr/bin/env bats

load ../test_helper

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR NO_COLOR=1
    export ST_CONFIG_FILE="${TEST_TMPDIR}/config"
    export ST_CREDENTIAL_DIR="${TEST_TMPDIR}/credentials"
    export ST_AUDIT_LOG="${TEST_TMPDIR}/audit.log"
    export ST_BACKUP_DIR="${TEST_TMPDIR}/backups"
    export ST_MYSQL_CONFIG_FILE="${TEST_TMPDIR}/.my.cnf"
    export ST_AUTO_BACKUP=true
    export ST_BACKUP_RETENTION_DAYS=30
    export ST_AUDIT_LOGGING=true
    export ST_PASSWORD_LENGTH=25
    export ST_PASSWORD_MIN_LENGTH=12
    export ST_DEFAULT_CHARSET=utf8mb4
    export ST_DEFAULT_COLLATION=utf8mb4_unicode_ci
    export ST_CREDENTIAL_FILE_PERMISSIONS=600
    export ST_ALLOWED_DOCROOT_PATHS="/var/www:/srv/www"
    mkdir -p "${ST_CREDENTIAL_DIR}" "${ST_BACKUP_DIR}"

    # Create mock .my.cnf
    echo 'password=testpass123' > "$ST_MYSQL_CONFIG_FILE"

    # Reset loaded state
    _MYSQL_LOADED=false

    source_lib "database"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# --- Credential loading ---

@test "load_mysql_credentials reads password from .my.cnf" {
    load_mysql_credentials
    assert_equal "$_MYSQL_PASS" "testpass123"
}

@test "load_mysql_credentials fails when file missing" {
    rm -f "$ST_MYSQL_CONFIG_FILE"
    _MYSQL_LOADED=false
    run load_mysql_credentials
    assert_failure
    assert_output --partial "MySQL config not found"
}

@test "load_mysql_credentials loads only once" {
    load_mysql_credentials
    assert_equal "$_MYSQL_LOADED" "true"

    # Change file content - should not reload
    echo 'password=changed' > "$ST_MYSQL_CONFIG_FILE"
    load_mysql_credentials
    assert_equal "$_MYSQL_PASS" "testpass123"
}

# --- Building blocks with mocked mysql ---

@test "db_exists returns success when database exists" {
    mock_command "mysql" 'exit 0'
    load_mysql_credentials
    run db_exists "testdb"
    assert_success
}

@test "db_exists returns failure when database missing" {
    mock_command "mysql" 'echo "ERROR 1049"; exit 1'
    load_mysql_credentials
    run db_exists "nonexistent"
    assert_failure
}

@test "user_exists returns success when user exists" {
    mock_command "mysql" 'echo -e "COUNT(*)\n1"'
    load_mysql_credentials
    run user_exists "testuser"
    assert_success
}

@test "user_exists returns failure when user missing" {
    mock_command "mysql" 'echo -e "COUNT(*)\n0"'
    load_mysql_credentials
    run user_exists "nonexistent"
    assert_failure
}

@test "create_db_only calls mysql with CREATE DATABASE" {
    local captured_query=""
    mock_command "mysql" '
        for arg in "$@"; do
            if [[ "$arg" == *"CREATE DATABASE"* ]]; then
                echo "OK"
                exit 0
            fi
            if [[ "$arg" == *"USE"* ]]; then
                exit 1  # db_exists check - return "not found"
            fi
        done
        exit 0
    '
    load_mysql_credentials
    run create_db_only "newdb"
    assert_success
}

@test "create_user_only calls mysql with CREATE USER" {
    mock_command "mysql" 'exit 0'
    load_mysql_credentials
    run create_user_only "newuser" "password123"
    assert_success
}

@test "grant_privileges calls mysql with GRANT" {
    mock_command "mysql" 'exit 0'
    load_mysql_credentials
    run grant_privileges "mydb" "myuser"
    assert_success
}

@test "drop_db_only calls mysql with DROP DATABASE" {
    mock_command "mysql" 'exit 0'
    load_mysql_credentials
    run drop_db_only "olddb"
    assert_success
}

@test "drop_user_only calls mysql with DROP USER" {
    mock_command "mysql" 'exit 0'
    load_mysql_credentials
    run drop_user_only "olduser"
    assert_success
}

# --- Credential file management ---

@test "save_credentials creates file with correct content" {
    save_credentials "testdb" "testuser" "testpass"

    local cred_file="${ST_CREDENTIAL_DIR}/testdb.txt"
    assert_file_exists "$cred_file"

    run cat "$cred_file"
    assert_output --partial "Database: testdb"
    assert_output --partial "Username: testuser"
    assert_output --partial "Password: testpass"
    assert_output --partial "Symfony DATABASE_URL"
    assert_output --partial "PDO DSN"
}

@test "save_credentials sets correct permissions" {
    save_credentials "testdb" "testuser" "testpass"

    local perms
    perms=$(stat -c '%a' "${ST_CREDENTIAL_DIR}/testdb.txt")
    assert_equal "$perms" "600"
}

@test "save_credentials creates credential directory if missing" {
    export ST_CREDENTIAL_DIR="${TEST_TMPDIR}/new_creds"
    save_credentials "testdb" "testuser" "testpass"
    assert_dir_exists "$ST_CREDENTIAL_DIR"
}

@test "remove_credentials deletes credential file" {
    echo "test" > "${ST_CREDENTIAL_DIR}/testdb.txt"
    remove_credentials "testdb"
    assert_file_not_exists "${ST_CREDENTIAL_DIR}/testdb.txt"
}

@test "remove_credentials handles missing file gracefully" {
    run remove_credentials "nonexistent"
    assert_success
}

# --- High-level operation validation ---

@test "create_database rejects invalid database name" {
    run create_database "invalid;name" "user" "pass"
    assert_failure
    assert_output --partial "Invalid database name"
}

@test "create_database rejects invalid username" {
    run create_database "validdb" "invalid;user" "pass"
    assert_failure
    assert_output --partial "Invalid username"
}

@test "create_db_for_user rejects invalid database name" {
    run create_db_for_user "bad;name" "user"
    assert_failure
}

@test "assign_db_to_user rejects invalid inputs" {
    run assign_db_to_user "bad;db" "user"
    assert_failure
}

@test "delete_database rejects invalid database name" {
    run delete_database "bad;db"
    assert_failure
}

# --- delete_database_keep_user validation ---

@test "delete_database_keep_user rejects invalid database name" {
    run delete_database_keep_user "bad;db"
    assert_failure
    assert_output --partial "Invalid database name"
}

@test "delete_database_keep_user rejects invalid username" {
    mock_command "mysql" 'exit 0'
    load_mysql_credentials
    run delete_database_keep_user "validdb" "bad;user"
    assert_failure
}

# --- reassign_db_to_user validation ---

@test "reassign_db_to_user rejects invalid database name" {
    run reassign_db_to_user "bad;db" "user1" "user2"
    assert_failure
    assert_output --partial "Invalid database name"
}

@test "reassign_db_to_user rejects invalid old username" {
    run reassign_db_to_user "validdb" "bad;user" "user2"
    assert_failure
    assert_output --partial "Invalid username"
}

@test "reassign_db_to_user rejects invalid new username" {
    run reassign_db_to_user "validdb" "user1" "bad;user"
    assert_failure
    assert_output --partial "Invalid username"
}

@test "reassign_db_to_user rejects same old and new user" {
    mock_command "mysql" '
        for arg in "$@"; do
            if [[ "$arg" == *"USE"* ]]; then
                exit 0
            fi
            if [[ "$arg" == *"COUNT"* ]]; then
                echo -e "COUNT(*)\n1"
                exit 0
            fi
        done
        exit 0
    '
    load_mysql_credentials
    run reassign_db_to_user "validdb" "sameuser" "sameuser"
    assert_failure
    assert_output --partial "same"
}

@test "revoke_privileges calls mysql with REVOKE" {
    mock_command "mysql" 'exit 0'
    load_mysql_credentials
    run revoke_privileges "mydb" "myuser"
    assert_success
}
