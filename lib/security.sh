#!/bin/bash
# Security library: input validation, escaping, audit logging, password generation

[[ -n "${_SECURITY_SOURCED:-}" ]] && return
_SECURITY_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"
source "${BASH_SOURCE%/*}/config.sh"

# --- Input validation ---
# Validates input against type-specific rules.
# Returns 0 on valid input, 1 on invalid.

validate_input() {
    local input="$1"
    local type="$2"

    case "$type" in
        domain)
            # RFC 1035: labels 1-63 chars, alphanumeric + hyphens, TLD 2+ letters
            if [[ ! "$input" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z]{2,}$ ]]; then
                log_error "Invalid domain name: $input"
                return 1
            fi
            ;;
        database)
            # MySQL identifier: max 64 chars, alphanumeric + underscore
            if [[ ! "$input" =~ ^[a-zA-Z0-9_]{1,64}$ ]]; then
                log_error "Invalid database name: $input (allowed: a-z, 0-9, underscore, max 64 chars)"
                return 1
            fi
            ;;
        username)
            # MySQL user: max 32 chars, alphanumeric + underscore
            if [[ ! "$input" =~ ^[a-zA-Z0-9_]{1,32}$ ]]; then
                log_error "Invalid username: $input (allowed: a-z, 0-9, underscore, max 32 chars)"
                return 1
            fi
            ;;
        path)
            # Path traversal protection: resolve and check against allowed roots
            local normalized
            normalized=$(realpath --canonicalize-missing "$input" 2>/dev/null || echo "")
            if [[ -z "$normalized" ]]; then
                log_error "Invalid path: $input"
                return 1
            fi
            # Check against allowed base paths
            local allowed
            IFS=':' read -ra allowed <<<"$ST_ALLOWED_DOCROOT_PATHS"
            local path_ok=false
            for base in "${allowed[@]}"; do
                # Ensure prefix match uses trailing slash to prevent /var/www-evil matching /var/www
                if [[ "$normalized" == "$base" ]] || [[ "$normalized" == "$base/"* ]]; then
                    path_ok=true
                    break
                fi
            done
            if [[ "$path_ok" != "true" ]]; then
                log_error "Path not under allowed roots ($ST_ALLOWED_DOCROOT_PATHS): $input"
                return 1
            fi
            ;;
        email)
            # Basic RFC 5322 email validation
            if [[ ! "$input" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                log_error "Invalid email address: $input"
                return 1
            fi
            ;;
        password)
            # Length check only (auto-generated passwords are cryptographically secure)
            if [[ ${#input} -lt $ST_PASSWORD_MIN_LENGTH ]]; then
                log_error "Password too short (minimum $ST_PASSWORD_MIN_LENGTH characters)"
                return 1
            fi
            ;;
        php_version)
            # Whitelist of supported PHP-FPM versions
            if [[ ! "$input" =~ ^(7\.4|8\.0|8\.1|8\.2|8\.3|8\.4)$ ]]; then
                log_error "Invalid PHP version: $input (supported: 7.4, 8.0, 8.1, 8.2, 8.3, 8.4)"
                return 1
            fi
            ;;
        cron_schedule)
            # Basic 5-field cron schedule validation
            if [[ ! "$input" =~ ^[0-9/*,-]+[[:space:]]+[0-9/*,-]+[[:space:]]+[0-9/*,-]+[[:space:]]+[0-9/*,-]+[[:space:]]+[0-9/*,-]+$ ]]; then
                log_error "Invalid cron schedule: $input (expected: '* * * * *' format)"
                return 1
            fi
            ;;
        port)
            # Port number: 1-65535
            if [[ ! "$input" =~ ^[0-9]+$ ]] || [[ "$input" -lt 1 ]] || [[ "$input" -gt 65535 ]]; then
                log_error "Invalid port: $input (must be 1-65535)"
                return 1
            fi
            ;;
        protocol)
            # Network protocol: tcp or udp
            if [[ ! "$input" =~ ^(tcp|udp)$ ]]; then
                log_error "Invalid protocol: $input (must be tcp or udp)"
                return 1
            fi
            ;;
        ip_address)
            # IPv4 address validation
            if [[ ! "$input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                log_error "Invalid IP address: $input"
                return 1
            fi
            # Check each octet is 0-255
            local IFS='.'
            local -a octets
            read -ra octets <<<"$input"
            for octet in "${octets[@]}"; do
                if [[ "$octet" -gt 255 ]]; then
                    log_error "Invalid IP address: $input (octet $octet > 255)"
                    return 1
                fi
            done
            ;;
        url)
            # Basic URL validation for redirects
            if [[ ! "$input" =~ ^https?://[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?(/.*)?$ ]]; then
                log_error "Invalid URL: $input"
                return 1
            fi
            ;;
        *)
            log_error "Unknown validation type: $type"
            return 1
            ;;
    esac

    return 0
}

# --- String escaping ---

# Escape string for MySQL queries (backslashes and single quotes)
mysql_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\'/\\\'}"
    echo "$str"
}

# --- Audit logging ---

# Log security-relevant operations
# Usage: audit_log "INFO" "Created database: mydb"
audit_log() {
    [[ "$ST_AUDIT_LOGGING" != "true" ]] && return 0

    local severity="$1"
    shift
    local action="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local user
    user=$(whoami)

    # Create log file if needed
    if [[ ! -f "$ST_AUDIT_LOG" ]]; then
        local log_dir
        log_dir=$(dirname "$ST_AUDIT_LOG")
        [[ ! -d "$log_dir" ]] && mkdir -p "$log_dir"
        touch "$ST_AUDIT_LOG"
        chmod 600 "$ST_AUDIT_LOG"
    fi

    echo "[$timestamp] [$severity] user=$user action=$action" >>"$ST_AUDIT_LOG"

    if [[ "$severity" == "CRITICAL" ]]; then
        log_warn "CRITICAL: $action"
    fi
}

# --- Password generation ---

# Generate a cryptographically secure password (256-bit entropy)
generate_password() {
    local length="${1:-$ST_PASSWORD_LENGTH}"
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-"$length"
}

# --- Safe file operations ---

# Write file with strict permissions (atomic rename, symlink-safe)
safe_write_file() {
    local file_path="$1"
    local content="$2"
    local permissions="${3:-600}"

    # Reject symlinks to prevent TOCTOU attacks
    if [[ -L "$file_path" ]]; then
        log_error "Refusing to write to symlink: $file_path"
        return 1
    fi

    local old_umask
    old_umask=$(umask)
    umask 077

    # Write to temp file, then atomic rename
    local tmp_file
    tmp_file=$(mktemp "${file_path}.XXXXXX")
    echo "$content" >"$tmp_file"
    chmod "$permissions" "$tmp_file"
    mv -f "$tmp_file" "$file_path"

    umask "$old_umask"
}
