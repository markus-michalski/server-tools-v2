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
    mkdir -p "${ST_CREDENTIAL_DIR}" "${ST_BACKUP_DIR}"
    source_lib "backup"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

@test "create_backup creates tar.gz file" {
    # Create a source file to backup
    echo "test content" > "${TEST_TMPDIR}/testfile.txt"

    run create_backup "${TEST_TMPDIR}/testfile.txt" "test_backup"
    assert_success

    # Verify backup file exists
    local backup_count
    backup_count=$(ls "${ST_BACKUP_DIR}"/test_backup_*.tar.gz 2>/dev/null | wc -l)
    assert_equal "$backup_count" "1"
}

@test "create_backup fails for nonexistent source" {
    run create_backup "${TEST_TMPDIR}/nonexistent" "test"
    assert_failure
    assert_output --partial "does not exist"
}

@test "create_backup creates backup directory if missing" {
    export ST_BACKUP_DIR="${TEST_TMPDIR}/new_backups"
    echo "test" > "${TEST_TMPDIR}/testfile.txt"

    # Don't use 'run' - mkdir needs to happen in current shell
    create_backup "${TEST_TMPDIR}/testfile.txt" "test"
    assert_dir_exists "${ST_BACKUP_DIR}"
}

@test "backup_before_delete skips when disabled" {
    ST_AUTO_BACKUP=false
    run backup_before_delete "${TEST_TMPDIR}/something" "test"
    assert_success
}

@test "backup_before_delete skips when target missing" {
    run backup_before_delete "${TEST_TMPDIR}/nonexistent" "test"
    assert_success
}

@test "backup_before_delete creates backup for existing target" {
    echo "important data" > "${TEST_TMPDIR}/important.txt"

    run backup_before_delete "${TEST_TMPDIR}/important.txt" "important"
    assert_success
    assert_output --partial "Backup created"
}

@test "list_backups shows no backups message when empty" {
    rm -rf "${ST_BACKUP_DIR}"/*

    run list_backups
    assert_success
    assert_output --partial "No backups found"
}

@test "list_backups shows existing backups" {
    touch "${ST_BACKUP_DIR}/test_20250101_120000.tar.gz"

    run list_backups
    assert_success
    assert_output --partial "test_20250101_120000.tar.gz"
}

@test "cleanup_old_backups removes old files" {
    # Create an old backup file (set modification time to 60 days ago)
    local old_backup="${ST_BACKUP_DIR}/old_backup_20240101.tar.gz"
    touch -d "60 days ago" "$old_backup"

    # Create a recent backup
    local new_backup="${ST_BACKUP_DIR}/new_backup_20250218.tar.gz"
    touch "$new_backup"

    run cleanup_old_backups
    assert_success

    # Old backup should be removed, new should remain
    assert_file_not_exists "$old_backup"
    assert_file_exists "$new_backup"
}
