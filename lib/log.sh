#!/bin/bash
# Log viewer library: view and search Apache, MySQL, and audit logs
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

# Get the error log path for a domain
get_apache_error_log() {
    local domain="${1:-}"

    if [[ -n "$domain" ]]; then
        # Domain-specific log
        local domain_log="/var/www/${domain}/logs/error.log"
        if [[ -f "$domain_log" ]]; then
            echo "$domain_log"
            return 0
        fi
        # Fallback to apache log dir
        local alt_log="${ST_APACHE_LOG_DIR}/${domain}-error.log"
        if [[ -f "$alt_log" ]]; then
            echo "$alt_log"
            return 0
        fi
        log_error "No error log found for domain: $domain"
        return 1
    fi

    # Global error log
    echo "${ST_APACHE_LOG_DIR}/error.log"
}

# Get the access log path for a domain
get_apache_access_log() {
    local domain="${1:-}"

    if [[ -n "$domain" ]]; then
        local domain_log="/var/www/${domain}/logs/access.log"
        if [[ -f "$domain_log" ]]; then
            echo "$domain_log"
            return 0
        fi
        local alt_log="${ST_APACHE_LOG_DIR}/${domain}-access.log"
        if [[ -f "$alt_log" ]]; then
            echo "$alt_log"
            return 0
        fi
        log_error "No access log found for domain: $domain"
        return 1
    fi

    echo "${ST_APACHE_LOG_DIR}/access.log"
}

# =============================================================================
# HIGH-LEVEL OPERATIONS - compose building blocks
# =============================================================================

# Show Apache error log entries
show_apache_errors() {
    local domain="${1:-}"
    local lines="${2:-$ST_LOG_LINES}"

    local log_file
    log_file=$(get_apache_error_log "$domain") || return 1

    if [[ -n "$domain" ]]; then
        print_header "Apache Errors: $domain"
    else
        print_header "Apache Errors (global)"
    fi

    echo "File: $log_file"
    echo "Last $lines entries:"
    echo "---"
    tail_logfile "$log_file" "$lines" || echo "  (no entries)"
}

# Show Apache access log entries
show_apache_access() {
    local domain="${1:-}"
    local lines="${2:-$ST_LOG_LINES}"

    local log_file
    log_file=$(get_apache_access_log "$domain") || return 1

    if [[ -n "$domain" ]]; then
        print_header "Apache Access: $domain"
    else
        print_header "Apache Access (global)"
    fi

    echo "File: $log_file"
    echo "Last $lines entries:"
    echo "---"
    tail_logfile "$log_file" "$lines" || echo "  (no entries)"
}

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

    # Apache error log
    local apache_error="${ST_APACHE_LOG_DIR}/error.log"
    if [[ -f "$apache_error" ]]; then
        local results
        results=$(grep_logfile "$apache_error" "$pattern" "$lines")
        if [[ -n "$results" ]]; then
            echo "--- Apache Error Log ---"
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
