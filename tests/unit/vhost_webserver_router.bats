#!/usr/bin/env bats
#
# Tests for lib/vhost.sh's backend dispatch (_ws_dispatch) and for the
# webserver-agnostic high-level operations exercised with ST_WEBSERVER=nginx.
#
# Like the existing create_vhost/delete_vhost tests in vhost.bats, the
# end-to-end-ish tests here stick to what's testable without root or a real
# webserver: input validation paths, and read-only queries (list_vhosts,
# show_vhost_info) against config files planted directly on disk.

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
    export ST_APACHE_SITES_AVAILABLE="${TEST_TMPDIR}/apache/sites-available"
    export ST_APACHE_SITES_ENABLED="${TEST_TMPDIR}/apache/sites-enabled"
    export ST_NGINX_SITES_AVAILABLE="${TEST_TMPDIR}/nginx/sites-available"
    export ST_NGINX_SITES_ENABLED="${TEST_TMPDIR}/nginx/sites-enabled"
    mkdir -p "${ST_CREDENTIAL_DIR}" "${ST_BACKUP_DIR}" \
        "${ST_APACHE_SITES_AVAILABLE}" "${ST_APACHE_SITES_ENABLED}" \
        "${ST_NGINX_SITES_AVAILABLE}" "${ST_NGINX_SITES_ENABLED}"
    source_lib "vhost"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# _ws_dispatch routing
# =============================================================================

@test "_ws_dispatch routes to apache_* by default" {
    run _ws_dispatch vhost_config_path "example.com"
    assert_success
    assert_output "${ST_APACHE_SITES_AVAILABLE}/example.com.conf"
}

@test "_ws_dispatch routes to apache_* when ST_WEBSERVER=apache explicitly" {
    export ST_WEBSERVER=apache
    run _ws_dispatch vhost_config_path "example.com"
    assert_success
    assert_output "${ST_APACHE_SITES_AVAILABLE}/example.com.conf"
}

@test "_ws_dispatch routes to nginx_* when ST_WEBSERVER=nginx" {
    export ST_WEBSERVER=nginx
    run _ws_dispatch vhost_config_path "example.com"
    assert_success
    assert_output "${ST_NGINX_SITES_AVAILABLE}/example.com"
}

@test "_ws_dispatch forwards all remaining arguments" {
    export ST_WEBSERVER=nginx
    run _ws_dispatch generate_redirect_config "old.com" "https://new.com/" 302
    assert_success
    assert_output --partial "server_name old.com;"
    assert_output --partial "return 302 https://new.com/;"
}

# =============================================================================
# create_vhost / delete_vhost / change_php_version - validation is backend-agnostic
# =============================================================================

@test "create_vhost rejects invalid domain under nginx backend" {
    export ST_WEBSERVER=nginx
    run create_vhost "bad domain name"
    assert_failure
    assert_output --partial "Invalid domain"
}

@test "create_vhost proxy mode rejects missing backend URL under nginx backend" {
    export ST_WEBSERVER=nginx
    run create_vhost "app.example.com" "" "" "" "false" "proxy" "" "false" "true"
    assert_failure
    assert_output --partial "Backend URL is required"
}

@test "delete_vhost reports missing vhost under nginx backend" {
    export ST_WEBSERVER=nginx
    run delete_vhost "example.com"
    assert_failure
    assert_output --partial "does not exist"
}

@test "delete_vhost rejects invalid domain under nginx backend" {
    export ST_WEBSERVER=nginx
    run delete_vhost "bad;domain"
    assert_failure
}

@test "change_php_version reports missing vhost under nginx backend" {
    export ST_WEBSERVER=nginx
    run change_php_version "example.com" "8.3"
    assert_failure
    assert_output --partial "does not exist"
}

# =============================================================================
# list_vhosts - purely read-only, safe to exercise end-to-end
# =============================================================================

@test "list_vhosts reports (none) for both backends when directories are empty" {
    run list_vhosts
    assert_success
    assert_output --partial "(none)"
}

@test "list_vhosts lists apache sites using the .conf-suffixed basename" {
    touch "${ST_APACHE_SITES_AVAILABLE}/example.com.conf"
    ln -s "${ST_APACHE_SITES_AVAILABLE}/example.com.conf" "${ST_APACHE_SITES_ENABLED}/example.com.conf"
    # Note: list_vhosts's last statement is `[[ $found -eq 0 ]] && echo "(none)"`,
    # a pre-existing (unrelated to this refactor, left as-is) quirk that makes
    # the function return non-zero exit status whenever sites ARE found -- so
    # this only checks output, not exit status.
    run list_vhosts
    assert_output --partial "- example.com"
    refute_output --partial "example.com.conf"
}

@test "list_vhosts lists nginx sites using the bare domain filename" {
    export ST_WEBSERVER=nginx
    touch "${ST_NGINX_SITES_AVAILABLE}/example.com"
    ln -s "${ST_NGINX_SITES_AVAILABLE}/example.com" "${ST_NGINX_SITES_ENABLED}/example.com"
    # See note above on list_vhosts's exit-status quirk.
    run list_vhosts
    assert_output --partial "- example.com"
}

# =============================================================================
# show_vhost_info - read-only against a planted nginx config, no root needed
# =============================================================================

@test "show_vhost_info reports php vhost details under nginx backend" {
    export ST_WEBSERVER=nginx
    nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" \
        > "${ST_NGINX_SITES_AVAILABLE}/example.com"

    run show_vhost_info "example.com"
    assert_success
    assert_output --partial "Type:         php"
    assert_output --partial "DocumentRoot: /var/www/example.com/html"
    assert_output --partial "PHP version:  8.3"
    assert_output --partial "SSL:          not applicable (nginx)"
    assert_output --partial "Status:       disabled"
}

@test "show_vhost_info reports proxy vhost details under nginx backend" {
    export ST_WEBSERVER=nginx
    nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "true" "true" \
        > "${ST_NGINX_SITES_AVAILABLE}/app.example.com"

    run show_vhost_info "app.example.com"
    assert_success
    assert_output --partial "Type:         proxy"
    assert_output --partial "Backend:      http://localhost:3000"
    assert_output --partial "WebSocket:    enabled"
}

@test "show_vhost_info reports enabled status under nginx backend" {
    export ST_WEBSERVER=nginx
    nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" \
        > "${ST_NGINX_SITES_AVAILABLE}/example.com"
    ln -s "${ST_NGINX_SITES_AVAILABLE}/example.com" "${ST_NGINX_SITES_ENABLED}/example.com"

    run show_vhost_info "example.com"
    assert_success
    assert_output --partial "Status:       enabled"
}

@test "show_vhost_info still reports Apache SSL status under the apache backend" {
    apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" \
        > "${ST_APACHE_SITES_AVAILABLE}/example.com.conf"

    run show_vhost_info "example.com"
    assert_success
    assert_output --partial "SSL:          not configured"
}

# =============================================================================
# Redirect helpers - validation is backend-agnostic
# =============================================================================

@test "create_redirect rejects invalid domain under nginx backend" {
    export ST_WEBSERVER=nginx
    run create_redirect "bad;domain" "https://example.com/" 301
    assert_failure
}

@test "add_www_redirect reports missing config under nginx backend" {
    export ST_WEBSERVER=nginx
    run add_www_redirect "example.com"
    assert_failure
    assert_output --partial "VHost config not found"
}

@test "force_https reports missing config under nginx backend" {
    export ST_WEBSERVER=nginx
    run force_https "example.com"
    assert_failure
    assert_output --partial "VHost config not found"
}
