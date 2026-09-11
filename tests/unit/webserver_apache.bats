#!/usr/bin/env bats
#
# Tests for lib/webserver/apache.sh: Apache config generation (pure
# functions) and site management mechanics (a2ensite/a2dissite/apache2ctl).

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
    export ST_APACHE_SERVER_ADMIN="webmaster@localhost"
    export ST_APACHE_SITES_AVAILABLE="${TEST_TMPDIR}/sites-available"
    export ST_APACHE_SITES_ENABLED="${TEST_TMPDIR}/sites-enabled"
    mkdir -p "${ST_CREDENTIAL_DIR}" "${ST_BACKUP_DIR}" "${ST_APACHE_SITES_AVAILABLE}" "${ST_APACHE_SITES_ENABLED}"
    source_lib "webserver/apache"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# --- Pure functions (no mocking needed) ---

@test "apache_forwarded_headers_snippet uses ap_expr for scheme and port" {
    run apache_forwarded_headers_snippet
    assert_success
    assert_output --partial 'RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}'
    assert_output --partial 'RequestHeader set X-Forwarded-Port expr=%{SERVER_PORT}'
}

@test "apache_generate_vhost_config includes ServerName" {
    run apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "ServerName example.com"
}

@test "apache_generate_vhost_config includes PHP-FPM socket" {
    run apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "php8.3-fpm.sock"
}

@test "apache_generate_vhost_config includes ServerAlias when provided" {
    run apache_generate_vhost_config "example.com" "www.example.com" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "ServerAlias www.example.com"
}

@test "apache_generate_vhost_config omits ServerAlias when empty" {
    run apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    refute_output --partial "ServerAlias"
}

@test "apache_generate_vhost_config includes security headers" {
    run apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "X-Content-Type-Options"
    assert_output --partial "X-Frame-Options"
    assert_output --partial "Referrer-Policy"
    assert_output --partial "Permissions-Policy"
}

@test "apache_generate_vhost_config includes forwarded headers" {
    run apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial 'RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}'
    assert_output --partial 'RequestHeader set X-Forwarded-Port expr=%{SERVER_PORT}'
}

@test "apache_generate_vhost_config includes DocumentRoot" {
    run apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "DocumentRoot /var/www/example.com/html"
}

@test "apache_generate_vhost_config includes logging paths" {
    run apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "ErrorLog /var/www/example.com/logs/error.log"
    assert_output --partial "CustomLog /var/www/example.com/logs/access.log"
}

@test "apache_generate_vhost_config disables directory listing" {
    run apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "-Indexes"
}

@test "apache_generate_vhost_config uses configurable ServerAdmin" {
    ST_APACHE_SERVER_ADMIN="admin@myserver.com"
    run apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html"
    assert_success
    assert_output --partial "ServerAdmin admin@myserver.com"
}

# =============================================================================
# REVERSE PROXY - pure functions
# =============================================================================

@test "apache_generate_proxy_config includes ServerName" {
    export ST_PROXY_PRESERVE_HOST=true
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial "ServerName app.example.com"
}

@test "apache_generate_proxy_config includes ProxyPass directives" {
    export ST_PROXY_PRESERVE_HOST=true
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial "ProxyPass / http://localhost:3000/"
    assert_output --partial "ProxyPassReverse / http://localhost:3000/"
}

@test "apache_generate_proxy_config includes ProxyPreserveHost On" {
    export ST_PROXY_PRESERVE_HOST=true
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial "ProxyPreserveHost On"
}

@test "apache_generate_proxy_config supports ProxyPreserveHost Off" {
    export ST_PROXY_PRESERVE_HOST=false
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "false"
    assert_success
    assert_output --partial "ProxyPreserveHost Off"
}

@test "apache_generate_proxy_config includes ServerAlias when provided" {
    export ST_PROXY_PRESERVE_HOST=true
    run apache_generate_proxy_config "app.example.com" "www.app.example.com" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial "ServerAlias www.app.example.com"
}

@test "apache_generate_proxy_config omits ServerAlias when empty" {
    export ST_PROXY_PRESERVE_HOST=true
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    refute_output --partial "ServerAlias"
}

@test "apache_generate_proxy_config includes security headers" {
    export ST_PROXY_PRESERVE_HOST=true
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial "X-Content-Type-Options"
    assert_output --partial "X-Frame-Options"
    assert_output --partial "Referrer-Policy"
    assert_output --partial "Permissions-Policy"
}

@test "apache_generate_proxy_config includes forwarded headers" {
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial 'RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}'
    assert_output --partial 'RequestHeader set X-Forwarded-Port expr=%{SERVER_PORT}'
}

@test "apache_generate_proxy_config includes forwarded headers when WebSocket is enabled" {
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "true" "true"
    assert_success
    assert_output --partial 'RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}'
    assert_output --partial 'RequestHeader set X-Forwarded-Port expr=%{SERVER_PORT}'
}

@test "apache_generate_proxy_config includes logging paths" {
    export ST_PROXY_PRESERVE_HOST=true
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial "ErrorLog /var/www/app.example.com/logs/error.log"
    assert_output --partial "CustomLog /var/www/app.example.com/logs/access.log"
}

@test "apache_generate_proxy_config does not include DocumentRoot" {
    export ST_PROXY_PRESERVE_HOST=true
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    refute_output --partial "DocumentRoot"
}

@test "apache_generate_proxy_config does not include PHP-FPM" {
    export ST_PROXY_PRESERVE_HOST=true
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    refute_output --partial "php"
    refute_output --partial "fpm"
}

@test "apache_generate_proxy_config includes WebSocket rules when enabled" {
    export ST_PROXY_PRESERVE_HOST=true
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "true" "true"
    assert_success
    assert_output --partial "RewriteEngine On"
    assert_output --partial "HTTP:Upgrade"
    assert_output --partial "ws://localhost:3000"
}

@test "apache_generate_proxy_config omits WebSocket rules when disabled" {
    export ST_PROXY_PRESERVE_HOST=true
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    refute_output --partial "ws://"
    refute_output --partial "HTTP:Upgrade"
}

@test "apache_generate_proxy_config includes VirtualHost block" {
    export ST_PROXY_PRESERVE_HOST=true
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial "<VirtualHost *:80>"
    assert_output --partial "</VirtualHost>"
}

@test "apache_generate_proxy_config uses configurable ServerAdmin" {
    export ST_PROXY_PRESERVE_HOST=true
    ST_APACHE_SERVER_ADMIN="admin@myserver.com"
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true"
    assert_success
    assert_output --partial "ServerAdmin admin@myserver.com"
}

# --- WebSocket bugfix regression tests (PR #16) ---
# Prior to these fixes, generate_proxy_config emitted an unescaped mod_rewrite
# backreference (so it was expanded to the function's own $1 -- the domain --
# at generation time instead of staying literal) and always used "ws://" even
# for https:// backends (producing an invalid "ws://https://..." double-scheme
# URL). This worktree was branched before PR #16 merged, so both fixes had to
# be re-applied here as part of the apache.sh extraction.

@test "apache_generate_proxy_config websocket RewriteRule keeps literal \$1 backreference" {
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "true" "true"
    assert_success
    assert_output --partial 'RewriteRule ^/?(.*) ws://localhost:3000/$1 [P,L]'
    # Regression guard: must NOT have been expanded to the domain
    refute_output --partial 'ws://localhost:3000/app.example.com'
}

@test "apache_generate_proxy_config uses wss:// (not ws://https://) for https backends" {
    run apache_generate_proxy_config "app.example.com" "" "https://localhost:3000" "true" "true"
    assert_success
    assert_output --partial 'RewriteRule ^/?(.*) wss://localhost:3000/$1 [P,L]'
    refute_output --partial "ws://https://"
}

@test "apache_generate_proxy_config uses ws:// for http backends" {
    run apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "true" "true"
    assert_success
    assert_output --partial 'ws://localhost:3000/$1'
    refute_output --partial "wss://"
}

# =============================================================================
# REDIRECT - pure functions
# =============================================================================

@test "apache_generate_redirect_config includes ServerName" {
    run apache_generate_redirect_config "old.com" "https://new.com/" 301
    assert_success
    assert_output --partial "ServerName old.com"
}

@test "apache_generate_redirect_config includes redirect directive" {
    run apache_generate_redirect_config "old.com" "https://new.com/" 301
    assert_success
    assert_output --partial "Redirect 301 / https://new.com/"
}

@test "apache_generate_redirect_config supports 302 redirect" {
    run apache_generate_redirect_config "old.com" "https://new.com/" 302
    assert_success
    assert_output --partial "Redirect 302"
}

@test "apache_generate_redirect_config includes VirtualHost block" {
    run apache_generate_redirect_config "old.com" "https://new.com/" 301
    assert_success
    assert_output --partial "<VirtualHost *:80>"
    assert_output --partial "</VirtualHost>"
}

@test "apache_generate_www_redirect_snippet generates to_www rules" {
    run apache_generate_www_redirect_snippet "example.com" "to_www"
    assert_success
    assert_output --partial "RewriteEngine On"
    assert_output --partial "www.example.com"
    assert_output --partial "R=301"
}

@test "apache_generate_www_redirect_snippet generates from_www rules" {
    run apache_generate_www_redirect_snippet "example.com" "from_www"
    assert_success
    assert_output --partial "RewriteEngine On"
    assert_output --partial "example.com"
    assert_output --partial "R=301"
}

@test "apache_generate_https_redirect_snippet generates HTTPS rewrite" {
    run apache_generate_https_redirect_snippet "example.com"
    assert_success
    assert_output --partial "RewriteEngine On"
    assert_output --partial "HTTPS"
    assert_output --partial "R=301"
}

# =============================================================================
# PATHS & QUERIES
# =============================================================================

@test "apache_vhost_config_path builds sites-available path with .conf suffix" {
    run apache_vhost_config_path "example.com"
    assert_success
    assert_output "${ST_APACHE_SITES_AVAILABLE}/example.com.conf"
}

@test "apache_vhost_exists is false when no config file present" {
    run apache_vhost_exists "example.com"
    assert_failure
}

@test "apache_vhost_exists is true when config file present" {
    touch "${ST_APACHE_SITES_AVAILABLE}/example.com.conf"
    run apache_vhost_exists "example.com"
    assert_success
}

@test "apache_get_vhost_docroot / apache_get_vhost_php_version round-trip against generator output" {
    apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" \
        > "${ST_APACHE_SITES_AVAILABLE}/example.com.conf"

    run apache_get_vhost_docroot "example.com"
    assert_success
    assert_output "/var/www/example.com/html"

    run apache_get_vhost_php_version "example.com"
    assert_success
    assert_output "8.3"
}

@test "apache_get_vhost_type detects proxy vhosts" {
    apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true" \
        > "${ST_APACHE_SITES_AVAILABLE}/app.example.com.conf"

    run apache_get_vhost_type "app.example.com"
    assert_success
    assert_output "proxy"
}

@test "apache_get_vhost_type detects php vhosts" {
    apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" \
        > "${ST_APACHE_SITES_AVAILABLE}/example.com.conf"

    run apache_get_vhost_type "example.com"
    assert_success
    assert_output "php"
}

@test "apache_get_vhost_backend extracts backend URL from proxy config" {
    apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true" \
        > "${ST_APACHE_SITES_AVAILABLE}/app.example.com.conf"

    run apache_get_vhost_backend "app.example.com"
    assert_success
    assert_output "http://localhost:3000"
}

@test "apache_vhost_enabled is false without a sites-enabled symlink" {
    run apache_vhost_enabled "example.com"
    assert_failure
}

@test "apache_vhost_enabled is true with a sites-enabled symlink" {
    touch "${ST_APACHE_SITES_AVAILABLE}/example.com.conf"
    ln -s "${ST_APACHE_SITES_AVAILABLE}/example.com.conf" "${ST_APACHE_SITES_ENABLED}/example.com.conf"
    run apache_vhost_enabled "example.com"
    assert_success
}

@test "apache_websocket_enabled detects proxy_wstunnel/ws:// markers" {
    apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "true" "true" \
        > "${ST_APACHE_SITES_AVAILABLE}/app.example.com.conf"

    run apache_websocket_enabled "app.example.com"
    assert_success
}

@test "apache_websocket_enabled is false without websocket markers" {
    apache_generate_proxy_config "app.example.com" "" "http://localhost:3000" "false" "true" \
        > "${ST_APACHE_SITES_AVAILABLE}/app.example.com.conf"

    run apache_websocket_enabled "app.example.com"
    assert_failure
}

@test "apache_websocket_enabled detects the wss:// marker on an https:// backend" {
    # Regression: "ws://" is not a substring of "wss://" (wss has an extra
    # "s" before the colon), so a plain "ws://" grep would report websocket
    # support as disabled for every TLS backend.
    apache_generate_proxy_config "app.example.com" "" "https://internal.example.com:8443" "true" "true" \
        > "${ST_APACHE_SITES_AVAILABLE}/app.example.com.conf"

    run apache_websocket_enabled "app.example.com"
    assert_success
}

@test "apache_change_php_version_in_config replaces the FPM socket version" {
    apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" \
        > "${ST_APACHE_SITES_AVAILABLE}/example.com.conf"

    apache_change_php_version_in_config "${ST_APACHE_SITES_AVAILABLE}/example.com.conf" "8.4"

    run apache_get_vhost_php_version "example.com"
    assert_success
    assert_output "8.4"
}

# =============================================================================
# SITE ENABLE/DISABLE/RELOAD MECHANICS
# =============================================================================

@test "apache_enable_site fails and logs when a2ensite fails" {
    mock_command "a2ensite" "exit 1"
    run apache_enable_site "example.com"
    assert_failure
    assert_output --partial "Failed to enable site"
}

@test "apache_enable_site succeeds when a2ensite succeeds" {
    mock_command "a2ensite" "exit 0"
    run apache_enable_site "example.com"
    assert_success
}

@test "apache_disable_site does not fail even if a2dissite fails" {
    mock_command "a2dissite" "exit 1"
    run apache_disable_site "example.com"
    assert_success
}

@test "apache_config_test fails when apache2ctl configtest fails" {
    mock_command "apache2ctl" 'exit 1'
    run apache_config_test
    assert_failure
    assert_output --partial "configuration test failed"
}

@test "apache_config_test succeeds when apache2ctl configtest succeeds" {
    mock_command "apache2ctl" 'exit 0'
    run apache_config_test
    assert_success
}

@test "apache_reload fails without reloading when config test fails" {
    mock_command "apache2ctl" 'exit 1'
    mock_command "systemctl" 'echo "should not run"; exit 1'
    run apache_reload
    assert_failure
    refute_output --partial "should not run"
}

@test "apache_reload reloads apache2 when config test passes" {
    mock_command "apache2ctl" 'exit 0'
    mock_command "systemctl" 'exit 0'
    run apache_reload
    assert_success
    assert_output --partial "reloaded successfully"
}

@test "apache_rewrite_module_ensure enables rewrite module when missing" {
    mock_command "apache2ctl" 'echo "some_other_module"'
    mock_command "a2enmod" 'echo "a2enmod $*" >> "'"${TEST_TMPDIR}"'/a2enmod.log"'
    apache_rewrite_module_ensure
    run cat "${TEST_TMPDIR}/a2enmod.log"
    assert_output --partial "a2enmod rewrite"
}

@test "apache_rewrite_module_ensure is a no-op when rewrite module already enabled" {
    mock_command "apache2ctl" 'echo "rewrite_module (shared)"'
    mock_command "a2enmod" 'echo "a2enmod $*" >> "'"${TEST_TMPDIR}"'/a2enmod.log"'
    apache_rewrite_module_ensure
    [[ ! -f "${TEST_TMPDIR}/a2enmod.log" ]]
}

@test "apache_enable_modules_php returns success even without a2enmod" {
    run apache_enable_modules_php
    assert_success
}

@test "apache_enable_modules_proxy returns success even without a2enmod" {
    run apache_enable_modules_proxy "false"
    assert_success
}

@test "apache_enable_modules_proxy accepts websocket flag" {
    run apache_enable_modules_proxy "true"
    assert_success
}

# =============================================================================
# INSERT-BEFORE-CLOSE
# =============================================================================

@test "apache_insert_before_close inserts snippet before closing VirtualHost tag" {
    local config="${TEST_TMPDIR}/site.conf"
    apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" > "$config"

    apache_insert_before_close "$config" "    # inserted marker"

    run grep -n "inserted marker\|</VirtualHost>" "$config"
    assert_success
    assert_output --partial "inserted marker"
}

@test "apache_insert_before_close preserves every line of a multi-line snippet" {
    # Regression test for #18: sed's "i\" command needs each line of its
    # insert text backslash-escaped for POSIX multi-line continuation. The
    # snippet variable here has real embedded newlines instead, so a naive
    # `sed -i "/<\/VirtualHost>/i\\${snippet}"` silently inserted only the
    # first line and dropped the rest -- meaning add_www_redirect()/
    # force_https() were shipping vhost configs missing their actual
    # RewriteRule directives.
    local config="${TEST_TMPDIR}/site.conf"
    apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" > "$config"

    local snippet
    snippet=$(apache_generate_www_redirect_snippet "example.com" "to_www")
    apache_insert_before_close "$config" "$snippet"

    assert_file_contains "$config" "RewriteEngine On"
    assert_file_contains "$config" "RewriteCond"
    assert_file_contains "$config" "RewriteRule"
}

@test "apache_insert_before_close inserts the snippet before the closing VirtualHost tag" {
    local config="${TEST_TMPDIR}/site.conf"
    apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" > "$config"

    apache_insert_before_close "$config" "    # inserted marker"

    run grep -n "inserted marker\|</VirtualHost>" "$config"
    assert_success
    # "inserted marker" must appear on an earlier line number than </VirtualHost>
    # (head -n1 guards against these becoming multi-line operands to -lt if a
    # fixture ever grows a second match)
    local marker_line vhost_close_line
    marker_line=$(grep -n "inserted marker" "$config" | head -n1 | cut -d: -f1)
    vhost_close_line=$(grep -n "</VirtualHost>" "$config" | head -n1 | cut -d: -f1)
    [[ "$marker_line" -lt "$vhost_close_line" ]]
}

@test "apache_insert_before_close preserves the rest of the config unchanged" {
    local config="${TEST_TMPDIR}/site.conf"
    apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" > "$config"

    apache_insert_before_close "$config" "    # inserted marker"

    run diff <(grep -v "inserted marker" "$config") \
        <(apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html")
    assert_success
}

@test "apache_insert_before_close fails cleanly when the config has no </VirtualHost> tag" {
    # Realistic shape: a truncated file (interrupted write, disk full mid-cp),
    # not just arbitrary non-vhost content.
    local config="${TEST_TMPDIR}/malformed.conf"
    printf '<VirtualHost *:80>\n    ServerName example.com\n' > "$config"

    run apache_insert_before_close "$config" "    # inserted marker"
    assert_failure
}

@test "apache_insert_before_close preserves the config file's permission mode" {
    local config="${TEST_TMPDIR}/site.conf"
    apache_generate_vhost_config "example.com" "" "8.3" "/var/www/example.com/html" > "$config"
    chmod 640 "$config"

    apache_insert_before_close "$config" "    # inserted marker"

    run stat -c '%a' "$config"
    assert_output "640"
}

@test "apache_insert_before_close handles </VirtualHost> on the file's first line" {
    local config="${TEST_TMPDIR}/site.conf"
    printf '</VirtualHost>\n' > "$config"

    apache_insert_before_close "$config" "    # inserted marker"

    run head -n1 "$config"
    assert_output "    # inserted marker"
    assert_file_contains "$config" "</VirtualHost>"
}

@test "apache_insert_before_close ignores a commented-out </VirtualHost> tag" {
    # An unanchored grep for "</VirtualHost>" also matches "#</VirtualHost>"
    # in a hand-edited config with an old, disabled block above the live one
    # -- landing the snippet at global server scope instead of inside the
    # real vhost (RewriteEngine/RewriteCond/RewriteRule are all legal there
    # too, so apache2ctl configtest and reload both succeed while silently
    # affecting every site on the box instead of the intended one).
    local config="${TEST_TMPDIR}/site.conf"
    cat > "$config" <<'EOF'
# Old config, disabled:
#<VirtualHost *:80>
#    ServerName old.example.com
#</VirtualHost>

<VirtualHost *:80>
    ServerName example.com
</VirtualHost>
EOF

    apache_insert_before_close "$config" "    # inserted marker"

    local marker_line real_close_line
    marker_line=$(grep -n "inserted marker" "$config" | head -n1 | cut -d: -f1)
    real_close_line=$(grep -n '^</VirtualHost>' "$config" | head -n1 | cut -d: -f1)
    # The marker must land right before the real (uncommented) close, not
    # the commented-out one a few lines above it.
    [[ "$marker_line" -eq "$((real_close_line - 1))" ]]
}

@test "apache_insert_before_close preserves content after the first </VirtualHost> (a second block)" {
    local config="${TEST_TMPDIR}/site.conf"
    cat > "$config" <<'EOF'
<VirtualHost *:80>
    ServerName first.example.com
</VirtualHost>
<VirtualHost *:443>
    ServerName first.example.com
</VirtualHost>
EOF

    apache_insert_before_close "$config" "    # inserted marker"

    assert_file_contains "$config" "ServerName first.example.com"
    assert_file_contains "$config" "VirtualHost \*:443"
    # The marker only landed before the FIRST close, not both
    run grep -c "inserted marker" "$config"
    assert_output "1"
}
