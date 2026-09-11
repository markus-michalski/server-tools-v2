#!/bin/bash
# Apache webserver backend: config generation and site management mechanics.
#
# Extracted from lib/vhost.sh so that lib/vhost.sh can stay webserver-agnostic
# and dispatch to this file (or webserver/nginx.sh) based on $ST_WEBSERVER.
# Pure functions (generate_*) have no side effects; the rest wrap apachectl/
# a2en*/a2dis* mechanics with error handling.

[[ -n "${_APACHE_WS_SOURCED:-}" ]] && return
_APACHE_WS_SOURCED=1

source "${BASH_SOURCE%/*}/../core.sh"
source "${BASH_SOURCE%/*}/../config.sh"
source "${BASH_SOURCE%/*}/../security.sh"

# =============================================================================
# PATHS
# =============================================================================

# Path to a domain's sites-available config file
apache_vhost_config_path() {
    local domain="$1"
    echo "${ST_APACHE_SITES_AVAILABLE}/${domain}.conf"
}

# =============================================================================
# BUILDING BLOCKS - config generation (pure functions, no side effects)
# =============================================================================

# Generate the Forwarded-Proto/Port header snippet shared by both vhost templates.
# Uses Apache's ap_expr (%{REQUEST_SCHEME}/%{SERVER_PORT}) instead of hardcoded
# "https"/"443" literals so the value is correct on the plain port-80 vhost too --
# certbot --apache copies this verbatim into the generated -le-ssl.conf, where the
# same expression then correctly evaluates to https/443.
apache_forwarded_headers_snippet() {
    cat <<'FWDEOF'
    # Forwarded Headers
    RequestHeader set X-Forwarded-Proto expr=%{REQUEST_SCHEME}
    RequestHeader set X-Forwarded-Port expr=%{SERVER_PORT}
FWDEOF
}

# Generate Apache vhost configuration string (pure function, no side effects)
apache_generate_vhost_config() {
    local domain="$1"
    local aliases="${2:-}"
    local php_version="$3"
    local docroot="$4"

    cat <<VHOSTEOF
<VirtualHost *:80>
    ServerName ${domain}
    ${aliases:+ServerAlias ${aliases}}
    ServerAdmin ${ST_APACHE_SERVER_ADMIN}
    DocumentRoot ${docroot}

    <Directory ${docroot}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/php${php_version}-fpm.sock|fcgi://localhost"
    </FilesMatch>

    # Security Headers
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"

$(apache_forwarded_headers_snippet)

    ServerSignature Off

    ErrorLog /var/www/${domain}/logs/error.log
    CustomLog /var/www/${domain}/logs/access.log combined
</VirtualHost>
VHOSTEOF
}

# Generate Apache reverse proxy configuration string (pure function, no side effects)
apache_generate_proxy_config() {
    local domain="$1"
    local aliases="${2:-}"
    local backend_url="$3"
    local websocket="${4:-false}"
    local preserve_host="${5:-$ST_PROXY_PRESERVE_HOST}"

    local preserve_host_value="On"
    [[ "$preserve_host" == "false" ]] && preserve_host_value="Off"

    cat <<PROXYEOF
<VirtualHost *:80>
    ServerName ${domain}
    ${aliases:+ServerAlias ${aliases}}
    ServerAdmin ${ST_APACHE_SERVER_ADMIN}

    ProxyPreserveHost ${preserve_host_value}
    ProxyPass / ${backend_url}/
    ProxyPassReverse / ${backend_url}/
PROXYEOF

    if [[ "$websocket" == "true" ]]; then
        # WebSocket scheme mirrors the backend's scheme: an https:// backend needs
        # wss://, not ws://https://... (the latter is a double-scheme bug).
        local ws_scheme="ws"
        local backend_host="${backend_url#http://}"
        if [[ "$backend_url" == https://* ]]; then
            ws_scheme="wss"
            backend_host="${backend_url#https://}"
        fi

        cat <<WSEOF

    # WebSocket proxy support
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/?(.*) ${ws_scheme}://${backend_host}/\$1 [P,L]
WSEOF
    fi

    cat <<PROXYEOF2

    # Security Headers
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"

$(apache_forwarded_headers_snippet)

    ServerSignature Off

    ErrorLog /var/www/${domain}/logs/error.log
    CustomLog /var/www/${domain}/logs/access.log combined
</VirtualHost>
PROXYEOF2
}

# Generate a redirect vhost config (pure function)
apache_generate_redirect_config() {
    local source_domain="$1"
    local target_url="$2"
    local code="${3:-301}"

    cat <<REDIRECTEOF
# Redirect vhost for ${source_domain}
# Created by server-tools on $(date '+%Y-%m-%d %H:%M:%S')
<VirtualHost *:80>
    ServerName ${source_domain}
    ServerAdmin ${ST_APACHE_SERVER_ADMIN}

    Redirect ${code} / ${target_url}

    ErrorLog /var/log/apache2/${source_domain}-error.log
</VirtualHost>
REDIRECTEOF
}

# Generate www redirect snippet (pure function)
apache_generate_www_redirect_snippet() {
    local domain="$1"
    local direction="${2:-to_www}"

    if [[ "$direction" == "to_www" ]]; then
        cat <<WWWEOF
    # Redirect non-www to www
    RewriteEngine On
    RewriteCond %{HTTP_HOST} ^${domain}\$ [NC]
    RewriteRule ^(.*)\$ http://www.${domain}\$1 [R=301,L]
WWWEOF
    else
        cat <<WWWEOF
    # Redirect www to non-www
    RewriteEngine On
    RewriteCond %{HTTP_HOST} ^www\.${domain}\$ [NC]
    RewriteRule ^(.*)\$ http://${domain}\$1 [R=301,L]
WWWEOF
    fi
}

# Generate HTTPS redirect snippet (pure function)
apache_generate_https_redirect_snippet() {
    local domain="$1"

    cat <<HTTPSEOF
    # Force HTTPS redirect
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)\$ https://%{HTTP_HOST}\$1 [R=301,L]
HTTPSEOF
}

# =============================================================================
# BUILDING BLOCKS - queries & mechanics
# =============================================================================

# Check if a vhost config exists
apache_vhost_exists() {
    local domain="$1"
    [[ -f "$(apache_vhost_config_path "$domain")" ]]
}

# Extract DocumentRoot from a vhost config
apache_get_vhost_docroot() {
    local domain="$1"
    local config
    config=$(apache_vhost_config_path "$domain")

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    grep -i "^[[:space:]]*DocumentRoot" "$config" | head -n1 | awk '{print $2}'
}

# Extract PHP version from a vhost config
apache_get_vhost_php_version() {
    local domain="$1"
    local config
    config=$(apache_vhost_config_path "$domain")

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    grep -oP 'php\K[0-9]+\.[0-9]+' "$config" | head -n1
}

# Detect vhost type from config (php or proxy)
apache_get_vhost_type() {
    local domain="$1"
    local config
    config=$(apache_vhost_config_path "$domain")

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    if grep -q "ProxyPass " "$config" 2>/dev/null; then
        echo "proxy"
    else
        echo "php"
    fi
}

# Extract backend URL from a proxy vhost config
apache_get_vhost_backend() {
    local domain="$1"
    local config
    config=$(apache_vhost_config_path "$domain")

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    grep -oP '^\s*ProxyPass\s+/\s+\K\S+' "$config" | head -n1 | sed 's|/$||'
}

# Check whether the vhost is enabled (symlinked into sites-enabled)
apache_vhost_enabled() {
    local domain="$1"
    [[ -L "${ST_APACHE_SITES_ENABLED}/${domain}.conf" ]]
}

# Check whether the vhost config has WebSocket proxy support. "wss?://" (not
# "ws://") so an https:// backend's "wss://" scheme still matches -- "ws://"
# alone is not a substring of "wss://" (wss = w,s,s,:,/,/ vs. ws = w,s,:,/,/).
apache_websocket_enabled() {
    local domain="$1"
    grep -qE "proxy_wstunnel|wss?://" "$(apache_vhost_config_path "$domain")" 2>/dev/null
}

# Replace the PHP-FPM socket version referenced in a vhost config
apache_change_php_version_in_config() {
    local config_file="$1"
    local new_version="$2"

    sed -i "s|proxy:unix:/run/php/php[0-9.]*-fpm.sock|proxy:unix:/run/php/php${new_version}-fpm.sock|g" "$config_file"
}

# =============================================================================
# BUILDING BLOCKS - site enable/disable/reload
# =============================================================================

# Enable an Apache site (wrapper with error handling)
apache_enable_site() {
    local domain="$1"
    if ! a2ensite "${domain}.conf" &>/dev/null; then
        log_error "Failed to enable site: $domain"
        return 1
    fi
}

# Disable an Apache site (wrapper with error handling)
apache_disable_site() {
    local domain="$1"
    a2dissite "${domain}.conf" &>/dev/null || true
}

# Run Apache's config syntax test
apache_config_test() {
    log_info "Testing Apache configuration..."
    if ! apache2ctl configtest &>/dev/null; then
        log_error "Apache configuration test failed!"
        apache2ctl configtest 2>&1 | sed 's/^/  /' >&2
        return 1
    fi
}

# Reload Apache with config test (safe reload with rollback info)
apache_reload() {
    apache_config_test || return 1

    log_info "Reloading Apache..."
    if ! systemctl reload apache2; then
        log_error "Apache reload failed!"
        return 1
    fi

    log_info "Apache reloaded successfully"
}

# =============================================================================
# BUILDING BLOCKS - module enablement
# =============================================================================

# Enable Apache modules needed for PHP-FPM vhosts
apache_enable_modules_php() {
    a2enmod headers 2>/dev/null || true
    a2enmod proxy_fcgi 2>/dev/null || true
}

# Enable Apache modules needed for reverse proxy vhosts
apache_enable_modules_proxy() {
    local websocket="${1:-false}"

    a2enmod headers 2>/dev/null || true
    a2enmod proxy 2>/dev/null || true
    a2enmod proxy_http 2>/dev/null || true
    if [[ "$websocket" == "true" ]]; then
        a2enmod proxy_wstunnel 2>/dev/null || true
        a2enmod rewrite 2>/dev/null || true
    fi
}

# Ensure Apache's rewrite module is enabled (needed for www/https redirect snippets)
apache_rewrite_module_ensure() {
    if ! apache2ctl -M 2>/dev/null | grep -q "rewrite_module"; then
        log_info "Enabling rewrite module..."
        a2enmod rewrite &>/dev/null
    fi
}

# Insert a config snippet right before the first </VirtualHost> closing tag.
#
# Deliberately not sed's "i\" command: sed's multi-line insert text needs a
# backslash before every embedded newline (POSIX continuation syntax), and
# snippet is a plain multi-line string without that escaping -- sed would
# silently insert only the first line and discard the rest. head/tail avoids
# that whole class of bug. Targets the *first* </VirtualHost> match, not
# every match the way the old sed did -- for force_https() in particular,
# inserting into every block would create a redirect loop on a :443 block;
# for the single-block files this tool generates it's a no-op either way.
apache_insert_before_close() {
    local config_file="$1"
    local snippet="$2"

    local line_no
    line_no=$(grep -n '^[[:space:]]*</VirtualHost>' "$config_file" | head -n1 | cut -d: -f1)

    if [[ -z "$line_no" ]]; then
        log_error "No </VirtualHost> found in $config_file"
        return 1
    fi

    local tmp
    tmp=$(mktemp "${config_file}.XXXXXX") || {
        log_error "Failed to create temp file for $config_file"
        return 1
    }
    # mktemp creates its file at mode 600; preserve the config's actual mode
    # (640/644, see create_vhost/create_redirect) rather than silently
    # narrowing permissions on the atomic rename below.
    chmod --reference="$config_file" "$tmp" 2>/dev/null || chmod 640 "$tmp"

    if ! { head -n "$((line_no - 1))" "$config_file" && printf '%s\n' "$snippet" && tail -n "+${line_no}" "$config_file"; } >"$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    if ! mv -f "$tmp" "$config_file"; then
        rm -f "$tmp"
        return 1
    fi
}
