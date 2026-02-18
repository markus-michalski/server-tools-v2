#!/bin/bash
# Backup library: backup creation, cleanup, and listing

[[ -n "${_BACKUP_SOURCED:-}" ]] && return
_BACKUP_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"
source "${BASH_SOURCE%/*}/config.sh"
source "${BASH_SOURCE%/*}/security.sh"

# --- Building blocks ---

# Create a tar.gz backup of a file or directory
create_backup() {
    local source="$1"
    local backup_name="${2:-$(basename "$source")}"
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="${ST_BACKUP_DIR}/${backup_name}_${timestamp}.tar.gz"

    if [[ ! -e "$source" ]]; then
        log_warn "Backup source does not exist: $source"
        return 1
    fi

    # Create backup directory if needed
    if [[ ! -d "$ST_BACKUP_DIR" ]]; then
        mkdir -p "$ST_BACKUP_DIR"
        chmod 700 "$ST_BACKUP_DIR"
    fi

    log_info "Creating backup: $backup_file"
    if tar -czf "$backup_file" -C "$(dirname "$source")" "$(basename "$source")" 2>/dev/null; then
        chmod 600 "$backup_file"
        log_info "Backup created: $backup_file"
        audit_log "INFO" "Created backup: $backup_file"
        return 0
    else
        log_error "Failed to create backup!"
        return 1
    fi
}

# --- High-level operations ---

# Auto-backup before destructive operations
# Returns 0 to proceed, 1 to abort
backup_before_delete() {
    local target="$1"
    local name="$2"

    # Skip if auto-backup is disabled
    [[ "$ST_AUTO_BACKUP" != "true" ]] && return 0

    # Skip if target doesn't exist
    [[ ! -e "$target" ]] && return 0

    log_info "Auto-backup enabled, creating backup..."
    if create_backup "$target" "$name"; then
        return 0
    else
        log_warn "Backup failed."
        if confirm "Continue without backup?"; then
            return 0
        fi
        return 1
    fi
}

# Remove backups older than retention period
cleanup_old_backups() {
    [[ ! -d "$ST_BACKUP_DIR" ]] && return 0

    log_info "Cleaning up backups older than $ST_BACKUP_RETENTION_DAYS days..."
    local count=0

    while IFS= read -r -d '' backup_file; do
        rm -f "$backup_file"
        ((count++))
    done < <(find "$ST_BACKUP_DIR" -name "*.tar.gz" -type f -mtime +"$ST_BACKUP_RETENTION_DAYS" -print0 2>/dev/null)

    if [[ $count -gt 0 ]]; then
        log_info "Removed $count old backup(s)"
        audit_log "INFO" "Cleaned up $count old backups"
    fi
}

# Display available backups
list_backups() {
    print_header "Backups"
    echo "Directory: $ST_BACKUP_DIR"
    echo ""

    if [[ ! -d "$ST_BACKUP_DIR" ]] || [[ -z "$(ls -A "$ST_BACKUP_DIR" 2>/dev/null)" ]]; then
        echo "No backups found"
        return 0
    fi

    echo "Available backups:"
    ls -lh "$ST_BACKUP_DIR" | grep "\.tar\.gz$" | awk '{printf "  %s  %5s  %s\n", $6" "$7" "$8, $5, $9}' || echo "  None"
    echo ""
    echo "Auto-cleanup: after $ST_BACKUP_RETENTION_DAYS days"
}
