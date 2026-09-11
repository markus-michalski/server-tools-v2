#!/usr/bin/env bats
#
# Tests for lib/webserver/nginx.sh: Nginx config generation (pure functions)
# and site management mechanics (ln/rm/nginx -t/systemctl).

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
    export ST_ALLOWED_DOCROOT_PATHS="/var/www:/srv/www"
    export ST_CREDENTIAL_FILE_PERMISSIONS=600
    export ST_NGINX_SITES_AVAILABLE="${TEST_TMPDIR}/sites-available"
    export ST_NGINX_SITES_ENABLED="${TEST_TMPDIR}/sites-enabled"
    mkdir -p "${ST_CREDENTIAL_DIR}" "${ST_BACKUP_DIR}" "${ST_NGINX_SITES_AVAILABLE}" "${ST_NGINX_SITES_ENABLED}"
    source_lib "webserver/nginx"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# PHP-FPM VHOST - pure function
# =============================================================================

@test "nginx_generate_vhost_config includes server_name" {
    run nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "server_name example.com;"
}

@test "nginx_generate_vhost_config includes aliases on the same server_name line" {
    run nginx_generate_vhost_config "example.com" "www.example.com alt.example.com" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "server_name example.com www.example.com alt.example.com;"
}

@test "nginx_generate_vhost_config includes root/docroot" {
    run nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "root /var/www/example.com/html;"
}

@test "nginx_generate_vhost_config includes PHP-FPM socket path" {
    run nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "fastcgi_pass unix:/run/php/php8.3-fpm.sock;"
}

@test "nginx_generate_vhost_config does not depend on an external fastcgi-php.conf snippet" {
    run nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    refute_output --partial "snippets/fastcgi-php.conf"
    assert_output --partial "fastcgi_param SCRIPT_FILENAME"
}

@test "nginx_generate_vhost_config guards the PHP location against path-info execution (CVE-2019-11043-class)" {
    # Without "try_files \$uri =404;" before fastcgi_pass, a request like
    # /uploads/avatar.jpg/x.php matches "location ~ \.php\$" and, with PHP's
    # default cgi.fix_pathinfo=1, executes the uploaded avatar.jpg as PHP --
    # the canonical nginx+PHP-FPM path-info RCE. Apache's <FilesMatch> doesn't
    # have this failure mode (it matches the resolved basename), so this is
    # nginx-specific, not parity with the Apache template.
    run nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial 'try_files $uri =404;'
}

@test "nginx_generate_vhost_config denies dotfile access" {
    run nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial 'location ~ /\.ht {'
    assert_output --partial "deny all;"
}

@test "nginx_generate_vhost_config includes security headers" {
    run nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial 'add_header X-Content-Type-Options "nosniff" always;'
    assert_output --partial 'add_header X-Frame-Options "SAMEORIGIN" always;'
    assert_output --partial 'add_header Referrer-Policy "strict-origin-when-cross-origin" always;'
    assert_output --partial 'add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;'
}

@test "nginx_generate_vhost_config includes logging paths matching Apache's canonical layout" {
    run nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "access_log /var/www/example.com/logs/access.log;"
    assert_output --partial "error_log /var/www/example.com/logs/error.log;"
}

@test "nginx_generate_vhost_config ends with a lone closing brace as the last line" {
    local last_line
    last_line=$(nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" | tail -n1)
    [[ "$last_line" == "}" ]]
}

# =============================================================================
# REVERSE PROXY - pure function
# =============================================================================

@test "nginx_generate_proxy_config includes server_name" {
    run nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial "server_name app.example.com;"
}

@test "nginx_generate_proxy_config includes proxy_pass verbatim (no trailing slash added or stripped)" {
    run nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial "proxy_pass http://localhost:3000;"
}

@test "nginx_generate_proxy_config includes forwarded-proto/port headers inline (no separate snippet)" {
    run nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial 'proxy_set_header X-Forwarded-Proto $scheme;'
    assert_output --partial 'proxy_set_header X-Forwarded-Port $server_port;'
}

@test "nginx_generate_proxy_config sets Host header when preserve_host is true" {
    run nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial 'proxy_set_header Host $host;'
}

@test "nginx_generate_proxy_config omits explicit Host header when preserve_host is false" {
    run nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "false"
    assert_success
    refute_output --partial 'proxy_set_header Host $host;'
}

@test "nginx_generate_proxy_config defaults preserve_host to ST_PROXY_PRESERVE_HOST" {
    export ST_PROXY_PRESERVE_HOST=false
    run nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false"
    assert_success
    refute_output --partial 'proxy_set_header Host $host;'
}

@test "nginx_generate_proxy_config includes WebSocket upgrade headers when enabled" {
    run nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "true" "true"
    assert_success
    assert_output --partial 'proxy_set_header Upgrade $http_upgrade;'
    assert_output --partial 'proxy_set_header Connection "upgrade";'
}

@test "nginx_generate_proxy_config omits WebSocket upgrade headers when disabled" {
    run nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    refute_output --partial "http_upgrade"
    refute_output --partial "Connection \"upgrade\""
}

@test "nginx_generate_proxy_config websocket needs no rewrite rule or backreference" {
    run nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "true" "true"
    assert_success
    refute_output --partial "rewrite"
    refute_output --partial '$1'
}

@test "nginx_generate_proxy_config includes security headers" {
    run nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial 'add_header X-Content-Type-Options "nosniff" always;'
    assert_output --partial 'add_header X-Frame-Options "SAMEORIGIN" always;'
    assert_output --partial 'add_header Referrer-Policy "strict-origin-when-cross-origin" always;'
    assert_output --partial 'add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;'
}

@test "nginx_generate_proxy_config includes logging paths matching Apache's canonical layout" {
    run nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial "access_log /var/www/app.example.com/logs/access.log;"
    assert_output --partial "error_log /var/www/app.example.com/logs/error.log;"
}

@test "nginx_generate_proxy_config does not include root/PHP-FPM directives" {
    run nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    refute_output --partial "root "
    refute_output --partial "fastcgi_pass"
}

@test "nginx_generate_proxy_config ends with a lone closing brace as the last line" {
    local last_line
    last_line=$(nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "true" "true" | tail -n1)
    [[ "$last_line" == "}" ]]
}

# =============================================================================
# REDIRECT - pure functions
# =============================================================================

@test "nginx_generate_redirect_config includes server_name" {
    run nginx_generate_redirect_config "old.com" "https://new.com/" 301
    assert_success
    assert_output --partial "server_name old.com;"
}

@test "nginx_generate_redirect_config supports 301" {
    run nginx_generate_redirect_config "old.com" "https://new.com/" 301
    assert_success
    assert_output --partial "return 301 https://new.com/;"
}

@test "nginx_generate_redirect_config supports 302" {
    run nginx_generate_redirect_config "old.com" "https://new.com/" 302
    assert_success
    assert_output --partial "return 302 https://new.com/;"
}

@test "nginx_generate_redirect_config does not append \$request_uri (matches Apache's bare redirect)" {
    run nginx_generate_redirect_config "old.com" "https://new.com/" 301
    assert_success
    refute_output --partial 'request_uri'
}

@test "nginx_generate_www_redirect_snippet generates to_www rule" {
    run nginx_generate_www_redirect_snippet "example.com" "to_www"
    assert_success
    assert_output --partial 'if ($host = example.com)'
    assert_output --partial "return 301 http://www.example.com\$request_uri;"
}

@test "nginx_generate_www_redirect_snippet generates from_www rule" {
    run nginx_generate_www_redirect_snippet "example.com" "from_www"
    assert_success
    assert_output --partial 'if ($host = www.example.com)'
    assert_output --partial "return 301 http://example.com\$request_uri;"
}

@test "nginx_generate_https_redirect_snippet generates scheme-based redirect" {
    run nginx_generate_https_redirect_snippet "example.com"
    assert_success
    assert_output --partial 'if ($scheme = http)'
    assert_output --partial 'return 301 https://$host$request_uri;'
}

# =============================================================================
# PATHS & QUERIES
# =============================================================================

@test "nginx_vhost_config_path uses the bare domain, no .conf suffix" {
    run nginx_vhost_config_path "example.com"
    assert_success
    assert_output "${ST_NGINX_SITES_AVAILABLE}/example.com"
}

@test "nginx_vhost_exists is false when no config file present" {
    run nginx_vhost_exists "example.com"
    assert_failure
}

@test "nginx_vhost_exists is true when config file present" {
    touch "${ST_NGINX_SITES_AVAILABLE}/example.com"
    run nginx_vhost_exists "example.com"
    assert_success
}

@test "nginx_get_vhost_docroot / nginx_get_vhost_php_version round-trip against generator output" {
    nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" \
        > "${ST_NGINX_SITES_AVAILABLE}/example.com"

    run nginx_get_vhost_docroot "example.com"
    assert_success
    assert_output "/var/www/example.com/html"

    run nginx_get_vhost_php_version "example.com"
    assert_success
    assert_output "8.3"
}

@test "nginx_get_vhost_type detects php vhosts" {
    nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" \
        > "${ST_NGINX_SITES_AVAILABLE}/example.com"

    run nginx_get_vhost_type "example.com"
    assert_success
    assert_output "php"
}

@test "nginx_get_vhost_type detects proxy vhosts" {
    nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true" \
        > "${ST_NGINX_SITES_AVAILABLE}/app.example.com"

    run nginx_get_vhost_type "app.example.com"
    assert_success
    assert_output "proxy"
}

@test "nginx_get_vhost_backend extracts backend URL from proxy config" {
    nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true" \
        > "${ST_NGINX_SITES_AVAILABLE}/app.example.com"

    run nginx_get_vhost_backend "app.example.com"
    assert_success
    assert_output "http://localhost:3000"
}

@test "nginx_vhost_enabled is false without a sites-enabled symlink" {
    run nginx_vhost_enabled "example.com"
    assert_failure
}

@test "nginx_vhost_enabled is true with a sites-enabled symlink" {
    touch "${ST_NGINX_SITES_AVAILABLE}/example.com"
    ln -s "${ST_NGINX_SITES_AVAILABLE}/example.com" "${ST_NGINX_SITES_ENABLED}/example.com"
    run nginx_vhost_enabled "example.com"
    assert_success
}

@test "nginx_websocket_enabled detects the Upgrade/http_upgrade marker" {
    nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "true" "true" \
        > "${ST_NGINX_SITES_AVAILABLE}/app.example.com"

    run nginx_websocket_enabled "app.example.com"
    assert_success
}

@test "nginx_websocket_enabled is false without the websocket marker" {
    nginx_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true" \
        > "${ST_NGINX_SITES_AVAILABLE}/app.example.com"

    run nginx_websocket_enabled "app.example.com"
    assert_failure
}

@test "nginx_change_php_version_in_config replaces the FPM socket version" {
    nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" \
        > "${ST_NGINX_SITES_AVAILABLE}/example.com"

    nginx_change_php_version_in_config "${ST_NGINX_SITES_AVAILABLE}/example.com" "8.4"

    run nginx_get_vhost_php_version "example.com"
    assert_success
    assert_output "8.4"
}

# =============================================================================
# SITE ENABLE/DISABLE/RELOAD MECHANICS
# =============================================================================

@test "nginx_enable_site symlinks sites-available into sites-enabled" {
    touch "${ST_NGINX_SITES_AVAILABLE}/example.com"
    run nginx_enable_site "example.com"
    assert_success
    [[ -L "${ST_NGINX_SITES_ENABLED}/example.com" ]]
}

@test "nginx_enable_site fails and logs when the symlink cannot be created" {
    # Point at a nonexistent target directory so ln fails regardless of
    # whether the test happens to run as root (permission bits alone
    # wouldn't reliably force a failure for root).
    export ST_NGINX_SITES_ENABLED="${TEST_TMPDIR}/no-such-dir/sites-enabled"
    touch "${ST_NGINX_SITES_AVAILABLE}/example.com"
    run nginx_enable_site "example.com"
    assert_failure
    assert_output --partial "Failed to enable site"
}

@test "nginx_disable_site removes the sites-enabled symlink" {
    touch "${ST_NGINX_SITES_AVAILABLE}/example.com"
    ln -s "${ST_NGINX_SITES_AVAILABLE}/example.com" "${ST_NGINX_SITES_ENABLED}/example.com"
    nginx_disable_site "example.com"
    [[ ! -e "${ST_NGINX_SITES_ENABLED}/example.com" ]]
}

@test "nginx_config_test fails when nginx -t fails" {
    mock_command "nginx" 'exit 1'
    run nginx_config_test
    assert_failure
    assert_output --partial "configuration test failed"
}

@test "nginx_config_test succeeds when nginx -t succeeds" {
    mock_command "nginx" 'exit 0'
    run nginx_config_test
    assert_success
}

@test "nginx_reload fails without reloading when config test fails" {
    mock_command "nginx" 'exit 1'
    mock_command "systemctl" 'echo "should not run"; exit 1'
    run nginx_reload
    assert_failure
    refute_output --partial "should not run"
}

@test "nginx_reload reloads nginx when config test passes" {
    mock_command "nginx" 'exit 0'
    mock_command "systemctl" 'exit 0'
    run nginx_reload
    assert_success
    assert_output --partial "reloaded successfully"
}

# =============================================================================
# NO-OP MODULE STUBS
# =============================================================================

@test "nginx_enable_modules_php is a no-op that succeeds" {
    run nginx_enable_modules_php
    assert_success
    assert_output ""
}

@test "nginx_enable_modules_proxy is a no-op that succeeds" {
    run nginx_enable_modules_proxy "true"
    assert_success
    assert_output ""
}

@test "nginx_rewrite_module_ensure is a no-op that succeeds" {
    run nginx_rewrite_module_ensure
    assert_success
    assert_output ""
}

# =============================================================================
# INSERT-BEFORE-CLOSE
# =============================================================================

@test "nginx_insert_before_server_close inserts a multi-line snippet before the lone closing brace" {
    local config="${TEST_TMPDIR}/site.conf"
    nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" > "$config"

    local snippet
    snippet=$(nginx_generate_https_redirect_snippet "example.com")
    nginx_insert_before_server_close "$config" "$snippet"

    run tail -n1 "$config"
    assert_success
    assert_output "}"

    run grep -c "if (\$scheme = http)" "$config"
    assert_output "1"
    run grep -c "return 301 https://\$host\$request_uri;" "$config"
    assert_output "1"
}

@test "nginx_insert_before_server_close preserves every original line of the config" {
    local config="${TEST_TMPDIR}/site.conf"
    nginx_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" > "$config"
    local before_lines
    before_lines=$(wc -l < "$config")

    local snippet="    # marker line one
    # marker line two"
    nginx_insert_before_server_close "$config" "$snippet"

    local after_lines
    after_lines=$(wc -l < "$config")
    [[ "$after_lines" -eq $((before_lines + 2)) ]]
}
