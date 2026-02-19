#!/bin/bash
# User library: per-domain SSH user management with ACL-based isolation
#
# Building blocks: atomic functions for user creation, ACL management, SSH setup
# High-level ops: create/delete/list/manage domain users
#
# Design: 1:1 mapping between user and domain. Multiple devs share one user
# with separate SSH keys. Isolation via POSIX ACLs (no chroot).

[[ -n "${_USER_SOURCED:-}" ]] && return
_USER_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"
source "${BASH_SOURCE%/*}/config.sh"
source "${BASH_SOURCE%/*}/security.sh"
source "${BASH_SOURCE%/*}/vhost.sh"

# =============================================================================
# BUILDING BLOCKS
# =============================================================================

# Check if a Linux system user exists
linux_user_exists() {
    local username="$1"
    getent passwd "$username" &>/dev/null
}

# Derive domain from a user's home directory
# Convention: home=/var/www/{domain} -> domain={domain}
get_user_domain() {
    local username="$1"
    local home
    home=$(getent passwd "$username" | cut -d: -f6)

    if [[ "$home" == /var/www/* ]]; then
        basename "$home"
    else
        return 1
    fi
}

# Find the Linux user assigned to a domain (reverse lookup)
# Scans passwd for users with home=/var/www/{domain} and UID >= 1000
get_domain_user() {
    local domain="$1"
    local target_home="/var/www/${domain}"
    local result
    result=$(getent passwd | awk -F: -v home="$target_home" '$6 == home && $3 >= 1000 { print $1; exit }')
    if [[ -n "$result" ]]; then
        echo "$result"
        return 0
    fi
    return 1
}

# Compute and validate domain paths
# Sets: _USER_HOME, _USER_HTML_DIR, _USER_LOGS_DIR
resolve_domain_paths() {
    local domain="$1"
    _USER_HOME="/var/www/${domain}"
    _USER_HTML_DIR="/var/www/${domain}/html"
    _USER_LOGS_DIR="/var/www/${domain}/logs"

    if [[ ! -d "$_USER_HOME" ]]; then
        log_error "Domain directory does not exist: $_USER_HOME"
        return 1
    fi

    # Reject symlinks to prevent TOCTOU attacks
    if [[ -L "$_USER_HOME" ]]; then
        log_error "Domain path is a symlink (rejected for security): $_USER_HOME"
        return 1
    fi
}

# Verify ACL tools are installed and filesystem supports ACLs
check_acl_support() {
    if ! command_exists setfacl || ! command_exists getfacl; then
        log_error "ACL tools not installed. Install with: apt install acl"
        return 1
    fi

    # Read-only probe: check if getfacl works on /var/www
    if [[ -d /var/www ]]; then
        if ! getfacl /var/www >/dev/null 2>&1; then
            log_error "Filesystem does not support ACLs. Mount with 'acl' option or use ext4/xfs."
            return 1
        fi
    fi
}

# Apply ACL rules for a user-domain binding
# html/: user owns, www-data gets ACL rwX
# logs/: www-data owns, user gets ACL rX (read-only)
apply_acl_rules() {
    local username="$1"
    local html_dir="$2"
    local logs_dir="$3"

    log_debug "Applying ACLs: $username -> $html_dir, $logs_dir"

    # html/: change ownership to user, grant www-data ACL
    chown -Rh "${username}:${username}" "$html_dir" || {
        log_error "chown failed for $html_dir"
        return 1
    }
    setfacl -R -m "u:www-data:rwX" "$html_dir" || {
        log_error "setfacl failed for $html_dir"
        return 1
    }
    setfacl -R -d -m "u:www-data:rwX" "$html_dir" || {
        log_error "setfacl default failed for $html_dir"
        return 1
    }

    # logs/: keep www-data ownership, grant user read-only ACL
    setfacl -R -m "u:${username}:rX" "$logs_dir" || {
        log_error "setfacl failed for $logs_dir"
        return 1
    }
    setfacl -R -d -m "u:${username}:rX" "$logs_dir" || {
        log_error "setfacl default failed for $logs_dir"
        return 1
    }

    log_debug "ACLs applied successfully"
}

# Remove ACL entries and restore www-data ownership
remove_acl_rules() {
    local username="$1"
    local html_dir="$2"
    local logs_dir="$3"

    log_debug "Removing ACLs for $username"

    # Restore html/ to www-data ownership, remove all ACLs
    chown -Rh www-data:www-data "$html_dir" || log_warn "chown restore failed for $html_dir"
    setfacl -R -b "$html_dir" || log_warn "ACL removal failed for $html_dir"

    # Remove only user-specific ACL entries from logs/
    setfacl -R -x "u:${username}" "$logs_dir" 2>/dev/null || true
    setfacl -R -d -x "u:${username}" "$logs_dir" 2>/dev/null || true

    log_debug "ACLs removed"
}

# Create .ssh directory with correct permissions
create_ssh_dir() {
    local username="$1"
    local home_dir="$2"
    local ssh_dir="${home_dir}/.ssh"

    mkdir -p "$ssh_dir"
    touch "${ssh_dir}/authorized_keys"
    chmod 700 "$ssh_dir"
    chmod 600 "${ssh_dir}/authorized_keys"
    chown -Rh "${username}:${username}" "$ssh_dir"
}

# Generate formatted info for a domain user (output-only, no mutations)
generate_user_info() {
    local username="$1"
    local passwd_entry
    passwd_entry=$(getent passwd "$username")
    local home uid shell gecos
    IFS=: read -r _ _ uid _ gecos home shell <<<"$passwd_entry"
    local domain
    domain=$(basename "$home")

    echo "  Username:    $username"
    echo "  Domain:      $domain"
    echo "  UID:         $uid"
    echo "  Home:        $home"
    echo "  Shell:       $shell"

    if [[ -n "$gecos" ]]; then
        echo "  Info:        $gecos"
    fi

    # SSH key count
    local key_file="${home}/.ssh/authorized_keys"
    if [[ -f "$key_file" ]]; then
        local key_count
        key_count=$(grep -cE "^(sk-)?(ssh-|ecdsa-)" "$key_file" 2>/dev/null || echo "0")
        echo "  SSH keys:    $key_count"
    else
        echo "  SSH keys:    (no authorized_keys file)"
    fi

    # ACL status for html/
    if command_exists getfacl && [[ -d "${home}/html" ]]; then
        local html_owner
        html_owner=$(stat -c '%U' "${home}/html" 2>/dev/null || echo "unknown")
        echo "  html/ owner: $html_owner"
        if getfacl "${home}/html" 2>/dev/null | grep -q "user:www-data:"; then
            echo "  html/ ACL:   www-data access configured"
        else
            echo "  html/ ACL:   no www-data ACL found"
        fi
    fi
}

# =============================================================================
# HIGH-LEVEL OPERATIONS
# =============================================================================

# Create a Linux user for a domain with ACL-based isolation
create_domain_user() {
    local domain="$1"
    local username="$2"

    # Validation
    validate_input "$domain" "domain" || return 1
    validate_input "$username" "linux_username" || return 1

    # Check domain directory exists
    resolve_domain_paths "$domain" || return 1

    # Check ACL support before making any changes (fail fast)
    check_acl_support || return 1

    # Check: domain already has a user?
    local existing_user
    if existing_user=$(get_domain_user "$domain") && [[ -n "$existing_user" ]]; then
        log_error "Domain '$domain' already has user '$existing_user'. One user per domain."
        return 1
    fi

    # Check: Linux user already exists?
    if linux_user_exists "$username"; then
        log_error "Linux user '$username' already exists"
        return 1
    fi

    # Warn if no vhost exists
    if ! vhost_exists "$domain"; then
        log_warn "No Apache vhost found for '$domain'. User will be created but web access may not work."
        confirm "Continue without vhost?" || return 1
    fi

    # Validate shell path
    # Validate shell path (must be absolute, no traversal)
    if [[ "$ST_USER_DEFAULT_SHELL" != /* ]]; then
        log_error "Shell must be an absolute path: $ST_USER_DEFAULT_SHELL"
        return 1
    fi
    if [[ ! -x "$ST_USER_DEFAULT_SHELL" ]]; then
        log_error "Configured shell does not exist or is not executable: $ST_USER_DEFAULT_SHELL"
        return 1
    fi
    if [[ -f /etc/shells ]] && ! grep -qxF "$ST_USER_DEFAULT_SHELL" /etc/shells; then
        log_warn "Shell '$ST_USER_DEFAULT_SHELL' is not listed in /etc/shells"
    fi

    log_info "Creating user '$username' for domain '$domain'..."

    # Phase 1: Create Linux user (no home dir creation, it already exists)
    if ! useradd \
        --home-dir "/var/www/${domain}" \
        --no-create-home \
        --shell "$ST_USER_DEFAULT_SHELL" \
        --comment "server-tools domain user for ${domain}" \
        "$username"; then
        log_error "useradd failed"
        return 1
    fi

    # Phase 2: Create .ssh directory
    local ssh_preexisted=false
    [[ -d "/var/www/${domain}/.ssh" ]] && ssh_preexisted=true

    if ! create_ssh_dir "$username" "/var/www/${domain}"; then
        log_error ".ssh setup failed, rolling back user..."
        [[ "$ssh_preexisted" == "false" ]] && rm -rf "/var/www/${domain}/.ssh"
        userdel "$username" 2>/dev/null
        return 1
    fi

    # Phase 3: Apply ACLs
    if ! apply_acl_rules "$username" "$_USER_HTML_DIR" "$_USER_LOGS_DIR"; then
        log_error "ACL setup failed, rolling back..."
        [[ "$ssh_preexisted" == "false" ]] && rm -rf "/var/www/${domain}/.ssh"
        userdel "$username" 2>/dev/null
        return 1
    fi

    audit_log "INFO" "Created domain user: $username for $domain"
    log_info "User '$username' created for domain '$domain'"
    echo ""
    echo "  Username:  $username"
    echo "  Domain:    $domain"
    echo "  Home:      /var/www/${domain}"
    echo "  Shell:     $ST_USER_DEFAULT_SHELL"
    echo ""
    echo "  Next steps:"
    echo "  - Add SSH key: server-tools user add-key --username $username --key \"ssh-ed25519 ...\""
    echo "  - Set password: server-tools user set-password --username $username"
}

# Delete a domain user and restore permissions
delete_domain_user() {
    local username="$1"

    validate_input "$username" "linux_username" || return 1

    if ! linux_user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    local domain
    domain=$(get_user_domain "$username") || {
        log_error "User '$username' is not a domain user (home not under /var/www/)"
        return 1
    }

    resolve_domain_paths "$domain" || return 1

    echo "WARNING: This will delete user '$username' and restore '$domain' to www-data ownership."
    echo "  Files in /var/www/${domain}/html/ will NOT be deleted, only re-owned."
    confirm "Delete user '$username'?" || {
        echo "Aborted."
        return 1
    }

    log_info "Deleting user '$username' (domain: $domain)..."

    # 1. Remove ACLs and restore ownership (before deleting user, so UID resolves)
    remove_acl_rules "$username" "$_USER_HTML_DIR" "$_USER_LOGS_DIR"

    # 2. Remove .ssh directory
    rm -rf "/var/www/${domain}/.ssh"

    # 3. Kill running processes (SIGTERM first, then SIGKILL)
    pkill -u "$username" 2>/dev/null || true
    sleep 1
    pkill -9 -u "$username" 2>/dev/null || true
    # Wait for processes to terminate (max 5 seconds)
    local wait_count=0
    while pgrep -u "$username" >/dev/null 2>&1 && [[ $wait_count -lt 10 ]]; do
        sleep 0.5
        wait_count=$((wait_count + 1))
    done

    # 4. Delete user (--remove not used, we handle cleanup ourselves)
    userdel "$username" 2>/dev/null || log_warn "userdel failed for $username"

    audit_log "INFO" "Deleted domain user: $username (domain: $domain)"
    log_info "User '$username' deleted. Domain '$domain' restored to www-data ownership."
}

# List all domain users
list_domain_users() {
    print_header "Domain Users"

    local found=0
    printf "  %-20s %-30s %s\n" "USERNAME" "DOMAIN" "SHELL"
    printf "  %-20s %-30s %s\n" "--------" "------" "-----"

    while IFS=: read -r username _ uid _ _ home shell; do
        if [[ "$home" == /var/www/* ]] && [[ "$uid" -ge 1000 ]]; then
            local domain
            domain=$(basename "$home")
            printf "  %-20s %-30s %s\n" "$username" "$domain" "$shell"
            found=1
        fi
    done < <(getent passwd)

    if [[ $found -eq 0 ]]; then
        echo "  No domain users found."
    fi
}

# Add an SSH public key to a domain user
add_ssh_key() {
    local username="$1"
    local key="$2"

    validate_input "$username" "linux_username" || return 1
    validate_input "$key" "ssh_public_key" || return 1

    if ! linux_user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    local home
    home=$(getent passwd "$username" | cut -d: -f6)
    local auth_keys="${home}/.ssh/authorized_keys"

    if [[ ! -f "$auth_keys" ]]; then
        create_ssh_dir "$username" "$home"
    fi

    # Check for duplicate
    if grep -qxF "$key" "$auth_keys" 2>/dev/null; then
        log_warn "Key already exists in authorized_keys"
        return 0
    fi

    printf '%s\n' "$key" >>"$auth_keys"
    chmod 600 "$auth_keys"
    chown "${username}:${username}" "$auth_keys"

    audit_log "INFO" "Added SSH key for user: $username"
    log_info "SSH key added for '$username'"
}

# Set or generate password for a domain user
set_user_password() {
    local username="$1"
    local password="${2:-}"

    validate_input "$username" "linux_username" || return 1

    if ! linux_user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    if [[ -z "$password" ]]; then
        password=$(generate_password "")
        log_info "Generated secure password (${ST_PASSWORD_LENGTH} chars)"
    else
        validate_input "$password" "password" || return 1
    fi

    # Reject colons in password (chpasswd format is user:pass)
    if [[ "$password" == *:* ]]; then
        log_error "Password must not contain ':' (conflicts with chpasswd format)"
        return 1
    fi

    if ! echo "${username}:${password}" | chpasswd; then
        log_error "Failed to set password for '$username'"
        return 1
    fi

    audit_log "INFO" "Password set for domain user: $username"
    log_info "Password set for '$username'"

    # Only show password on terminal (not in pipes/scripts)
    if [[ -t 1 ]]; then
        echo ""
        echo "  Username: $username"
        echo "  Password: $password"
    fi
}

# Display detailed info about a domain user
show_user_info() {
    local username="$1"

    validate_input "$username" "linux_username" || return 1

    if ! linux_user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    print_header "User: $username"
    generate_user_info "$username"
}
