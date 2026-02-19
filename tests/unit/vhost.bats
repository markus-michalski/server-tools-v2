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

# --- Redirect pure functions ---

@test "generate_redirect_config includes ServerName" {
    run generate_redirect_config "old.com" "https://new.com/" 301
    assert_success
    assert_output --partial "ServerName old.com"
}

@test "generate_redirect_config includes redirect directive" {
    run generate_redirect_config "old.com" "https://new.com/" 301
    assert_success
    assert_output --partial "Redirect 301 / https://new.com/"
}

@test "generate_redirect_config supports 302 redirect" {
    run generate_redirect_config "old.com" "https://new.com/" 302
    assert_success
    assert_output --partial "Redirect 302"
}

@test "generate_redirect_config includes VirtualHost block" {
    run generate_redirect_config "old.com" "https://new.com/" 301
    assert_success
    assert_output --partial "<VirtualHost *:80>"
    assert_output --partial "</VirtualHost>"
}

@test "generate_www_redirect_snippet generates to_www rules" {
    run generate_www_redirect_snippet "example.com" "to_www"
    assert_success
    assert_output --partial "RewriteEngine On"
    assert_output --partial "www.example.com"
    assert_output --partial "R=301"
}

@test "generate_www_redirect_snippet generates from_www rules" {
    run generate_www_redirect_snippet "example.com" "from_www"
    assert_success
    assert_output --partial "RewriteEngine On"
    assert_output --partial "example.com"
    assert_output --partial "R=301"
}

@test "generate_https_redirect_snippet generates HTTPS rewrite" {
    run generate_https_redirect_snippet "example.com"
    assert_success
    assert_output --partial "RewriteEngine On"
    assert_output --partial "HTTPS"
    assert_output --partial "R=301"
}

# --- Redirect high-level validation ---

@test "create_redirect rejects invalid domain" {
    run create_redirect "bad;domain" "https://example.com/" 301
    assert_failure
}

@test "create_redirect rejects invalid URL" {
    run create_redirect "example.com" "not-a-url" 301
    assert_failure
    assert_output --partial "Invalid URL"
}

@test "create_redirect rejects invalid redirect code" {
    run create_redirect "example.com" "https://new.com/" 200
    assert_failure
    assert_output --partial "Invalid redirect code"
}

@test "add_www_redirect rejects invalid domain" {
    run add_www_redirect "bad;domain"
    assert_failure
}

@test "force_https rejects invalid domain" {
    run force_https "bad;domain"
    assert_failure
}

# =============================================================================
# LOGROTATE
# =============================================================================

@test "generate_logrotate_config contains domain log path" {
    run generate_logrotate_config "example.com"
    assert_success
    assert_output --partial "/var/www/example.com/logs/*.log"
}

@test "generate_logrotate_config contains weekly rotation" {
    run generate_logrotate_config "example.com"
    assert_success
    assert_output --partial "weekly"
}

@test "generate_logrotate_config contains compress directives" {
    run generate_logrotate_config "example.com"
    assert_success
    assert_output --partial "compress"
    assert_output --partial "delaycompress"
}

@test "generate_logrotate_config contains postrotate with apache reload" {
    run generate_logrotate_config "example.com"
    assert_success
    assert_output --partial "postrotate"
    assert_output --partial "systemctl reload apache2"
}

@test "generate_logrotate_config uses ST_LOGROTATE_ROTATE value" {
    export ST_LOGROTATE_ROTATE=10
    run generate_logrotate_config "example.com"
    assert_success
    assert_output --partial "rotate 10"
}

@test "generate_logrotate_config uses ST_LOGROTATE_DAYS for maxage" {
    export ST_LOGROTATE_DAYS=30
    run generate_logrotate_config "example.com"
    assert_success
    assert_output --partial "maxage 30"
}

@test "generate_logrotate_config sets correct file permissions" {
    run generate_logrotate_config "example.com"
    assert_success
    assert_output --partial "create 640 www-data www-data"
}
