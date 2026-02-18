#!/bin/bash
# Cron library: system cron job management via /etc/cron.d
#
# Building blocks: cron file operations, schedule validation
# High-level ops: add, remove, list cron jobs

[[ -n "${_CRON_SOURCED:-}" ]] && return
_CRON_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"
source "${BASH_SOURCE%/*}/config.sh"
source "${BASH_SOURCE%/*}/security.sh"

# =============================================================================
# BUILDING BLOCKS
# =============================================================================

# Generate a sanitized cron file name from a label
cron_file_name() {
    local name="$1"
    # Replace non-alphanumeric chars with underscores, lowercase
    echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/_/g'
}

# Check if a cron job file exists by name
cron_exists() {
    local name="$1"
    local file="/etc/cron.d/$(cron_file_name "$name")"
    [[ -f "$file" ]]
}

# Generate cron file content (pure function)
generate_cron_content() {
    local schedule="$1"
    local command="$2"
    local user="${3:-root}"

    cat <<EOF
# Cron Job - Created $(date '+%Y-%m-%d %H:%M:%S') by server-tools
${schedule} ${user} ${command}
EOF
}

# =============================================================================
# HIGH-LEVEL OPERATIONS
# =============================================================================

# Add a system cron job to /etc/cron.d
add_cron() {
    local schedule="$1"
    local command="$2"
    local name="${3:-}"

    if [[ -z "$schedule" ]] || [[ -z "$command" ]]; then
        log_error "Schedule and command are required"
        return 1
    fi

    validate_input "$schedule" "cron_schedule" || return 1

    # Generate name if not provided
    if [[ -z "$name" ]]; then
        name="custom_$(date +%s)"
    fi

    local safe_name
    safe_name=$(cron_file_name "$name")
    local cron_file="/etc/cron.d/${safe_name}"

    # Check for existing cron with same name
    if [[ -f "$cron_file" ]]; then
        log_warn "Cron job '$safe_name' already exists"
        confirm "Overwrite existing cron job?" || return 1
    fi

    log_info "Creating cron job '$safe_name'..."

    local content
    content=$(generate_cron_content "$schedule" "$command")
    safe_write_file "$cron_file" "$content" 644

    audit_log "INFO" "Created cron job: $safe_name ($schedule)"
    log_info "Cron job created: $cron_file"
    echo "  Schedule: $schedule"
    echo "  Command:  $command"
}

# Remove a cron job by searching for a pattern
remove_cron() {
    local pattern="$1"

    if [[ -z "$pattern" ]]; then
        log_error "Search pattern is required"
        return 1
    fi

    if [[ ! -d "/etc/cron.d" ]]; then
        log_error "No cron directory found"
        return 1
    fi

    local found=0

    for file in /etc/cron.d/*; do
        if [[ -f "$file" ]] && grep -qF "$pattern" "$file" 2>/dev/null; then
            echo "Found: $file"
            cat "$file"
            echo ""
            confirm "Delete this cron job?" || continue
            rm -f "$file"
            audit_log "INFO" "Deleted cron job: $(basename "$file")"
            log_info "Cron job deleted: $file"
            found=1
        fi
    done

    if [[ $found -eq 0 ]]; then
        log_warn "No cron jobs matching '$pattern' found"
        return 1
    fi
}

# List all system cron jobs
list_crons() {
    print_header "Cron Jobs"

    echo "System cron jobs (/etc/cron.d):"
    local count=0

    if [[ -d "/etc/cron.d" ]]; then
        for file in /etc/cron.d/*; do
            if [[ -f "$file" ]]; then
                echo "  $(basename "$file"):"
                sed 's/^/    /' "$file"
                echo ""
                ((count++))
            fi
        done
    fi

    if [[ $count -eq 0 ]]; then
        echo "  (none)"
    fi

    echo ""
    echo "Root crontab:"
    if ! crontab -l 2>/dev/null; then
        echo "  (none)"
    fi
}
