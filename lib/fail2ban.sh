#!/bin/bash
# Fail2Ban library: jail status and IP ban management
#
# Architecture: building blocks + high-level operations
# - Building blocks: fail2ban-client wrappers
# - High-level ops: formatted status displays and ban management

[[ -n "${_FAIL2BAN_SOURCED:-}" ]] && return
_FAIL2BAN_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"
source "${BASH_SOURCE%/*}/config.sh"
source "${BASH_SOURCE%/*}/security.sh"

# =============================================================================
# BUILDING BLOCKS - atomic fail2ban operations
# =============================================================================

# Check if fail2ban is installed
fail2ban_installed() {
    command_exists fail2ban-client
}

# Get list of active jails
get_active_jails() {
    fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*:\s*//' | tr ',' '\n' | sed 's/^[[:space:]]*//'
}

# Get status of a specific jail
get_jail_status() {
    local jail="$1"
    fail2ban-client status "$jail" 2>/dev/null
}

# Get banned IPs from a jail
get_banned_ips() {
    local jail="$1"
    fail2ban-client status "$jail" 2>/dev/null | grep "Banned IP list" | sed 's/.*:\s*//'
}

# Unban an IP from a specific jail
unban_ip_from_jail() {
    local jail="$1"
    local ip="$2"
    fail2ban-client set "$jail" unbanip "$ip" 2>&1
}

# =============================================================================
# HIGH-LEVEL OPERATIONS - compose building blocks
# =============================================================================

# Show overall Fail2Ban status
show_fail2ban_status() {
    if ! fail2ban_installed; then
        log_error "Fail2Ban is not installed. Install with: apt install fail2ban"
        return 1
    fi

    print_header "Fail2Ban Status"

    local jails
    jails=$(get_active_jails)

    if [[ -z "$jails" ]]; then
        echo "  No active jails"
        return 0
    fi

    for jail in $jails; do
        local status
        status=$(get_jail_status "$jail")
        local currently_banned
        currently_banned=$(echo "$status" | grep "Currently banned" | awk '{print $NF}')
        local total_banned
        total_banned=$(echo "$status" | grep "Total banned" | awk '{print $NF}')

        printf "  %-20s currently: %-4s total: %s\n" "$jail" "${currently_banned:-0}" "${total_banned:-0}"
    done
}

# Show all banned IPs across all jails
show_banned() {
    if ! fail2ban_installed; then
        log_error "Fail2Ban is not installed"
        return 1
    fi

    print_header "Banned IPs"

    local jails
    jails=$(get_active_jails)

    if [[ -z "$jails" ]]; then
        echo "  No active jails"
        return 0
    fi

    local found=0
    for jail in $jails; do
        local ips
        ips=$(get_banned_ips "$jail")
        if [[ -n "$ips" ]]; then
            echo "  [$jail]"
            for ip in $ips; do
                echo "    - $ip"
            done
            found=1
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo "  No IPs currently banned"
    fi
}

# Unban an IP address
unban_ip() {
    local ip="$1"

    if ! fail2ban_installed; then
        log_error "Fail2Ban is not installed"
        return 1
    fi

    validate_input "$ip" "ip_address" || return 1

    # Find which jails have this IP banned
    local jails
    jails=$(get_active_jails)
    local found_in=""

    for jail in $jails; do
        local ips
        ips=$(get_banned_ips "$jail")
        if echo "$ips" | grep -qw "$ip"; then
            found_in="$found_in $jail"
        fi
    done

    if [[ -z "$found_in" ]]; then
        log_error "IP '$ip' is not currently banned in any jail"
        return 1
    fi

    echo "IP '$ip' is banned in:$found_in"
    confirm "Unban IP '$ip' from all jails?" || {
        echo "Aborted."
        return 1
    }

    for jail in $found_in; do
        log_info "Unbanning '$ip' from jail '$jail'..."
        unban_ip_from_jail "$jail" "$ip" || log_warn "Failed to unban from $jail"
    done

    audit_log "INFO" "Fail2Ban: unbanned IP $ip from$found_in"
    log_info "IP '$ip' unbanned"
}
