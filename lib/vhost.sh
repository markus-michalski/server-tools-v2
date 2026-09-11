#!/bin/bash
# VHost library: composable virtual host management (Apache or Nginx) with PHP-FPM
#
# This file is webserver-agnostic: input validation, directory creation,
# confirmation prompts, rollback-on-failure, logrotate setup, and audit
# logging all live here. Webserver-specific mechanics (config file syntax,
# enabling/disabling sites, reload/config-test) live in lib/webserver/apache.sh
# and lib/webserver/nginx.sh, selected at runtime via $ST_WEBSERVER and
# dispatched through _ws_dispatch().

[[ -n "${_VHOST_SOURCED:-}" ]] && return
_VHOST_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"
source "${BASH_SOURCE%/*}/config.sh"
source "${BASH_SOURCE%/*}/security.sh"
source "${BASH_SOURCE%/*}/backup.sh"
source "${BASH_SOURCE%/*}/webserver/apache.sh"
source "${BASH_SOURCE%/*}/webserver/nginx.sh"

# Dispatch to the configured webserver backend's implementation of $1, called
# with the remaining arguments. E.g. `_ws_dispatch generate_vhost_config "$domain" ...`
# calls `apache_generate_vhost_config "$domain" ...` or `nginx_generate_vhost_config ...`
# depending on $ST_WEBSERVER.
_ws_dispatch() {
    local fn="$1"
    shift
    case "${ST_WEBSERVER:-apache}" in
        nginx) "nginx_${fn}" "$@" ;;
        *) "apache_${fn}" "$@" ;;
    esac
}

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

# =============================================================================
# LOGROTATE - pure functions + operations
# =============================================================================

# Generate logrotate config for a domain (pure function)
#
# The postrotate reload command must be baked in as static text here, at
# generation time: logrotate runs this file later, asynchronously via cron,
# when $ST_WEBSERVER (a live bash variable in *this* process) no longer
# exists to look up. Pick the backend-appropriate pid-check + reload command
# now, once, based on $ST_WEBSERVER at the time the vhost is created.
generate_logrotate_config() {
    local domain="$1"
    local log_dir="/var/www/${domain}/logs"
    local pid_check reload_cmd
    if [[ "${ST_WEBSERVER:-apache}" == "nginx" ]]; then
        pid_check="/var/run/nginx.pid"
        reload_cmd="systemctl reload nginx"
    else
        pid_check="/var/run/apache2/apache2.pid"
        reload_cmd="systemctl reload apache2"
    fi

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
        if [ -f ${pid_check} ]; then
            ${reload_cmd} > /dev/null 2>&1 || true
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

# Create a complete virtual host (PHP-FPM or Reverse Proxy)
create_vhost() {
    local domain="$1"
    local aliases="${2:-}"
    local php_version="${3:-$ST_DEFAULT_PHP_VERSION}"
    local custom_docroot="${4:-}"
    local no_welcome="${5:-false}"
    local vhost_type="${6:-php}"
    local backend_url="${7:-}"
    local websocket="${8:-false}"
    local preserve_host="${9:-$ST_PROXY_PRESERVE_HOST}"

    # Validate inputs
    validate_input "$domain" "domain" || return 1

    # Validate aliases
    if [[ -n "$aliases" ]]; then
        local alias
        for alias in $aliases; do
            validate_input "$alias" "domain" || return 1
        done
    fi

    # Type-specific validation
    if [[ "$vhost_type" == "proxy" ]]; then
        if [[ -z "$backend_url" ]]; then
            log_error "Backend URL is required for proxy vhosts (--backend)"
            return 1
        fi
        validate_input "$backend_url" "url" || return 1
    else
        validate_input "$php_version" "php_version" || return 1

        # Check PHP-FPM socket
        if [[ ! -S "/run/php/php${php_version}-fpm.sock" ]]; then
            log_error "PHP ${php_version} FPM is not installed or not running"
            log_info "Installed PHP versions: $(detect_php_versions)"
            return 1
        fi
    fi

    # Check for existing vhost
    if _ws_dispatch vhost_exists "$domain"; then
        log_warn "Virtual host for '$domain' already exists"
        confirm "Overwrite existing configuration?" || return 1
    fi

    # Proxy mode: no DocumentRoot needed, only logs directory
    if [[ "$vhost_type" == "proxy" ]]; then
        log_info "Creating reverse proxy vhost for $domain..."
        echo "  Type:     reverse proxy"
        echo "  Backend:  $backend_url"
        echo "  WebSocket: $websocket"

        # Only create logs directory
        mkdir -p "/var/www/${domain}/logs"
        chown www-data:www-data "/var/www/${domain}/logs"

        # Setup logrotate for domain logs
        setup_logrotate "$domain"

        # Write proxy vhost config
        local config
        config=$(_ws_dispatch generate_proxy_config "$domain" "$aliases" "$backend_url" "$websocket" "$preserve_host")
        safe_write_file "$(_ws_dispatch vhost_config_path "$domain")" "$config" 640

        # Enable required webserver modules
        _ws_dispatch enable_modules_proxy "$websocket"
    else
        # Determine document root
        local docroot
        if [[ -z "$custom_docroot" ]]; then
            docroot="/var/www/${domain}/html"
        else
            validate_input "$custom_docroot" "path" || return 1
            docroot="$custom_docroot"
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
        config=$(_ws_dispatch generate_vhost_config "$domain" "$aliases" "$php_version" "$docroot")
        safe_write_file "$(_ws_dispatch vhost_config_path "$domain")" "$config" 640

        # Enable required webserver modules
        _ws_dispatch enable_modules_php
    fi

    # Enable site
    _ws_dispatch enable_site "$domain" || return 1

    # Safe reload
    if ! _ws_dispatch reload; then
        log_error "Webserver reload failed - rolling back..."
        _ws_dispatch disable_site "$domain"
        return 1
    fi

    if [[ "$vhost_type" == "proxy" ]]; then
        audit_log "INFO" "Created proxy vhost: $domain -> $backend_url"
        log_info "Proxy vhost '$domain' -> '$backend_url' created successfully"
    else
        audit_log "INFO" "Created virtual host: $domain (PHP $php_version)"
        log_info "Virtual host '$domain' created successfully"
    fi
}

# Delete a virtual host
delete_vhost() {
    local domain="$1"

    validate_input "$domain" "domain" || return 1

    if ! _ws_dispatch vhost_exists "$domain"; then
        log_error "Virtual host '$domain' does not exist"
        return 1
    fi

    # Block deletion if a domain user is assigned
    if command_exists getent; then
        local domain_user
        domain_user=$(getent passwd | awk -F: -v home="/var/www/${domain}" '$6 == home && $3 >= 1000 { print $1; exit }')
        if [[ -n "$domain_user" ]]; then
            log_error "Domain '$domain' has assigned user '$domain_user'."
            log_error "Delete user first: server-tools user delete --username $domain_user"
            return 1
        fi
    fi

    local docroot
    docroot=$(_ws_dispatch get_vhost_docroot "$domain")

    echo "WARNING: Virtual host will be deleted!"
    echo "  Domain:       $domain"
    echo "  DocumentRoot: $docroot"

    # Backup config before deletion
    backup_before_delete "$(_ws_dispatch vhost_config_path "$domain")" "vhost_${domain}" || return 1

    confirm "Delete virtual host '$domain'?" || {
        echo "Aborted."
        return 1
    }

    # Disable site
    _ws_dispatch disable_site "$domain"

    # SSL site disable + config removal is Apache/certbot-specific: certbot
    # --apache splits SSL into a separate "<domain>-le-ssl.conf" file with its
    # own sites-enabled symlink. Nginx SSL/certbot integration isn't wired up
    # yet (tracked as follow-up work), so there's no equivalent file on nginx.
    if [[ "${ST_WEBSERVER:-apache}" == "apache" ]]; then
        apache_disable_site "${domain}-le-ssl" 2>/dev/null || true
    fi

    # Remove config files
    rm -f "$(_ws_dispatch vhost_config_path "$domain")"
    if [[ "${ST_WEBSERVER:-apache}" == "apache" ]]; then
        rm -f "${ST_APACHE_SITES_AVAILABLE}/${domain}-le-ssl.conf"
    fi

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

    _ws_dispatch reload || log_warn "Webserver reload failed"

    audit_log "INFO" "Deleted virtual host: $domain"
    log_info "Virtual host '$domain' deleted"
}

# List virtual hosts
list_vhosts() {
    print_header "Virtual Hosts"

    # Directory layout (and filename convention: Apache uses "<domain>.conf",
    # Debian's nginx convention uses the bare "<domain>") differs enough
    # between backends that a single glob can't express both -- branch here
    # rather than inventing a new _ws_dispatch abstraction for one caller.
    if [[ "${ST_WEBSERVER:-apache}" == "nginx" ]]; then
        echo "Active sites:"
        local found=0
        for f in "${ST_NGINX_SITES_ENABLED}"/*; do
            [[ -f "$f" ]] || continue
            echo "  - $(basename "$f")"
            found=1
        done
        [[ $found -eq 0 ]] && echo "  (none)"

        echo ""
        echo "Available sites:"
        found=0
        for f in "${ST_NGINX_SITES_AVAILABLE}"/*; do
            [[ -f "$f" ]] || continue
            echo "  - $(basename "$f")"
            found=1
        done
        [[ $found -eq 0 ]] && echo "  (none)"
    else
        echo "Active sites:"
        local found=0
        for f in "${ST_APACHE_SITES_ENABLED}"/*.conf; do
            [[ -f "$f" ]] || continue
            echo "  - $(basename "$f" .conf)"
            found=1
        done
        [[ $found -eq 0 ]] && echo "  (none)"

        echo ""
        echo "Available sites:"
        found=0
        for f in "${ST_APACHE_SITES_AVAILABLE}"/*.conf; do
            [[ -f "$f" ]] || continue
            echo "  - $(basename "$f" .conf)"
            found=1
        done
        [[ $found -eq 0 ]] && echo "  (none)"
    fi
}

# Change PHP version for an existing vhost
change_php_version() {
    local domain="$1"
    local php_version="$2"

    validate_input "$domain" "domain" || return 1
    validate_input "$php_version" "php_version" || return 1

    local config
    config=$(_ws_dispatch vhost_config_path "$domain")
    if [[ ! -f "$config" ]]; then
        log_error "Virtual host '$domain' does not exist"
        return 1
    fi

    if [[ ! -S "/run/php/php${php_version}-fpm.sock" ]]; then
        log_error "PHP ${php_version} FPM is not installed or not running"
        return 1
    fi

    log_info "Changing PHP version for '$domain' to $php_version..."

    # Backup to temp dir (not in webserver config dir to avoid stale .backup files)
    local config_backup
    config_backup=$(mktemp "/tmp/vhost-backup-XXXXXX")
    if ! cp "$config" "$config_backup"; then
        log_error "Failed to backup configuration"
        rm -f "$config_backup"
        return 1
    fi

    # Replace PHP version in config
    if ! _ws_dispatch change_php_version_in_config "$config" "$php_version"; then
        log_error "Failed to update configuration"
        cp "$config_backup" "$config"
        rm -f "$config_backup"
        return 1
    fi

    # Safe reload with rollback
    if ! _ws_dispatch reload; then
        log_error "Webserver reload failed - rolling back..."
        cp "$config_backup" "$config"
        rm -f "$config_backup"
        _ws_dispatch reload || true
        return 1
    fi

    rm -f "$config_backup"
    audit_log "INFO" "Changed PHP version for $domain to $php_version"
    log_info "PHP version for '$domain' changed to $php_version"
}

# Show info about a single vhost
show_vhost_info() {
    local domain="$1"

    validate_input "$domain" "domain" || return 1

    if ! _ws_dispatch vhost_exists "$domain"; then
        log_error "Virtual host '$domain' does not exist"
        return 1
    fi

    print_header "Virtual Host: $domain"

    local vtype
    vtype=$(_ws_dispatch get_vhost_type "$domain")

    echo "  Domain:       $domain"
    echo "  Type:         ${vtype:-unknown}"

    if [[ "$vtype" == "proxy" ]]; then
        local backend
        backend=$(_ws_dispatch get_vhost_backend "$domain")
        echo "  Backend:      ${backend:-unknown}"

        # Check for WebSocket support
        if _ws_dispatch websocket_enabled "$domain"; then
            echo "  WebSocket:    enabled"
        else
            echo "  WebSocket:    disabled"
        fi
    else
        local docroot php_version
        docroot=$(_ws_dispatch get_vhost_docroot "$domain")
        php_version=$(_ws_dispatch get_vhost_php_version "$domain")
        echo "  DocumentRoot: ${docroot:-unknown}"
        echo "  PHP version:  ${php_version:-unknown}"
    fi

    # Check if SSL is configured. SSL/certbot integration only exists for
    # Apache today (see lib/ssl.sh) -- be honest about that on nginx rather
    # than printing a possibly-wrong "not configured".
    if [[ "${ST_WEBSERVER:-apache}" == "apache" ]]; then
        if [[ -f "${ST_APACHE_SITES_AVAILABLE}/${domain}-le-ssl.conf" ]]; then
            echo "  SSL:          enabled"
        else
            echo "  SSL:          not configured"
        fi
    else
        echo "  SSL:          not applicable (nginx)"
    fi

    # Check if site is enabled
    if _ws_dispatch vhost_enabled "$domain"; then
        echo "  Status:       enabled"
    else
        echo "  Status:       disabled"
    fi
}

# =============================================================================
# REDIRECT MANAGEMENT
# =============================================================================

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

    local config_file
    config_file=$(_ws_dispatch vhost_config_path "$source_domain")
    if [[ -f "$config_file" ]]; then
        log_error "Config already exists: $config_file"
        return 1
    fi

    log_info "Creating redirect: $source_domain -> $target_url ($code)"

    local config
    config=$(_ws_dispatch generate_redirect_config "$source_domain" "$target_url" "$code")

    safe_write_file "$config_file" "$config" 644
    _ws_dispatch enable_site "$source_domain" || return 1
    _ws_dispatch reload || return 1

    audit_log "INFO" "Created redirect: $source_domain -> $target_url ($code)"
    log_info "Redirect created successfully"
}

# Add www redirect to existing vhost
add_www_redirect() {
    local domain="$1"
    local direction="${2:-to_www}"

    validate_input "$domain" "domain" || return 1

    local config_file
    config_file=$(_ws_dispatch vhost_config_path "$domain")
    if [[ ! -f "$config_file" ]]; then
        log_error "VHost config not found: $config_file"
        return 1
    fi

    # Ensure the rewrite-equivalent capability is available (no-op on nginx)
    _ws_dispatch rewrite_module_ensure

    # Backup to temp dir (not in webserver config dir to avoid stale .bak files)
    local config_backup
    config_backup=$(mktemp "/tmp/vhost-backup-XXXXXX")
    cp "$config_file" "$config_backup" || {
        rm -f "$config_backup"
        return 1
    }

    local snippet
    snippet=$(_ws_dispatch generate_www_redirect_snippet "$domain" "$direction")

    # Insert snippet before the config's closing tag. Function names differ
    # between backends (apache_insert_before_close vs.
    # nginx_insert_before_server_close), so branch inline rather than forcing
    # this through _ws_dispatch's shared-suffix convention.
    if [[ "${ST_WEBSERVER:-apache}" == "nginx" ]]; then
        nginx_insert_before_server_close "$config_file" "$snippet"
    else
        apache_insert_before_close "$config_file" "$snippet"
    fi

    _ws_dispatch reload || {
        log_warn "Webserver reload failed, restoring backup..."
        cp "$config_backup" "$config_file"
        rm -f "$config_backup"
        _ws_dispatch reload
        return 1
    }

    rm -f "$config_backup"
    audit_log "INFO" "Added www redirect for $domain ($direction)"
    log_info "WWW redirect added for $domain"
}

# Force HTTPS redirect on existing vhost
force_https() {
    local domain="$1"

    validate_input "$domain" "domain" || return 1

    local config_file
    config_file=$(_ws_dispatch vhost_config_path "$domain")
    if [[ ! -f "$config_file" ]]; then
        log_error "VHost config not found: $config_file"
        return 1
    fi

    # Ensure the rewrite-equivalent capability is available (no-op on nginx)
    _ws_dispatch rewrite_module_ensure

    # Backup to temp dir (not in webserver config dir to avoid stale .bak files)
    local config_backup
    config_backup=$(mktemp "/tmp/vhost-backup-XXXXXX")
    cp "$config_file" "$config_backup" || {
        rm -f "$config_backup"
        return 1
    }

    local snippet
    snippet=$(_ws_dispatch generate_https_redirect_snippet "$domain")

    # See add_www_redirect for why this is an inline branch, not _ws_dispatch.
    if [[ "${ST_WEBSERVER:-apache}" == "nginx" ]]; then
        nginx_insert_before_server_close "$config_file" "$snippet"
    else
        apache_insert_before_close "$config_file" "$snippet"
    fi

    _ws_dispatch reload || {
        log_warn "Webserver reload failed, restoring backup..."
        cp "$config_backup" "$config_file"
        rm -f "$config_backup"
        _ws_dispatch reload
        return 1
    }

    rm -f "$config_backup"
    audit_log "INFO" "Added HTTPS redirect for $domain"
    log_info "HTTPS redirect added for $domain"
}
