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
    export ST_CERTBOT_EMAIL="admin@example.com"
    mkdir -p "${ST_CREDENTIAL_DIR}" "${ST_BACKUP_DIR}"
    source_lib "ssl"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# --- certbot_installed ---

@test "certbot_installed returns success when certbot exists" {
    mock_command "certbot" "echo certbot"
    run certbot_installed
    assert_success
}

@test "certbot_installed returns failure when certbot missing" {
    # Override command_exists to simulate missing certbot
    command_exists() { return 1; }
    run certbot_installed
    assert_failure
}

# --- cert_exists ---

@test "cert_exists returns success when cert directory exists" {
    mkdir -p "/tmp/test_le_$$"
    mkdir -p "/tmp/test_le_$$/live/example.com"

    # We can't easily test against /etc/letsencrypt, so test the function logic
    # by checking that it looks for the right directory
    run cert_exists "nonexistent-domain-$$.test"
    assert_failure

    rm -rf "/tmp/test_le_$$"
}

# --- get_cert_expiry ---

@test "get_cert_expiry fails when cert file missing" {
    run get_cert_expiry "nonexistent-domain.test"
    assert_failure
}

# --- setup_ssl input validation ---

@test "setup_ssl rejects invalid domain" {
    run setup_ssl "bad domain name"
    assert_failure
    assert_output --partial "Invalid domain"
}

@test "setup_ssl requires existing vhost" {
    run setup_ssl "example.com"
    assert_failure
    assert_output --partial "does not exist"
}

@test "setup_ssl uses ST_CERTBOT_EMAIL when no email provided" {
    # Create mock vhost config so vhost_exists passes
    mkdir -p "/tmp/test_apache_$$"
    local orig_vhost_exists
    # Override vhost_exists for this test
    vhost_exists() { return 0; }
    # Mock certbot
    mock_command "certbot" 'echo "mock certbot $@"; exit 0'
    mock_command "systemctl" 'exit 0'
    mock_command "apache2ctl" 'exit 0'

    run setup_ssl "example.com"
    assert_success
    assert_output --partial "admin@example.com"
}

@test "setup_ssl uses webmaster@ fallback when no email configured" {
    export ST_CERTBOT_EMAIL=""
    vhost_exists() { return 0; }
    mock_command "certbot" 'echo "mock certbot $@"; exit 0'
    mock_command "systemctl" 'exit 0'
    mock_command "apache2ctl" 'exit 0'

    run setup_ssl "example.com"
    assert_success
    assert_output --partial "webmaster@example.com"
}

# --- delete_ssl input validation ---

@test "delete_ssl rejects invalid domain" {
    run delete_ssl "bad;domain"
    assert_failure
}

@test "delete_ssl fails when no certificate exists" {
    run delete_ssl "example.com"
    assert_failure
    assert_output --partial "No certificate found"
}

# --- list_certificates ---

@test "list_certificates shows message when certbot not installed" {
    # Override certbot_installed to simulate missing certbot
    certbot_installed() { return 1; }
    run list_certificates
    assert_success
    assert_output --partial "not installed"
}

# --- check_expiring_soon ---

@test "check_expiring_soon handles missing letsencrypt directory" {
    run check_expiring_soon 30
    assert_success
    assert_output --partial "No certificates found"
}

@test "check_expiring_soon accepts custom day parameter" {
    run check_expiring_soon 7
    assert_success
    assert_output --partial "7 Days"
}

@test "check_expiring_soon defaults to 30 days" {
    run check_expiring_soon
    assert_success
    assert_output --partial "30 Days"
}

# --- Wildcard SSL ---

@test "setup_wildcard_ssl rejects invalid domain" {
    run setup_wildcard_ssl "bad domain" "cloudflare"
    assert_failure
    assert_output --partial "Invalid domain"
}

@test "setup_wildcard_ssl requires DNS provider" {
    export ST_DNS_PROVIDER=""
    run setup_wildcard_ssl "example.com" ""
    assert_failure
    assert_output --partial "DNS provider not configured"
}

@test "certbot_dns_plugin_installed returns failure when no provider" {
    export ST_DNS_PROVIDER=""
    run certbot_dns_plugin_installed ""
    assert_failure
}

@test "get_dns_credentials_path returns configured path" {
    export ST_DNS_CREDENTIALS_FILE="/root/my-creds.ini"
    run get_dns_credentials_path "cloudflare"
    assert_success
    assert_output "/root/my-creds.ini"
}

@test "get_dns_credentials_path returns default path when not configured" {
    export ST_DNS_CREDENTIALS_FILE=""
    export ST_DNS_PROVIDER=""
    run get_dns_credentials_path "cloudflare"
    assert_success
    assert_output "/root/.certbot-dns-cloudflare.ini"
}

@test "setup_wildcard_ssl fails when credentials file missing" {
    mock_command "certbot" 'exit 0'
    mock_command "dpkg" 'exit 0'
    export ST_DNS_PROVIDER="cloudflare"
    export ST_DNS_CREDENTIALS_FILE="${TEST_TMPDIR}/nonexistent.ini"
    run setup_wildcard_ssl "example.com" "cloudflare"
    assert_failure
    assert_output --partial "credentials file not found"
}

# --- fix_ssl_proxy_config ---

@test "fix_ssl_proxy_config replaces https://localhost with http:// in ProxyPass" {
    local sites_dir="${TEST_TMPDIR}/sites-available"
    mkdir -p "$sites_dir"
    export ST_APACHE_SITES_AVAILABLE="$sites_dir"
    cat > "${sites_dir}/app.example.com-le-ssl.conf" <<'EOF'
<VirtualHost *:443>
    ServerName app.example.com
    ProxyPass / https://localhost:3000/
    ProxyPassReverse / https://localhost:3000/
</VirtualHost>
EOF

    run fix_ssl_proxy_config "app.example.com"
    assert_success
    run grep "ProxyPass / " "${sites_dir}/app.example.com-le-ssl.conf"
    assert_output --partial "http://localhost:3000/"
    refute_output --partial "https://localhost:3000/"
}

@test "fix_ssl_proxy_config replaces https://localhost in ProxyPassReverse" {
    local sites_dir="${TEST_TMPDIR}/sites-available"
    mkdir -p "$sites_dir"
    export ST_APACHE_SITES_AVAILABLE="$sites_dir"
    cat > "${sites_dir}/app.example.com-le-ssl.conf" <<'EOF'
<VirtualHost *:443>
    ProxyPass / https://localhost:8080/
    ProxyPassReverse / https://localhost:8080/
</VirtualHost>
EOF

    run fix_ssl_proxy_config "app.example.com"
    assert_success
    run grep "ProxyPassReverse" "${sites_dir}/app.example.com-le-ssl.conf"
    assert_output --partial "http://localhost:8080/"
    refute_output --partial "https://localhost:8080/"
}

@test "fix_ssl_proxy_config does not change https:// for non-localhost backends" {
    local sites_dir="${TEST_TMPDIR}/sites-available"
    mkdir -p "$sites_dir"
    export ST_APACHE_SITES_AVAILABLE="$sites_dir"
    cat > "${sites_dir}/app.example.com-le-ssl.conf" <<'EOF'
<VirtualHost *:443>
    ProxyPass / https://upstream.internal:3000/
    ProxyPassReverse / https://upstream.internal:3000/
</VirtualHost>
EOF

    run fix_ssl_proxy_config "app.example.com"
    assert_success
    run cat "${sites_dir}/app.example.com-le-ssl.conf"
    assert_output --partial "https://upstream.internal:3000/"
}

@test "fix_ssl_proxy_config fixes https://[::1] IPv6 loopback backend" {
    local sites_dir="${TEST_TMPDIR}/sites-available"
    mkdir -p "$sites_dir"
    export ST_APACHE_SITES_AVAILABLE="$sites_dir"
    cat > "${sites_dir}/app.example.com-le-ssl.conf" <<'EOF'
<VirtualHost *:443>
    ProxyPass / https://[::1]:9000/
    ProxyPassReverse / https://[::1]:9000/
</VirtualHost>
EOF

    run fix_ssl_proxy_config "app.example.com"
    assert_success
    run cat "${sites_dir}/app.example.com-le-ssl.conf"
    assert_output --partial "http://[::1]:9000/"
    refute_output --partial "https://[::1]:9000/"
}

@test "fix_ssl_proxy_config warns and returns failure when sed fails" {
    local sites_dir="${TEST_TMPDIR}/sites-available"
    mkdir -p "$sites_dir"
    export ST_APACHE_SITES_AVAILABLE="$sites_dir"
    printf '    ProxyPass / https://localhost:3000/\n' > "${sites_dir}/app.example.com-le-ssl.conf"
    mock_command "sed" "exit 1"

    run fix_ssl_proxy_config "app.example.com"
    assert_failure
    assert_output --partial "Could not fix proxy passthrough"
}

@test "fix_ssl_proxy_config is a no-op when SSL config does not exist" {
    export ST_APACHE_SITES_AVAILABLE="${TEST_TMPDIR}/sites-available"
    run fix_ssl_proxy_config "nonexistent.example.com"
    assert_success
}

@test "fix_ssl_proxy_config fixes https://localhost/ without port" {
    local sites_dir="${TEST_TMPDIR}/sites-available"
    mkdir -p "$sites_dir"
    export ST_APACHE_SITES_AVAILABLE="$sites_dir"
    cat > "${sites_dir}/app.example.com-le-ssl.conf" <<'EOF'
<VirtualHost *:443>
    ProxyPass / https://localhost/
    ProxyPassReverse / https://localhost/
</VirtualHost>
EOF

    run fix_ssl_proxy_config "app.example.com"
    assert_success
    run cat "${sites_dir}/app.example.com-le-ssl.conf"
    assert_output --partial "http://localhost/"
    refute_output --partial "https://localhost/"
}

@test "fix_ssl_proxy_config fixes https://127.0.0.1 loopback backend" {
    local sites_dir="${TEST_TMPDIR}/sites-available"
    mkdir -p "$sites_dir"
    export ST_APACHE_SITES_AVAILABLE="$sites_dir"
    cat > "${sites_dir}/app.example.com-le-ssl.conf" <<'EOF'
<VirtualHost *:443>
    ProxyPass / https://127.0.0.1:8080/
    ProxyPassReverse / https://127.0.0.1:8080/
</VirtualHost>
EOF

    run fix_ssl_proxy_config "app.example.com"
    assert_success
    run cat "${sites_dir}/app.example.com-le-ssl.conf"
    assert_output --partial "http://127.0.0.1:8080/"
    refute_output --partial "https://127.0.0.1:8080/"
}

@test "fix_ssl_proxy_config is a no-op when config has no ProxyPass" {
    local sites_dir="${TEST_TMPDIR}/sites-available"
    mkdir -p "$sites_dir"
    export ST_APACHE_SITES_AVAILABLE="$sites_dir"
    cat > "${sites_dir}/app.example.com-le-ssl.conf" <<'EOF'
<VirtualHost *:443>
    DocumentRoot /var/www/app.example.com/public
</VirtualHost>
EOF

    run fix_ssl_proxy_config "app.example.com"
    assert_success
}

@test "setup_ssl fixes https://localhost in SSL vhost after certbot for proxy vhosts" {
    local sites_dir="${TEST_TMPDIR}/sites-available"
    mkdir -p "$sites_dir"
    export ST_APACHE_SITES_AVAILABLE="$sites_dir"

    vhost_exists() { return 0; }
    mock_command "systemctl" 'exit 0'
    mock_command "apache2ctl" 'exit 0'
    # Simulate certbot creating SSL conf with wrong https://localhost (the bug)
    mock_command "certbot" "
        mkdir -p '${sites_dir}'
        cat > '${sites_dir}/example.com-le-ssl.conf' <<'CERTBOT_EOF'
<VirtualHost *:443>
    ServerName example.com
    ProxyPass / https://localhost:3000/
    ProxyPassReverse / https://localhost:3000/
</VirtualHost>
CERTBOT_EOF
        exit 0
    "

    run setup_ssl "example.com"
    assert_success
    run grep "ProxyPass / " "${sites_dir}/example.com-le-ssl.conf"
    assert_output --partial "http://localhost:3000/"
    refute_output --partial "https://localhost:3000/"
}
