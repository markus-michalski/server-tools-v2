#!/bin/bash
# Nginx webserver backend: config generation and site management mechanics.
#
# Nginx-native counterpart to lib/webserver/apache.sh, dispatched to by
# lib/vhost.sh when $ST_WEBSERVER=nginx. Pure functions (generate_*) have no
# side effects; the rest wrap nginx/systemctl mechanics with error handling.
#
# SSL/certbot integration for nginx is explicitly out of scope here (see
# lib/ssl.sh, which remains Apache-only) -- that's tracked as follow-up work.

[[ -n "${_NGINX_WS_SOURCED:-}" ]] && return
_NGINX_WS_SOURCED=1

source "${BASH_SOURCE%/*}/../core.sh"
source "${BASH_SOURCE%/*}/../config.sh"
source "${BASH_SOURCE%/*}/../security.sh"

# =============================================================================
# PATHS
# =============================================================================

# Path to a domain's sites-available config file.
# Deliberately no ".conf" extension -- Debian's nginx sites-available
# convention traditionally uses the bare domain as filename (unlike Apache's
# ".conf" suffix). Every nginx_* function below agrees on this convention.
nginx_vhost_config_path() {
    local domain="$1"
    echo "${ST_NGINX_SITES_AVAILABLE}/${domain}"
}

# =============================================================================
# BUILDING BLOCKS - config generation (pure functions, no side effects)
# =============================================================================

# Generate Nginx vhost configuration string (pure function, no side effects)
# The output MUST end with a lone "}" as the last line (closing the server
# block) -- nginx_insert_before_server_close() relies on that invariant.
nginx_generate_vhost_config() {
    local domain="$1"
    local aliases="${2:-}"
    local php_version="$3"
    local docroot="$4"

    cat <<VHOSTEOF
server {
    listen 80;
    server_name ${domain}${aliases:+ ${aliases}};
    root ${docroot};
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_pass unix:/run/php/php${php_version}-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }

    # Security Headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

    access_log /var/www/${domain}/logs/access.log;
    error_log /var/www/${domain}/logs/error.log;
}
VHOSTEOF
}

# Generate Nginx reverse proxy configuration string (pure function, no side effects)
# Same closing-lone-"}" invariant as nginx_generate_vhost_config above.
nginx_generate_proxy_config() {
    local domain="$1"
    local aliases="${2:-}"
    local backend_url="$3"
    local websocket="${4:-false}"
    local preserve_host="${5:-$ST_PROXY_PRESERVE_HOST}"

    # Note: unlike Apache's ProxyPass, nginx's proxy_pass semantics depend on
    # trailing-slash presence on the directive value itself. We pass
    # backend_url through as given, without adding or stripping a trailing
    # slash -- matching Apache's own current (separately tracked, not fixed
    # here) trailing-slash nuance rather than trying to fix it in this PR.
    cat <<PROXYEOF
server {
    listen 80;
    server_name ${domain}${aliases:+ ${aliases}};

    location / {
        proxy_pass ${backend_url};
        proxy_http_version 1.1;
PROXYEOF

    # ProxyPreserveHost mapping: Apache's "ProxyPreserveHost On" forwards the
    # client's original Host header to the backend. Nginx has no single
    # on/off directive for this -- we approximate it by either setting Host
    # explicitly (preserve = on/default) or omitting it, which falls back to
    # nginx's own default of forwarding $proxy_host (the backend's host:port,
    # i.e. NOT preserved) when preserve_host == "false".
    if [[ "$preserve_host" != "false" ]]; then
        cat <<HOSTEOF
        proxy_set_header Host \$host;
HOSTEOF
    fi

    cat <<HEADEOF
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Port \$server_port;
HEADEOF

    if [[ "$websocket" == "true" ]]; then
        # Nginx's websocket proxying needs no regex rewrite rule or
        # backreference (unlike Apache's mod_rewrite-based hack) -- just
        # these two header lines. No $1-style bug class is possible here.
        cat <<WSEOF
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
WSEOF
    fi

    cat <<TAILEOF
    }

    # Security Headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

    access_log /var/www/${domain}/logs/access.log;
    error_log /var/www/${domain}/logs/error.log;
}
TAILEOF
}

# Generate a redirect vhost config (pure function)
nginx_generate_redirect_config() {
    local source_domain="$1"
    local target_url="$2"
    local code="${3:-301}"

    # Deliberately NOT appending $request_uri: Apache's redirect vhost
    # (apache_generate_redirect_config, using the "Redirect" directive) does a
    # bare redirect that does not forward the original request path either.
    # Matching that cross-backend behavior matters more here than idiomatic
    # nginx style, so this stays a plain "return CODE URL;".
    cat <<REDIRECTEOF
# Redirect vhost for ${source_domain}
# Created by server-tools on $(date '+%Y-%m-%d %H:%M:%S')
server {
    listen 80;
    server_name ${source_domain};

    return ${code} ${target_url};
}
REDIRECTEOF
}

# Generate www redirect snippet (pure function)
nginx_generate_www_redirect_snippet() {
    local domain="$1"
    local direction="${2:-to_www}"

    if [[ "$direction" == "to_www" ]]; then
        cat <<WWWEOF
    # Redirect non-www to www
    if (\$host = ${domain}) {
        return 301 http://www.${domain}\$request_uri;
    }
WWWEOF
    else
        cat <<WWWEOF
    # Redirect www to non-www
    if (\$host = www.${domain}) {
        return 301 http://${domain}\$request_uri;
    }
WWWEOF
    fi
}

# Generate HTTPS redirect snippet (pure function)
nginx_generate_https_redirect_snippet() {
    local domain="$1"

    cat <<HTTPSEOF
    # Force HTTPS redirect
    if (\$scheme = http) {
        return 301 https://\$host\$request_uri;
    }
HTTPSEOF
}

# =============================================================================
# BUILDING BLOCKS - queries & mechanics
# =============================================================================

# Check if a vhost config exists
nginx_vhost_exists() {
    local domain="$1"
    [[ -f "$(nginx_vhost_config_path "$domain")" ]]
}

# Extract docroot ("root ...;") from a vhost config
nginx_get_vhost_docroot() {
    local domain="$1"
    local config
    config=$(nginx_vhost_config_path "$domain")

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    grep -i "^[[:space:]]*root[[:space:]]" "$config" | head -n1 | awk '{print $2}' | sed 's/;$//'
}

# Extract PHP version from a vhost config (e.g. from the fastcgi_pass socket path)
nginx_get_vhost_php_version() {
    local domain="$1"
    local config
    config=$(nginx_vhost_config_path "$domain")

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    grep -oP 'php\K[0-9]+\.[0-9]+' "$config" | head -n1
}

# Detect vhost type from config (php or proxy)
nginx_get_vhost_type() {
    local domain="$1"
    local config
    config=$(nginx_vhost_config_path "$domain")

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    if grep -q "proxy_pass " "$config" 2>/dev/null; then
        echo "proxy"
    else
        echo "php"
    fi
}

# Extract backend URL from a proxy vhost config
nginx_get_vhost_backend() {
    local domain="$1"
    local config
    config=$(nginx_vhost_config_path "$domain")

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    grep -oP '^\s*proxy_pass\s+\K\S+' "$config" | head -n1 | sed 's/;$//'
}

# Check whether the vhost is enabled (symlinked into sites-enabled)
nginx_vhost_enabled() {
    local domain="$1"
    [[ -L "${ST_NGINX_SITES_ENABLED}/${domain}" ]]
}

# Check whether the vhost config has WebSocket proxy support -- consistent
# with the marker nginx_generate_proxy_config's websocket branch emits.
nginx_websocket_enabled() {
    local domain="$1"
    grep -q "Upgrade.*http_upgrade" "$(nginx_vhost_config_path "$domain")" 2>/dev/null
}

# Replace the PHP-FPM socket version referenced in a vhost config
nginx_change_php_version_in_config() {
    local config_file="$1"
    local new_version="$2"

    sed -i "s|/run/php/php[0-9.]*-fpm.sock|/run/php/php${new_version}-fpm.sock|g" "$config_file"
}

# =============================================================================
# BUILDING BLOCKS - site enable/disable/reload
# =============================================================================

# Enable an Nginx site (wrapper with error handling)
nginx_enable_site() {
    local domain="$1"
    if ! ln -sf "${ST_NGINX_SITES_AVAILABLE}/${domain}" "${ST_NGINX_SITES_ENABLED}/${domain}"; then
        log_error "Failed to enable site: $domain"
        return 1
    fi
}

# Disable an Nginx site (wrapper with error handling)
nginx_disable_site() {
    local domain="$1"
    rm -f "${ST_NGINX_SITES_ENABLED}/${domain}"
}

# Run Nginx's config syntax test
nginx_config_test() {
    log_info "Testing Nginx configuration..."
    if ! nginx -t &>/dev/null; then
        log_error "Nginx configuration test failed!"
        nginx -t 2>&1 | sed 's/^/  /' >&2
        return 1
    fi
}

# Reload Nginx with config test (safe reload with rollback info)
nginx_reload() {
    nginx_config_test || return 1

    log_info "Reloading Nginx..."
    if ! systemctl reload nginx; then
        log_error "Nginx reload failed!"
        return 1
    fi

    log_info "Nginx reloaded successfully"
}

# =============================================================================
# BUILDING BLOCKS - module enablement
# =============================================================================

# Nginx has no a2enmod equivalent: proxy/fastcgi/rewrite (if/return) support
# is compiled in by default on Debian's nginx packages. No-op, kept so the
# router can call it unconditionally without knowing backend-specific quirks.
nginx_enable_modules_php() {
    return 0
}

# See nginx_enable_modules_php -- same reasoning, nothing to enable.
nginx_enable_modules_proxy() {
    return 0
}

# Nginx's if/return redirect blocks need no module. No-op for router symmetry
# with apache_rewrite_module_ensure.
nginx_rewrite_module_ensure() {
    return 0
}

# Insert a config snippet right before the closing "}" (the last line) of a
# vhost config generated by nginx_generate_vhost_config/nginx_generate_proxy_config.
#
# Deliberately not sed's "i\" command here: sed's multi-line insert text needs
# a backslash before every embedded newline (POSIX continuation syntax), and
# our snippets are plain multi-line strings without that escaping -- sed would
# silently insert only the snippet's first line and discard the rest (or, if
# the snippet contains "{"/"}", error out trying to parse the remainder as
# more sed script). head/tail avoids that whole class of bug and is trivial
# to verify against the "last line is a lone '}'" invariant.
nginx_insert_before_server_close() {
    local config_file="$1"
    local snippet="$2"
    local tmp
    tmp=$(mktemp "${config_file}.XXXXXX")
    if ! { head -n -1 "$config_file" && printf '%s\n' "$snippet" && tail -n1 "$config_file"; } >"$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    mv -f "$tmp" "$config_file"
}
