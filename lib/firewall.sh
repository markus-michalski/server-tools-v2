#!/bin/bash
# Firewall library: UFW firewall management
#
# Architecture: building blocks + high-level operations
# - Building blocks: atomic ufw commands
# - High-level ops: validated operations with audit logging

[[ -n "${_FIREWALL_SOURCED:-}" ]] && return
_FIREWALL_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"
source "${BASH_SOURCE%/*}/config.sh"
source "${BASH_SOURCE%/*}/security.sh"

# =============================================================================
# BUILDING BLOCKS - atomic ufw operations
# =============================================================================

# Check if ufw is installed
ufw_installed() {
    command_exists ufw
}

# Check if ufw is enabled
ufw_is_enabled() {
    ufw status 2>/dev/null | head -1 | grep -q "active"
}

# Get ufw status output
ufw_status() {
    ufw status verbose 2>/dev/null
}

# Allow a port
ufw_allow_port() {
    local port="$1"
    local proto="${2:-}"

    if [[ -n "$proto" ]]; then
        ufw allow "$port/$proto" 2>&1
    else
        ufw allow "$port" 2>&1
    fi
}

# Deny a port
ufw_deny_port() {
    local port="$1"
    local proto="${2:-}"

    if [[ -n "$proto" ]]; then
        ufw deny "$port/$proto" 2>&1
    else
        ufw deny "$port" 2>&1
    fi
}

# Delete a rule by number
ufw_delete_rule() {
    local rule_number="$1"
    echo "y" | ufw delete "$rule_number" 2>&1
}

# =============================================================================
# HIGH-LEVEL OPERATIONS - compose building blocks
# =============================================================================

# Show firewall status
show_firewall_status() {
    if ! ufw_installed; then
        log_error "UFW is not installed. Install with: apt install ufw"
        return 1
    fi

    print_header "Firewall Status"
    ufw_status
}

# Allow a port with validation and logging
allow_port() {
    local port="$1"
    local proto="${2:-}"

    if ! ufw_installed; then
        log_error "UFW is not installed"
        return 1
    fi

    validate_input "$port" "port" || return 1
    if [[ -n "$proto" ]]; then
        validate_input "$proto" "protocol" || return 1
    fi

    local rule_desc="$port"
    [[ -n "$proto" ]] && rule_desc="$port/$proto"

    log_info "Allowing port $rule_desc..."
    ufw_allow_port "$port" "$proto" || {
        log_error "Failed to add allow rule"
        return 1
    }

    audit_log "INFO" "Firewall: allowed port $rule_desc"
    log_info "Port $rule_desc allowed"
}

# Deny a port with validation and logging
deny_port() {
    local port="$1"
    local proto="${2:-}"

    if ! ufw_installed; then
        log_error "UFW is not installed"
        return 1
    fi

    validate_input "$port" "port" || return 1
    if [[ -n "$proto" ]]; then
        validate_input "$proto" "protocol" || return 1
    fi

    local rule_desc="$port"
    [[ -n "$proto" ]] && rule_desc="$port/$proto"

    log_info "Denying port $rule_desc..."
    ufw_deny_port "$port" "$proto" || {
        log_error "Failed to add deny rule"
        return 1
    }

    audit_log "INFO" "Firewall: denied port $rule_desc"
    log_info "Port $rule_desc denied"
}

# Remove a firewall rule
remove_rule() {
    if ! ufw_installed; then
        log_error "UFW is not installed"
        return 1
    fi

    echo "Current rules (numbered):"
    ufw status numbered 2>/dev/null
    echo ""

    local rule_number
    read -r -p "Rule number to delete: " rule_number

    if [[ ! "$rule_number" =~ ^[0-9]+$ ]]; then
        log_error "Invalid rule number"
        return 1
    fi

    confirm "Delete rule $rule_number?" || {
        echo "Aborted."
        return 1
    }

    ufw_delete_rule "$rule_number" || {
        log_error "Failed to delete rule"
        return 1
    }

    audit_log "INFO" "Firewall: deleted rule #$rule_number"
    log_info "Rule deleted"
}

# Enable or disable firewall
toggle_firewall() {
    if ! ufw_installed; then
        log_error "UFW is not installed"
        return 1
    fi

    if ufw_is_enabled; then
        echo "Firewall is currently ENABLED"
        confirm "Disable firewall?" || return 1
        echo "y" | ufw disable 2>&1
        audit_log "INFO" "Firewall: disabled"
        log_info "Firewall disabled"
    else
        echo "Firewall is currently DISABLED"
        echo "WARNING: Ensure SSH (port 22) is allowed before enabling!"
        confirm "Enable firewall?" || return 1
        echo "y" | ufw enable 2>&1
        audit_log "INFO" "Firewall: enabled"
        log_info "Firewall enabled"
    fi
}
