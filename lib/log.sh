#!/bin/bash
# Log viewer library: view and search webserver (Apache/Nginx), MySQL, and audit logs
#
# Architecture: building blocks + high-level operations
# - Building blocks: file reading and searching primitives
# - High-level ops: formatted log display with filtering

[[ -n "${_LOG_SOURCED:-}" ]] && return
_LOG_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"
source "${BASH_SOURCE%/*}/config.sh"
source "${BASH_SOURCE%/*}/security.sh"

# =============================================================================
# BUILDING BLOCKS - atomic log operations
# =============================================================================

# Read last N lines from a log file
tail_logfile() {
    local file="$1"
    local lines="${2:-$ST_LOG_LINES}"

    if [[ ! -f "$file" ]]; then
        log_error "Log file not found: $file"
        return 1
    fi

    if [[ ! -r "$file" ]]; then
        log_error "Cannot read log file: $file (permission denied)"
        return 1
    fi

    # Validate lines is a positive integer
    if [[ ! "$lines" =~ ^[0-9]+$ ]] || [[ "$lines" -lt 1 ]]; then
        lines="$ST_LOG_LINES"
    fi

    tail -n "$lines" "$file"
}

# Search a log file for a pattern
grep_logfile() {
    local file="$1"
    local pattern="$2"
    local lines="${3:-$ST_LOG_LINES}"

    # Validate lines is a positive integer
    if [[ ! "$lines" =~ ^[0-9]+$ ]] || [[ "$lines" -lt 1 ]]; then
        lines="$ST_LOG_LINES"
    fi

    if [[ ! -f "$file" ]]; then
        log_error "Log file not found: $file"
        return 1
    fi

    grep -i -e "$pattern" -- "$file" 2>/dev/null | tail -n "$lines"
}

# Global log directory of the active webserver backend ($ST_WEBSERVER)
_webserver_log_dir() {
    if [[ "${ST_WEBSERVER:-apache}" == "nginx" ]]; then
        echo "$ST_NGINX_LOG_DIR"
    else
        echo "$ST_APACHE_LOG_DIR"
    fi
}

# Display name of the active webserver backend
_webserver_label() {
    if [[ "${ST_WEBSERVER:-apache}" == "nginx" ]]; then
        echo "Nginx"
    else
        echo "Apache"
    fi
}

# Get the error log path for a domain
get_webserver_error_log() {
    local domain="${1:-}"
    local log_dir
    log_dir=$(_webserver_log_dir)

    if [[ -n "$domain" ]]; then
        # Domain-specific log (written by both the Apache and Nginx vhost templates)
        local domain_log="/var/www/${domain}/logs/error.log"
        if [[ -f "$domain_log" ]]; then
            echo "$domain_log"
            return 0
        fi
        # Fallback to the webserver's global log dir
        local alt_log="${log_dir}/${domain}-error.log"
        if [[ -f "$alt_log" ]]; then
            echo "$alt_log"
            return 0
        fi
        log_error "No error log found for domain: $domain"
        return 1
    fi

    # Global error log
    echo "${log_dir}/error.log"
}

# Get the access log path for a domain
get_webserver_access_log() {
    local domain="${1:-}"
    local log_dir
    log_dir=$(_webserver_log_dir)

    if [[ -n "$domain" ]]; then
        local domain_log="/var/www/${domain}/logs/access.log"
        if [[ -f "$domain_log" ]]; then
            echo "$domain_log"
            return 0
        fi
        local alt_log="${log_dir}/${domain}-access.log"
        if [[ -f "$alt_log" ]]; then
            echo "$alt_log"
            return 0
        fi
        log_error "No access log found for domain: $domain"
        return 1
    fi

    echo "${log_dir}/access.log"
}

# Backward-compatible names: they follow $ST_WEBSERVER like the neutral ones
get_apache_error_log() { get_webserver_error_log "$@"; }
get_apache_access_log() { get_webserver_access_log "$@"; }

# =============================================================================
# HIGH-LEVEL OPERATIONS - compose building blocks
# =============================================================================

# Show webserver (Apache or Nginx, per $ST_WEBSERVER) error log entries
show_webserver_errors() {
    local domain="${1:-}"
    local lines="${2:-$ST_LOG_LINES}"
    local label
    label=$(_webserver_label)

    local log_file
    log_file=$(get_webserver_error_log "$domain") || return 1

    if [[ -n "$domain" ]]; then
        print_header "$label Errors: $domain"
    else
        print_header "$label Errors (global)"
    fi

    echo "File: $log_file"
    echo "Last $lines entries:"
    echo "---"
    tail_logfile "$log_file" "$lines" || echo "  (no entries)"
}

# Show webserver (Apache or Nginx, per $ST_WEBSERVER) access log entries
show_webserver_access() {
    local domain="${1:-}"
    local lines="${2:-$ST_LOG_LINES}"
    local label
    label=$(_webserver_label)

    local log_file
    log_file=$(get_webserver_access_log "$domain") || return 1

    if [[ -n "$domain" ]]; then
        print_header "$label Access: $domain"
    else
        print_header "$label Access (global)"
    fi

    echo "File: $log_file"
    echo "Last $lines entries:"
    echo "---"
    tail_logfile "$log_file" "$lines" || echo "  (no entries)"
}

# Backward-compatible names: they follow $ST_WEBSERVER like the neutral ones
show_apache_errors() { show_webserver_errors "$@"; }
show_apache_access() { show_webserver_access "$@"; }

# Show MySQL error log
show_mysql_errors() {
    local lines="${1:-$ST_LOG_LINES}"

    print_header "MySQL Errors"
    echo "File: $ST_MYSQL_LOG_FILE"
    echo "Last $lines entries:"
    echo "---"
    tail_logfile "$ST_MYSQL_LOG_FILE" "$lines" || echo "  (no entries or file not found)"
}

# Show server-tools audit log
show_audit_log_entries() {
    local lines="${1:-$ST_LOG_LINES}"
    local filter="${2:-}"

    print_header "Audit Log"
    echo "File: $ST_AUDIT_LOG"

    if [[ ! -f "$ST_AUDIT_LOG" ]]; then
        echo "  (no audit log found)"
        return 0
    fi

    if [[ -n "$filter" ]]; then
        echo "Filter: $filter"
        echo "---"
        grep_logfile "$ST_AUDIT_LOG" "$filter" "$lines"
    else
        echo "Last $lines entries:"
        echo "---"
        tail_logfile "$ST_AUDIT_LOG" "$lines"
    fi
}

# Search across multiple log files
search_logs() {
    local pattern="$1"
    local lines="${2:-$ST_LOG_LINES}"

    if [[ -z "$pattern" ]]; then
        log_error "Search pattern is required"
        return 1
    fi

    print_header "Log Search: $pattern"

    local found=0

    # Webserver error log (Apache or Nginx, per $ST_WEBSERVER)
    local webserver_error
    webserver_error="$(_webserver_log_dir)/error.log"
    if [[ -f "$webserver_error" ]]; then
        local results
        results=$(grep_logfile "$webserver_error" "$pattern" "$lines")
        if [[ -n "$results" ]]; then
            echo "--- $(_webserver_label) Error Log ---"
            echo "$results"
            echo ""
            found=1
        fi
    fi

    # MySQL error log
    if [[ -f "$ST_MYSQL_LOG_FILE" ]]; then
        local results
        results=$(grep_logfile "$ST_MYSQL_LOG_FILE" "$pattern" "$lines")
        if [[ -n "$results" ]]; then
            echo "--- MySQL Error Log ---"
            echo "$results"
            echo ""
            found=1
        fi
    fi

    # Audit log
    if [[ -f "$ST_AUDIT_LOG" ]]; then
        local results
        results=$(grep_logfile "$ST_AUDIT_LOG" "$pattern" "$lines")
        if [[ -n "$results" ]]; then
            echo "--- Audit Log ---"
            echo "$results"
            echo ""
            found=1
        fi
    fi

    if [[ $found -eq 0 ]]; then
        echo "No matches found for: $pattern"
    fi
}
