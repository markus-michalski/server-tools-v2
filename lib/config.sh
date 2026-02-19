#!/bin/bash
# Config library: configuration loading, validation, and defaults
# All configurable values use the ST_ prefix.

[[ -n "${_CONFIG_SOURCED:-}" ]] && return
_CONFIG_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"

# --- Default configuration values ---

# Paths
ST_CREDENTIAL_DIR="${ST_CREDENTIAL_DIR:-/root/db-credentials}"
ST_AUDIT_LOG="${ST_AUDIT_LOG:-/var/log/server-tools-audit.log}"
ST_BACKUP_DIR="${ST_BACKUP_DIR:-/root/server-tools-backups}"
ST_CONFIG_FILE="${ST_CONFIG_FILE:-/etc/server-tools/config}"

# PHP
ST_DEFAULT_PHP_VERSION="${ST_DEFAULT_PHP_VERSION:-8.3}"
ST_PHP_VERSIONS_TO_SCAN="${ST_PHP_VERSIONS_TO_SCAN:-7.4 8.0 8.1 8.2 8.3 8.4}"

# MySQL
ST_MYSQL_CONFIG_FILE="${ST_MYSQL_CONFIG_FILE:-/root/.my.cnf}"
ST_DEFAULT_CHARSET="${ST_DEFAULT_CHARSET:-utf8mb4}"
ST_DEFAULT_COLLATION="${ST_DEFAULT_COLLATION:-utf8mb4_unicode_ci}"

# Passwords
ST_PASSWORD_LENGTH="${ST_PASSWORD_LENGTH:-25}"
ST_PASSWORD_MIN_LENGTH="${ST_PASSWORD_MIN_LENGTH:-12}"

# Apache
ST_APACHE_SERVER_ADMIN="${ST_APACHE_SERVER_ADMIN:-webmaster@localhost}"
ST_DEFAULT_DOCROOT_PATTERN="${ST_DEFAULT_DOCROOT_PATTERN:-/var/www/{domain}/html}"

# Backup & Safety
ST_AUTO_BACKUP="${ST_AUTO_BACKUP:-true}"
ST_BACKUP_RETENTION_DAYS="${ST_BACKUP_RETENTION_DAYS:-30}"

# Database backups
ST_DB_BACKUP_DIR="${ST_DB_BACKUP_DIR:-/root/db-backups}"

# SSL / Certbot
ST_CERTBOT_EMAIL="${ST_CERTBOT_EMAIL:-}"
ST_DNS_PROVIDER="${ST_DNS_PROVIDER:-}"
ST_DNS_CREDENTIALS_FILE="${ST_DNS_CREDENTIALS_FILE:-}"

# Logrotate
ST_LOGROTATE_DAYS="${ST_LOGROTATE_DAYS:-14}"
ST_LOGROTATE_ROTATE="${ST_LOGROTATE_ROTATE:-52}"

# Logs
ST_APACHE_LOG_DIR="${ST_APACHE_LOG_DIR:-/var/log/apache2}"
ST_MYSQL_LOG_FILE="${ST_MYSQL_LOG_FILE:-/var/log/mysql/error.log}"
ST_LOG_LINES="${ST_LOG_LINES:-50}"

# Security
ST_ALLOWED_DOCROOT_PATHS="${ST_ALLOWED_DOCROOT_PATHS:-/var/www:/srv/www}"
ST_CREDENTIAL_FILE_PERMISSIONS="${ST_CREDENTIAL_FILE_PERMISSIONS:-600}"
ST_AUDIT_LOGGING="${ST_AUDIT_LOGGING:-true}"

# --- Functions ---

# Load configuration from file
load_config() {
    local config_file="${ST_CONFIG_FILE}"

    if [[ ! -f "$config_file" ]]; then
        log_debug "No config file found at $config_file, using defaults"
        return 0
    fi

    # Check file permissions
    local perms
    perms=$(stat -c '%a' "$config_file" 2>/dev/null || stat -f '%A' "$config_file" 2>/dev/null)
    if [[ "${perms: -1}" =~ [4-7] ]]; then
        log_warn "Config file is world-readable: $config_file (permissions: $perms)"
        log_warn "Recommendation: chmod 600 $config_file"
    fi

    # Source the config file
    # shellcheck source=/dev/null
    source "$config_file"

    validate_config
}

# Validate configuration values
validate_config() {
    # Password length bounds
    if [[ "$ST_PASSWORD_LENGTH" -lt 12 ]] || [[ "$ST_PASSWORD_LENGTH" -gt 64 ]]; then
        log_warn "ST_PASSWORD_LENGTH should be between 12 and 64, got: $ST_PASSWORD_LENGTH. Resetting to 25."
        ST_PASSWORD_LENGTH=25
    fi

    if [[ "$ST_PASSWORD_MIN_LENGTH" -lt 8 ]]; then
        log_warn "ST_PASSWORD_MIN_LENGTH should be at least 8, got: $ST_PASSWORD_MIN_LENGTH. Resetting to 12."
        ST_PASSWORD_MIN_LENGTH=12
    fi

    # Backup retention bounds
    if [[ "$ST_BACKUP_RETENTION_DAYS" -lt 1 ]] || [[ "$ST_BACKUP_RETENTION_DAYS" -gt 365 ]]; then
        log_warn "ST_BACKUP_RETENTION_DAYS should be between 1 and 365, got: $ST_BACKUP_RETENTION_DAYS. Resetting to 30."
        ST_BACKUP_RETENTION_DAYS=30
    fi
}

# Display current configuration
show_config() {
    print_header "Current Configuration"

    echo "Paths:"
    echo "  Credentials:   $ST_CREDENTIAL_DIR"
    echo "  Audit log:     $ST_AUDIT_LOG"
    echo "  Backups:       $ST_BACKUP_DIR"
    echo "  DB backups:    $ST_DB_BACKUP_DIR"
    echo "  Config file:   $ST_CONFIG_FILE"
    echo ""
    echo "Defaults:"
    echo "  PHP version:   $ST_DEFAULT_PHP_VERSION"
    echo "  DB charset:    $ST_DEFAULT_CHARSET / $ST_DEFAULT_COLLATION"
    echo ""
    echo "Passwords:"
    echo "  Auto length:   $ST_PASSWORD_LENGTH"
    echo "  Min length:    $ST_PASSWORD_MIN_LENGTH"
    echo ""
    echo "Features:"
    echo "  Auto-backup:   $ST_AUTO_BACKUP"
    echo "  Audit logging: $ST_AUDIT_LOGGING"
    echo ""

    if [[ -f "$ST_CONFIG_FILE" ]]; then
        echo "Config file:     loaded from $ST_CONFIG_FILE"
    else
        echo "Config file:     not found (using defaults)"
    fi
}
