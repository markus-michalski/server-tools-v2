#!/bin/bash
# VHost library: composable Apache virtual host management with PHP-FPM
#
# Building blocks: pure functions for config generation, site management
# High-level ops: create/delete/list/modify vhosts

[[ -n "${_VHOST_SOURCED:-}" ]] && return
_VHOST_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"
source "${BASH_SOURCE%/*}/config.sh"
source "${BASH_SOURCE%/*}/security.sh"
source "${BASH_SOURCE%/*}/backup.sh"

# =============================================================================
# BUILDING BLOCKS
# =============================================================================

# Detect installed PHP-FPM versions by checking for sockets
detect_php_versions() {
    local versions=()
    for version in $ST_PHP_VERSIONS_TO_SCAN; do
        if [[ -S "/run/php/php${version}-fpm.sock" ]]; then
            versions+=("$version")
        fi
    done
    echo "${versions[*]}"
}

# Check if a vhost config exists
vhost_exists() {
    local domain="$1"
    [[ -f "/etc/apache2/sites-available/${domain}.conf" ]]
}

# Extract DocumentRoot from a vhost config
get_vhost_docroot() {
    local domain="$1"
    local config="/etc/apache2/sites-available/${domain}.conf"

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    grep -i "^[[:space:]]*DocumentRoot" "$config" | head -n1 | awk '{print $2}'
}

# Extract PHP version from a vhost config
get_vhost_php_version() {
    local domain="$1"
    local config="/etc/apache2/sites-available/${domain}.conf"

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    grep -oP 'php\K[0-9]+\.[0-9]+' "$config" | head -n1
}

# Generate Apache vhost configuration string (pure function, no side effects)
generate_vhost_config() {
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

    ServerSignature Off

    ErrorLog /var/www/${domain}/logs/error.log
    CustomLog /var/www/${domain}/logs/access.log combined
</VirtualHost>
VHOSTEOF
}

# Generate welcome page content (pure function)
generate_welcome_page() {
    local domain="$1"

    cat <<'PHPEOF'
<?php
$domain = htmlspecialchars($_SERVER['SERVER_NAME'] ?? 'unknown', ENT_QUOTES, 'UTF-8');
$docroot = htmlspecialchars(__DIR__, ENT_QUOTES, 'UTF-8');
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to <?= $domain ?></title>
    <style>
        body { font-family: system-ui, sans-serif; margin: 40px; color: #333; }
        h1 { color: #2d5016; }
        .info { background: #f0f0f0; padding: 15px; border-left: 4px solid #2d5016; margin: 15px 0; }
    </style>
</head>
<body>
    <h1>Welcome to <?= $domain ?></h1>
    <div class="info">
        <p><strong>Status:</strong> Virtual host created successfully</p>
        <p><strong>PHP:</strong> <?= phpversion() ?></p>
        <p><strong>Created:</strong> <?= date('Y-m-d H:i:s') ?></p>
        <p><strong>DocumentRoot:</strong> <?= $docroot ?></p>
    </div>
</body>
</html>
PHPEOF
}

# Enable an Apache site (wrapper with error handling)
enable_site() {
    local domain="$1"
    if ! a2ensite "${domain}.conf" &>/dev/null; then
        log_error "Failed to enable site: $domain"
        return 1
    fi
}

# Disable an Apache site (wrapper with error handling)
disable_site() {
    local domain="$1"
    a2dissite "${domain}.conf" &>/dev/null || true
}

# Reload Apache with config test (safe reload with rollback info)
reload_apache() {
    log_info "Testing Apache configuration..."
    if ! apache2ctl configtest &>/dev/null; then
        log_error "Apache configuration test failed!"
        apache2ctl configtest 2>&1 | sed 's/^/  /' >&2
        return 1
    fi

    log_info "Reloading Apache..."
    if ! systemctl reload apache2; then
        log_error "Apache reload failed!"
        return 1
    fi

    log_info "Apache reloaded successfully"
}

# =============================================================================
# LOGROTATE - pure functions + operations
# =============================================================================

# Generate logrotate config for a domain (pure function)
generate_logrotate_config() {
    local domain="$1"
    local log_dir="/var/www/${domain}/logs"

    cat <<LOGROTATEEOF
${log_dir}/*.log {
    weekly
    missingok
    rotate ${ST_LOGROTATE_ROTATE}
    maxage ${ST_LOGROTATE_DAYS}
    compress
    delaycompress
    notifempty
    create 640 www-data www-data
    sharedscripts
    postrotate
        if [ -f /var/run/apache2/apache2.pid ]; then
            systemctl reload apache2 > /dev/null 2>&1 || true
        fi
    endscript
}
LOGROTATEEOF
}

# Setup logrotate for a domain
setup_logrotate() {
    local domain="$1"

    validate_input "$domain" "domain" || return 1

    local config
    config=$(generate_logrotate_config "$domain")
    safe_write_file "/etc/logrotate.d/vhost-${domain}" "$config" 644

    audit_log "INFO" "Logrotate: created config for $domain"
    log_info "Logrotate configured for $domain"
}

# Remove logrotate config for a domain
remove_logrotate() {
    local domain="$1"
    local config_file="/etc/logrotate.d/vhost-${domain}"

    if [[ -f "$config_file" ]]; then
        rm -f "$config_file"
        audit_log "INFO" "Logrotate: removed config for $domain"
        log_info "Logrotate config removed for $domain"
    fi
}

# =============================================================================
# HIGH-LEVEL OPERATIONS
# =============================================================================

# Create a complete virtual host
create_vhost() {
    local domain="$1"
    local aliases="${2:-}"
    local php_version="${3:-$ST_DEFAULT_PHP_VERSION}"
    local custom_docroot="${4:-}"
    local no_welcome="${5:-false}"

    # Validate inputs
    validate_input "$domain" "domain" || return 1
    validate_input "$php_version" "php_version" || return 1

    # Validate aliases
    if [[ -n "$aliases" ]]; then
        local alias
        for alias in $aliases; do
            validate_input "$alias" "domain" || return 1
        done
    fi

    # Check PHP-FPM socket
    if [[ ! -S "/run/php/php${php_version}-fpm.sock" ]]; then
        log_error "PHP ${php_version} FPM is not installed or not running"
        log_info "Installed PHP versions: $(detect_php_versions)"
        return 1
    fi

    # Determine document root
    local docroot
    if [[ -z "$custom_docroot" ]]; then
        docroot="/var/www/${domain}/html"
    else
        validate_input "$custom_docroot" "path" || return 1
        docroot="$custom_docroot"
    fi

    # Check for existing vhost
    if vhost_exists "$domain"; then
        log_warn "Virtual host for '$domain' already exists"
        confirm "Overwrite existing configuration?" || return 1
    fi

    log_info "Creating virtual host for $domain..."
    echo "  DocumentRoot: $docroot"
    echo "  PHP version:  $php_version"

    # Create directory structure
    mkdir -p "$docroot" "/var/www/${domain}/logs"
    chown www-data:www-data "$docroot" "/var/www/${domain}/logs"
    chmod 755 "$docroot"

    # Setup logrotate for domain logs
    setup_logrotate "$domain"

    # Create welcome page
    if [[ "$no_welcome" != "true" ]]; then
        generate_welcome_page "$domain" >"${docroot}/index.php"
        chown www-data:www-data "${docroot}/index.php"
        chmod 644 "${docroot}/index.php"
    fi

    # Write vhost config
    local config
    config=$(generate_vhost_config "$domain" "$aliases" "$php_version" "$docroot")
    safe_write_file "/etc/apache2/sites-available/${domain}.conf" "$config" 640

    # Enable required Apache modules
    a2enmod headers 2>/dev/null || true
    a2enmod proxy_fcgi 2>/dev/null || true

    # Enable site
    enable_site "$domain" || return 1

    # Safe reload
    if ! reload_apache; then
        log_error "Apache reload failed - rolling back..."
        disable_site "$domain"
        return 1
    fi

    audit_log "INFO" "Created virtual host: $domain (PHP $php_version)"
    log_info "Virtual host '$domain' created successfully"
}

# Delete a virtual host
delete_vhost() {
    local domain="$1"

    validate_input "$domain" "domain" || return 1

    if ! vhost_exists "$domain"; then
        log_error "Virtual host '$domain' does not exist"
        return 1
    fi

    local docroot
    docroot=$(get_vhost_docroot "$domain")

    echo "WARNING: Virtual host will be deleted!"
    echo "  Domain:       $domain"
    echo "  DocumentRoot: $docroot"

    # Backup config before deletion
    backup_before_delete "/etc/apache2/sites-available/${domain}.conf" "vhost_${domain}" || return 1

    confirm "Delete virtual host '$domain'?" || {
        echo "Aborted."
        return 1
    }

    # Disable sites
    disable_site "$domain"
    disable_site "${domain}-le-ssl" 2>/dev/null || true

    # Remove config files
    rm -f "/etc/apache2/sites-available/${domain}.conf"
    rm -f "/etc/apache2/sites-available/${domain}-le-ssl.conf"

    # Remove logrotate config
    remove_logrotate "$domain"

    # Optionally remove DocumentRoot
    if [[ -n "$docroot" ]] && [[ -d "$(dirname "$docroot")" ]]; then
        if confirm "Also delete DocumentRoot (/var/www/${domain})?"; then
            if [[ "/var/www/${domain}" =~ ^/var/www/ ]]; then
                rm -rf "/var/www/${domain}"
                log_info "DocumentRoot deleted"
            else
                log_warn "DocumentRoot outside /var/www/ - not deleted for safety"
            fi
        fi
    fi

    reload_apache || log_warn "Apache reload failed"

    audit_log "INFO" "Deleted virtual host: $domain"
    log_info "Virtual host '$domain' deleted"
}

# List virtual hosts
list_vhosts() {
    print_header "Virtual Hosts"

    echo "Active sites:"
    local found=0
    for f in /etc/apache2/sites-enabled/*.conf; do
        [[ -f "$f" ]] || continue
        echo "  - $(basename "$f" .conf)"
        found=1
    done
    [[ $found -eq 0 ]] && echo "  (none)"

    echo ""
    echo "Available sites:"
    found=0
    for f in /etc/apache2/sites-available/*.conf; do
        [[ -f "$f" ]] || continue
        echo "  - $(basename "$f" .conf)"
        found=1
    done
    [[ $found -eq 0 ]] && echo "  (none)"
}

# Change PHP version for an existing vhost
change_php_version() {
    local domain="$1"
    local php_version="$2"

    validate_input "$domain" "domain" || return 1
    validate_input "$php_version" "php_version" || return 1

    local config="/etc/apache2/sites-available/${domain}.conf"
    if [[ ! -f "$config" ]]; then
        log_error "Virtual host '$domain' does not exist"
        return 1
    fi

    if [[ ! -S "/run/php/php${php_version}-fpm.sock" ]]; then
        log_error "PHP ${php_version} FPM is not installed or not running"
        return 1
    fi

    log_info "Changing PHP version for '$domain' to $php_version..."

    # Backup before modification
    if ! cp "$config" "${config}.backup"; then
        log_error "Failed to backup configuration"
        return 1
    fi

    # Replace PHP version in config
    if ! sed -i "s|proxy:unix:/run/php/php[0-9.]*-fpm.sock|proxy:unix:/run/php/php${php_version}-fpm.sock|g" "$config"; then
        log_error "Failed to update configuration"
        mv "${config}.backup" "$config"
        return 1
    fi

    # Safe reload with rollback
    if ! reload_apache; then
        log_error "Apache reload failed - rolling back..."
        mv "${config}.backup" "$config"
        reload_apache || true
        return 1
    fi

    rm -f "${config}.backup"
    audit_log "INFO" "Changed PHP version for $domain to $php_version"
    log_info "PHP version for '$domain' changed to $php_version"
}

# Show info about a single vhost
show_vhost_info() {
    local domain="$1"

    validate_input "$domain" "domain" || return 1

    if ! vhost_exists "$domain"; then
        log_error "Virtual host '$domain' does not exist"
        return 1
    fi

    print_header "Virtual Host: $domain"

    local docroot php_version
    docroot=$(get_vhost_docroot "$domain")
    php_version=$(get_vhost_php_version "$domain")

    echo "  Domain:       $domain"
    echo "  DocumentRoot: ${docroot:-unknown}"
    echo "  PHP version:  ${php_version:-unknown}"

    # Check if SSL is configured
    if [[ -f "/etc/apache2/sites-available/${domain}-le-ssl.conf" ]]; then
        echo "  SSL:          enabled"
    else
        echo "  SSL:          not configured"
    fi

    # Check if site is enabled
    if [[ -L "/etc/apache2/sites-enabled/${domain}.conf" ]]; then
        echo "  Status:       enabled"
    else
        echo "  Status:       disabled"
    fi
}

# =============================================================================
# REDIRECT MANAGEMENT
# =============================================================================

# Generate a redirect vhost config (pure function)
generate_redirect_config() {
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
generate_www_redirect_snippet() {
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
generate_https_redirect_snippet() {
    local domain="$1"

    cat <<HTTPSEOF
    # Force HTTPS redirect
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)\$ https://%{HTTP_HOST}\$1 [R=301,L]
HTTPSEOF
}

# Create a redirect vhost (high-level operation)
create_redirect() {
    local source_domain="$1"
    local target_url="$2"
    local code="${3:-301}"

    validate_input "$source_domain" "domain" || return 1
    validate_input "$target_url" "url" || return 1

    if [[ "$code" != "301" ]] && [[ "$code" != "302" ]]; then
        log_error "Invalid redirect code: $code (must be 301 or 302)"
        return 1
    fi

    local config_file="/etc/apache2/sites-available/${source_domain}.conf"
    if [[ -f "$config_file" ]]; then
        log_error "Config already exists: $config_file"
        return 1
    fi

    log_info "Creating redirect: $source_domain -> $target_url ($code)"

    local config
    config=$(generate_redirect_config "$source_domain" "$target_url" "$code")

    echo "$config" >"$config_file"
    enable_site "$source_domain" || return 1
    reload_apache || return 1

    audit_log "INFO" "Created redirect: $source_domain -> $target_url ($code)"
    log_info "Redirect created successfully"
}

# Add www redirect to existing vhost
add_www_redirect() {
    local domain="$1"
    local direction="${2:-to_www}"

    validate_input "$domain" "domain" || return 1

    local config_file="/etc/apache2/sites-available/${domain}.conf"
    if [[ ! -f "$config_file" ]]; then
        log_error "VHost config not found: $config_file"
        return 1
    fi

    # Check if rewrite module is enabled
    if ! apache2ctl -M 2>/dev/null | grep -q "rewrite_module"; then
        log_info "Enabling rewrite module..."
        a2enmod rewrite &>/dev/null
    fi

    # Backup config
    cp "$config_file" "${config_file}.bak" || return 1

    local snippet
    snippet=$(generate_www_redirect_snippet "$domain" "$direction")

    # Insert snippet before </VirtualHost>
    sed -i "/<\/VirtualHost>/i\\${snippet}" "$config_file"

    reload_apache || {
        log_warn "Apache reload failed, restoring backup..."
        cp "${config_file}.bak" "$config_file"
        reload_apache
        return 1
    }

    rm -f "${config_file}.bak"
    audit_log "INFO" "Added www redirect for $domain ($direction)"
    log_info "WWW redirect added for $domain"
}

# Force HTTPS redirect on existing vhost
force_https() {
    local domain="$1"

    validate_input "$domain" "domain" || return 1

    local config_file="/etc/apache2/sites-available/${domain}.conf"
    if [[ ! -f "$config_file" ]]; then
        log_error "VHost config not found: $config_file"
        return 1
    fi

    # Check if rewrite module is enabled
    if ! apache2ctl -M 2>/dev/null | grep -q "rewrite_module"; then
        log_info "Enabling rewrite module..."
        a2enmod rewrite &>/dev/null
    fi

    # Backup config
    cp "$config_file" "${config_file}.bak" || return 1

    local snippet
    snippet=$(generate_https_redirect_snippet "$domain")

    # Insert snippet before </VirtualHost>
    sed -i "/<\/VirtualHost>/i\\${snippet}" "$config_file"

    reload_apache || {
        log_warn "Apache reload failed, restoring backup..."
        cp "${config_file}.bak" "$config_file"
        reload_apache
        return 1
    }

    rm -f "${config_file}.bak"
    audit_log "INFO" "Added HTTPS redirect for $domain"
    log_info "HTTPS redirect added for $domain"
}
