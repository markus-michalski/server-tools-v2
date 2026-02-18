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
    source_lib "vhost"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# --- Pure functions (no mocking needed) ---

@test "generate_vhost_config includes ServerName" {
    run generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "ServerName example.com"
}

@test "generate_vhost_config includes PHP-FPM socket" {
    run generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "php8.3-fpm.sock"
}

@test "generate_vhost_config includes ServerAlias when provided" {
    run generate_vhost_config "example.com" "www.example.com" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "ServerAlias www.example.com"
}

@test "generate_vhost_config omits ServerAlias when empty" {
    run generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    refute_output --partial "ServerAlias"
}

@test "generate_vhost_config includes security headers" {
    run generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "X-Content-Type-Options"
    assert_output --partial "X-Frame-Options"
    assert_output --partial "Referrer-Policy"
    assert_output --partial "Permissions-Policy"
}

@test "generate_vhost_config includes DocumentRoot" {
    run generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "DocumentRoot /var/www/example.com/html"
}

@test "generate_vhost_config includes logging paths" {
    run generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "ErrorLog /var/www/example.com/logs/error.log"
    assert_output --partial "CustomLog /var/www/example.com/logs/access.log"
}

@test "generate_vhost_config disables directory listing" {
    run generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "-Indexes"
}

@test "generate_vhost_config uses configurable ServerAdmin" {
    ST_APACHE_SERVER_ADMIN="admin@myserver.com"
    run generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "ServerAdmin admin@myserver.com"
}

# --- Welcome page ---

@test "generate_welcome_page produces valid PHP" {
    run generate_welcome_page "example.com"
    assert_success
    assert_output --partial "<?php"
    assert_output --partial "phpversion()"
    assert_output --partial "htmlspecialchars"
}

@test "generate_welcome_page includes HTML structure" {
    run generate_welcome_page "example.com"
    assert_success
    assert_output --partial "<!DOCTYPE html>"
    assert_output --partial "</html>"
}

# --- Input validation ---

@test "create_vhost rejects invalid domain" {
    run create_vhost "bad domain name"
    assert_failure
    assert_output --partial "Invalid domain"
}

@test "create_vhost rejects invalid PHP version" {
    run create_vhost "example.com" "" "5.6"
    assert_failure
    assert_output --partial "Invalid PHP version"
}

@test "delete_vhost rejects invalid domain" {
    run delete_vhost "bad;domain"
    assert_failure
}

@test "change_php_version rejects invalid domain" {
    run change_php_version "bad;domain" "8.3"
    assert_failure
}

@test "change_php_version rejects invalid PHP version" {
    run change_php_version "example.com" "5.6"
    assert_failure
    assert_output --partial "Invalid PHP version"
}

@test "show_vhost_info rejects invalid domain" {
    run show_vhost_info "bad;domain"
    assert_failure
}
