#!/usr/bin/env bats
#
# Tests for the webserver-agnostic orchestration layer in lib/vhost.sh:
# input validation, welcome page, logrotate, and high-level operation
# routing. Webserver-specific config generation/queries/mechanics are tested
# in tests/unit/webserver_apache.bats and tests/unit/webserver_nginx.bats;
# backend dispatch (_ws_dispatch) is tested in
# tests/unit/vhost_webserver_router.bats.

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

@test "audit_vhost rejects invalid domain" {
    run audit_vhost "bad;domain"
    assert_failure
}

@test "audit_vhost fails when the vhost does not exist" {
    export ST_APACHE_SITES_AVAILABLE="${TEST_TMPDIR}/sites-available"
    mkdir -p "$ST_APACHE_SITES_AVAILABLE"
    run audit_vhost "example.com"
    assert_failure
}

@test "audit_vhost skips cleanly on nginx (template audit not yet implemented)" {
    export ST_WEBSERVER="nginx"
    export ST_NGINX_SITES_AVAILABLE="${TEST_TMPDIR}/nginx-sites-available"
    mkdir -p "$ST_NGINX_SITES_AVAILABLE"
    touch "${ST_NGINX_SITES_AVAILABLE}/example.com"
    run audit_vhost "example.com"
    assert_success
    assert_output --partial "[SKIP]"
    assert_output --partial "nginx"
}

@test "audit_all_vhosts skips cleanly on nginx (template audit not yet implemented)" {
    export ST_WEBSERVER="nginx"
    run audit_all_vhosts
    assert_success
    assert_output --partial "not yet implemented for nginx"
}

@test "audit_all_vhosts reports no vhosts found when sites-available is empty" {
    export ST_APACHE_SITES_AVAILABLE="${TEST_TMPDIR}/sites-available"
    mkdir -p "$ST_APACHE_SITES_AVAILABLE"
    run audit_all_vhosts
    assert_success
    assert_output --partial "(no vhosts found)"
}

@test "audit_all_vhosts skips Apache's own stock configs" {
    export ST_APACHE_SITES_AVAILABLE="${TEST_TMPDIR}/sites-available"
    mkdir -p "$ST_APACHE_SITES_AVAILABLE"
    printf '<VirtualHost *:80>\n</VirtualHost>\n' > "${ST_APACHE_SITES_AVAILABLE}/000-default.conf"
    printf '<VirtualHost *:443>\n</VirtualHost>\n' > "${ST_APACHE_SITES_AVAILABLE}/default-ssl.conf"
    run audit_all_vhosts
    assert_success
    assert_output --partial "(no vhosts found)"
    refute_output --partial "Vhost: 000-default"
    refute_output --partial "Vhost: default-ssl"
}

@test "audit_all_vhosts audits a real deployed vhost and reports drift" {
    export ST_APACHE_SITES_AVAILABLE="${TEST_TMPDIR}/sites-available"
    mkdir -p "$ST_APACHE_SITES_AVAILABLE"
    printf '<VirtualHost *:80>\n    ServerName example.com\n    ProxyPass / http://localhost:3000/\n</VirtualHost>\n' \
        > "${ST_APACHE_SITES_AVAILABLE}/example.com.conf"
    run audit_all_vhosts
    assert_failure
    assert_output --partial "Vhost: example.com"
    assert_output --partial "[DRIFT]"
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

@test "generate_logrotate_config bakes in the nginx reload command when ST_WEBSERVER=nginx" {
    # postrotate runs later, asynchronously via cron/logrotate -- $ST_WEBSERVER
    # (a live bash variable in this process) won't exist then, so the
    # backend-correct command must be baked in as static text at generation
    # time, not looked up dynamically when logrotate actually runs.
    export ST_WEBSERVER=nginx
    run generate_logrotate_config "example.com"
    assert_success
    assert_output --partial "systemctl reload nginx"
    assert_output --partial "/var/run/nginx.pid"
    refute_output --partial "apache2"
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

# =============================================================================
# REVERSE PROXY - high-level validation
# =============================================================================

@test "create_vhost proxy mode rejects missing backend URL" {
    run create_vhost "app.example.com" "" "" "" "false" "proxy" "" "false" "true"
    assert_failure
    assert_output --partial "Backend URL is required"
}

@test "create_vhost proxy mode rejects invalid backend URL" {
    run create_vhost "app.example.com" "" "" "" "false" "proxy" "not-a-url" "false" "true"
    assert_failure
    assert_output --partial "Invalid URL"
}

@test "create_vhost proxy mode rejects invalid domain" {
    run create_vhost "bad domain" "" "" "" "false" "proxy" "http://localhost:3000" "false" "true"
    assert_failure
    assert_output --partial "Invalid domain"
}
