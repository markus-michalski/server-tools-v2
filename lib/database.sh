#!/bin/bash
# Database library: composable MySQL database and user management
#
# Architecture: building blocks + high-level operations
# - Building blocks: one atomic operation each, independently testable
# - High-level ops: compose blocks into workflows, add validation + logging

[[ -n "${_DATABASE_SOURCED:-}" ]] && return
_DATABASE_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"
source "${BASH_SOURCE%/*}/config.sh"
source "${BASH_SOURCE%/*}/security.sh"
source "${BASH_SOURCE%/*}/backup.sh"

# MySQL credentials (loaded on demand)
_MYSQL_PASS=""
_MYSQL_LOADED=false

# =============================================================================
# BUILDING BLOCKS - atomic operations, composable
# =============================================================================

# Load MySQL root credentials from .my.cnf
load_mysql_credentials() {
    [[ "$_MYSQL_LOADED" == "true" ]] && return 0

    if [[ ! -f "$ST_MYSQL_CONFIG_FILE" ]]; then
        log_error "MySQL config not found: $ST_MYSQL_CONFIG_FILE"
        return 1
    fi

    _MYSQL_PASS=$(awk -F '=' '/^password/ {gsub(/[ "'\'']+/, "", $2); print $2}' "$ST_MYSQL_CONFIG_FILE")
    _MYSQL_LOADED=true
    log_debug "MySQL credentials loaded from $ST_MYSQL_CONFIG_FILE"
}

# Test MySQL connectivity
mysql_check_connection() {
    if ! mysql -u"root" -p"${_MYSQL_PASS}" -e "SELECT 1" &>/dev/null; then
        log_error "Cannot connect to MySQL. Check credentials in $ST_MYSQL_CONFIG_FILE"
        audit_log "ERROR" "MySQL connection failed"
        return 1
    fi
}

# Execute a MySQL query with connection check
mysql_cmd() {
    local query="$1"
    mysql_check_connection || return 1
    mysql -u"root" -p"${_MYSQL_PASS}" -e "$query" 2>&1
}

# Check if a database exists
db_exists() {
    local db_name="$1"
    local escaped
    escaped=$(mysql_escape "$db_name")
    mysql_cmd "USE \`${escaped}\`" &>/dev/null
}

# Check if a MySQL user exists
user_exists() {
    local username="$1"
    local escaped
    escaped=$(mysql_escape "$username")
    local result
    result=$(mysql_cmd "SELECT COUNT(*) FROM mysql.user WHERE user='${escaped}'" 2>/dev/null | tail -1)
    [[ "$result" -gt 0 ]] 2>/dev/null
}

# Create a database (no user, no grants)
create_db_only() {
    local db_name="$1"
    local charset="${2:-$ST_DEFAULT_CHARSET}"
    local collation="${3:-$ST_DEFAULT_COLLATION}"
    local escaped
    escaped=$(mysql_escape "$db_name")

    if db_exists "$db_name"; then
        log_error "Database '$db_name' already exists"
        return 1
    fi

    mysql_cmd "CREATE DATABASE \`${escaped}\` CHARACTER SET ${charset} COLLATE ${collation}"
}

# Create a MySQL user (no database, no grants)
create_user_only() {
    local username="$1"
    local password="$2"
    local host="${3:-localhost}"
    local escaped_user escaped_pass

    escaped_user=$(mysql_escape "$username")
    escaped_pass=$(mysql_escape "$password")

    mysql_cmd "CREATE USER IF NOT EXISTS '${escaped_user}'@'${host}' IDENTIFIED BY '${escaped_pass}'"
}

# Grant all privileges on a database to a user
grant_privileges() {
    local db_name="$1"
    local username="$2"
    local host="${3:-localhost}"
    local escaped_db escaped_user

    escaped_db=$(mysql_escape "$db_name")
    escaped_user=$(mysql_escape "$username")

    mysql_cmd "GRANT ALL PRIVILEGES ON \`${escaped_db}\`.* TO '${escaped_user}'@'${host}'"
    mysql_cmd "FLUSH PRIVILEGES"
}

# Revoke all privileges on a database from a user
revoke_privileges() {
    local db_name="$1"
    local username="$2"
    local host="${3:-localhost}"
    local escaped_db escaped_user

    escaped_db=$(mysql_escape "$db_name")
    escaped_user=$(mysql_escape "$username")

    mysql_cmd "REVOKE ALL PRIVILEGES ON \`${escaped_db}\`.* FROM '${escaped_user}'@'${host}'"
    mysql_cmd "FLUSH PRIVILEGES"
}

# Grant read-only (SELECT) on a database to a user
grant_readonly() {
    local db_name="$1"
    local username="$2"
    local host="${3:-localhost}"
    local escaped_db escaped_user

    escaped_db=$(mysql_escape "$db_name")
    escaped_user=$(mysql_escape "$username")

    mysql_cmd "GRANT SELECT ON \`${escaped_db}\`.* TO '${escaped_user}'@'${host}'"
    mysql_cmd "FLUSH PRIVILEGES"
}

# Grant read-write (SELECT, INSERT, UPDATE, DELETE) on a database to a user
grant_readwrite() {
    local db_name="$1"
    local username="$2"
    local host="${3:-localhost}"
    local escaped_db escaped_user

    escaped_db=$(mysql_escape "$db_name")
    escaped_user=$(mysql_escape "$username")

    mysql_cmd "GRANT SELECT, INSERT, UPDATE, DELETE ON \`${escaped_db}\`.* TO '${escaped_user}'@'${host}'"
    mysql_cmd "FLUSH PRIVILEGES"
}

# Show grants for a specific user
show_user_grants() {
    local username="$1"
    local host="${2:-localhost}"
    local escaped_user
    escaped_user=$(mysql_escape "$username")

    mysql_cmd "SHOW GRANTS FOR '${escaped_user}'@'${host}'" 2>/dev/null
}

# Dump a database to a compressed file
dump_database() {
    local db_name="$1"
    local output_dir="${2:-$ST_DB_BACKUP_DIR}"
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local output_file="${output_dir}/db_${db_name}_${timestamp}.sql.gz"

    # Ensure output directory exists
    if [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir"
        chmod 700 "$output_dir"
    fi

    mysqldump -u"root" -p"${_MYSQL_PASS}" --single-transaction --routines --triggers \
        "$db_name" 2>/dev/null | gzip >"$output_file"

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        rm -f "$output_file"
        return 1
    fi

    chmod 600 "$output_file"
    echo "$output_file"
}

# Restore a dump file into a database
restore_dump() {
    local db_name="$1"
    local dump_file="$2"
    local escaped
    escaped=$(mysql_escape "$db_name")

    case "$dump_file" in
        *.sql.gz)
            gunzip -c "$dump_file" | mysql -u"root" -p"${_MYSQL_PASS}" "$escaped" 2>&1
            ;;
        *.sql.zip)
            unzip -p "$dump_file" | mysql -u"root" -p"${_MYSQL_PASS}" "$escaped" 2>&1
            ;;
        *.sql)
            mysql -u"root" -p"${_MYSQL_PASS}" "$escaped" <"$dump_file" 2>&1
            ;;
        *)
            log_error "Unsupported file format: $dump_file (expected .sql, .sql.gz, .sql.zip)"
            return 1
            ;;
    esac
}

# Export a database to a specific file path
export_to_file() {
    local db_name="$1"
    local output_file="$2"

    # Determine compression from extension
    case "$output_file" in
        *.sql.gz)
            mysqldump -u"root" -p"${_MYSQL_PASS}" --single-transaction --routines --triggers \
                "$db_name" 2>/dev/null | gzip >"$output_file"
            ;;
        *.sql)
            mysqldump -u"root" -p"${_MYSQL_PASS}" --single-transaction --routines --triggers \
                "$db_name" >"$output_file" 2>/dev/null
            ;;
        *)
            log_error "Unsupported output format: $output_file (use .sql or .sql.gz)"
            return 1
            ;;
    esac

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        rm -f "$output_file"
        return 1
    fi

    chmod 600 "$output_file"
}

# Drop a database
drop_db_only() {
    local db_name="$1"
    local escaped
    escaped=$(mysql_escape "$db_name")
    mysql_cmd "DROP DATABASE IF EXISTS \`${escaped}\`"
}

# Drop a MySQL user
drop_user_only() {
    local username="$1"
    local host="${2:-localhost}"
    local escaped
    escaped=$(mysql_escape "$username")
    mysql_cmd "DROP USER IF EXISTS '${escaped}'@'${host}'"
    mysql_cmd "FLUSH PRIVILEGES"
}

# Save credentials to file
save_credentials() {
    local db_name="$1"
    local username="$2"
    local password="$3"
    local credentials_file="${ST_CREDENTIAL_DIR}/${db_name}.txt"

    # Ensure credential directory exists with strict permissions
    if [[ ! -d "$ST_CREDENTIAL_DIR" ]]; then
        local old_umask
        old_umask=$(umask)
        umask 077
        mkdir -p "$ST_CREDENTIAL_DIR"
        umask "$old_umask"
    fi

    local content
    content="# Database Credentials for: ${db_name}
# Created: $(date '+%Y-%m-%d %H:%M:%S')
# =========================================

Database: ${db_name}
Username: ${username}
Password: ${password}

# Connection Strings
# ------------------
# PDO DSN:
#   mysql:host=localhost;dbname=${db_name};charset=utf8mb4
#
# Symfony DATABASE_URL:
#   mysql://${username}:${password}@localhost:3306/${db_name}?charset=utf8mb4
"

    safe_write_file "$credentials_file" "$content" "$ST_CREDENTIAL_FILE_PERMISSIONS"
    log_info "Credentials saved: $credentials_file"
}

# Remove credentials file
remove_credentials() {
    local db_name="$1"
    local credentials_file="${ST_CREDENTIAL_DIR}/${db_name}.txt"

    if [[ -f "$credentials_file" ]]; then
        rm -f "$credentials_file"
        log_info "Credentials removed: $credentials_file"
    fi
}

# =============================================================================
# HIGH-LEVEL OPERATIONS - compose building blocks
# =============================================================================

# Create a new database with a dedicated user
create_database() {
    local db_name="$1"
    local username="$2"
    local password="${3:-}"

    # Validate inputs
    validate_input "$db_name" "database" || return 1
    validate_input "$username" "username" || return 1

    # Auto-generate password if empty
    if [[ -z "$password" ]]; then
        password=$(generate_password "") # uses default length
        log_info "Generated secure password (${ST_PASSWORD_LENGTH} chars)"
    else
        validate_input "$password" "password" || return 1
    fi

    # Load credentials
    load_mysql_credentials || return 1

    # Execute building blocks
    log_info "Creating database '$db_name' with user '$username'..."

    create_db_only "$db_name" || return 1
    create_user_only "$username" "$password" || {
        # Rollback: drop the database we just created
        drop_db_only "$db_name"
        return 1
    }
    grant_privileges "$db_name" "$username" || return 1
    save_credentials "$db_name" "$username" "$password"

    audit_log "INFO" "Created database: $db_name with user: $username"
    log_info "Database '$db_name' created successfully"
    echo ""
    echo "  Database: $db_name"
    echo "  Username: $username"
    echo "  Password: $password"
    echo "  Credentials: ${ST_CREDENTIAL_DIR}/${db_name}.txt"
}

# Create a database for an existing user (no new user created)
create_db_for_user() {
    local db_name="$1"
    local username="$2"

    validate_input "$db_name" "database" || return 1
    validate_input "$username" "username" || return 1

    load_mysql_credentials || return 1

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    log_info "Creating database '$db_name' for existing user '$username'..."

    create_db_only "$db_name" || return 1
    grant_privileges "$db_name" "$username" || return 1
    save_credentials "$db_name" "$username" "(existing user - no password stored)"

    audit_log "INFO" "Created database: $db_name for existing user: $username"
    log_info "Database '$db_name' granted to user '$username'"
}

# Delete a database but keep the user account
delete_database_keep_user() {
    local db_name="$1"
    local username="${2:-}"

    validate_input "$db_name" "database" || return 1

    load_mysql_credentials || return 1

    if ! db_exists "$db_name"; then
        log_error "Database '$db_name' does not exist"
        return 1
    fi

    echo "WARNING: This will permanently delete database '$db_name'"
    if [[ -n "$username" ]]; then
        echo "User '$username' will NOT be deleted (only privileges revoked)"
    fi

    # Backup credentials before deletion
    backup_before_delete "${ST_CREDENTIAL_DIR}/${db_name}.txt" "db_${db_name}" || return 1

    confirm "Delete database '$db_name'?" || {
        echo "Aborted."
        return 1
    }

    log_info "Deleting database '$db_name'..."

    # Revoke privileges before dropping the database
    if [[ -n "$username" ]]; then
        validate_input "$username" "username" || return 1
        if user_exists "$username"; then
            revoke_privileges "$db_name" "$username" || log_warn "Failed to revoke privileges for '$username'"
        fi
    fi

    drop_db_only "$db_name" || return 1
    remove_credentials "$db_name"

    audit_log "INFO" "Deleted database: $db_name (user kept: ${username:-none})"
    log_info "Database '$db_name' deleted successfully (user kept)"
}

# Reassign a database from one user to another
reassign_db_to_user() {
    local db_name="$1"
    local old_user="$2"
    local new_user="$3"

    validate_input "$db_name" "database" || return 1
    validate_input "$old_user" "username" || return 1
    validate_input "$new_user" "username" || return 1

    load_mysql_credentials || return 1

    if ! db_exists "$db_name"; then
        log_error "Database '$db_name' does not exist"
        return 1
    fi

    if ! user_exists "$old_user"; then
        log_error "Current user '$old_user' does not exist"
        return 1
    fi

    if ! user_exists "$new_user"; then
        log_error "New user '$new_user' does not exist"
        return 1
    fi

    if [[ "$old_user" == "$new_user" ]]; then
        log_error "Old and new user are the same"
        return 1
    fi

    log_info "Reassigning '$db_name' from '$old_user' to '$new_user'..."

    revoke_privileges "$db_name" "$old_user" || return 1
    grant_privileges "$db_name" "$new_user" || {
        # Rollback: re-grant to old user
        log_warn "Failed to grant to '$new_user', restoring '$old_user' access..."
        grant_privileges "$db_name" "$old_user" || log_error "CRITICAL: Rollback failed! Manual intervention required."
        return 1
    }

    audit_log "INFO" "Reassigned $db_name from $old_user to $new_user"
    log_info "Database '$db_name' reassigned from '$old_user' to '$new_user'"
}

# Grant access on an existing database to an existing user
assign_db_to_user() {
    local db_name="$1"
    local username="$2"

    validate_input "$db_name" "database" || return 1
    validate_input "$username" "username" || return 1

    load_mysql_credentials || return 1

    if ! db_exists "$db_name"; then
        log_error "Database '$db_name' does not exist"
        return 1
    fi

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    log_info "Granting '$username' access to '$db_name'..."
    grant_privileges "$db_name" "$username" || return 1

    audit_log "INFO" "Granted $username access to $db_name"
    log_info "User '$username' now has access to '$db_name'"
}

# Delete a database and optionally its user
delete_database() {
    local db_name="$1"
    local username="${2:-}"
    local drop_user="${3:-false}"

    validate_input "$db_name" "database" || return 1

    load_mysql_credentials || return 1

    if ! db_exists "$db_name"; then
        log_error "Database '$db_name' does not exist"
        return 1
    fi

    echo "WARNING: This will permanently delete database '$db_name'"
    [[ -n "$username" ]] && [[ "$drop_user" == "true" ]] && echo "WARNING: User '$username' will also be dropped"

    # Backup credentials before deletion
    backup_before_delete "${ST_CREDENTIAL_DIR}/${db_name}.txt" "db_${db_name}" || return 1

    confirm "Delete database '$db_name'?" || {
        echo "Aborted."
        return 1
    }

    log_info "Deleting database '$db_name'..."
    drop_db_only "$db_name" || return 1

    if [[ -n "$username" ]] && [[ "$drop_user" == "true" ]]; then
        validate_input "$username" "username" || return 1
        log_info "Dropping user '$username'..."
        drop_user_only "$username" || log_warn "Failed to drop user '$username'"
    fi

    remove_credentials "$db_name"

    audit_log "INFO" "Deleted database: $db_name"
    log_info "Database '$db_name' deleted successfully"
}

# List all databases (excluding system databases)
list_databases() {
    load_mysql_credentials || return 1

    print_header "Databases"
    echo "MySQL databases:"
    mysql_cmd "SHOW DATABASES" 2>/dev/null | grep -Ev "^(Database|information_schema|performance_schema|mysql|sys)$" | sed 's/^/  - /'
    echo ""
    echo "MySQL users:"
    mysql_cmd "SELECT CONCAT(user, '@', host) FROM mysql.user WHERE user NOT IN ('root', 'mysql.sys', 'mysql.session', 'mysql.infoschema', 'debian-sys-maint') ORDER BY user" 2>/dev/null | tail -n +2 | sed 's/^/  - /'
}

# Show detailed info about a database
show_db_info() {
    local db_name="$1"

    validate_input "$db_name" "database" || return 1
    load_mysql_credentials || return 1

    if ! db_exists "$db_name"; then
        log_error "Database '$db_name' does not exist"
        return 1
    fi

    print_header "Database: $db_name"

    # Size
    echo "Size:"
    mysql_cmd "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)' FROM information_schema.tables WHERE table_schema = '$(mysql_escape "$db_name")'" 2>/dev/null | tail -1 | sed 's/^/  /'
    echo " MB"

    # Tables
    echo ""
    echo "Tables:"
    mysql_cmd "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$(mysql_escape "$db_name")'" 2>/dev/null | tail -1 | sed 's/^/  /'

    # Grants
    echo ""
    echo "Users with access:"
    mysql_cmd "SELECT DISTINCT CONCAT(grantee) FROM information_schema.schema_privileges WHERE table_schema = '$(mysql_escape "$db_name")'" 2>/dev/null | tail -n +2 | sed 's/^/  /'

    # Credential file
    echo ""
    local cred_file="${ST_CREDENTIAL_DIR}/${db_name}.txt"
    if [[ -f "$cred_file" ]]; then
        echo "Credentials: $cred_file"
    else
        echo "Credentials: not stored"
    fi
}

# Backup a single database to compressed dump
backup_database() {
    local db_name="$1"

    validate_input "$db_name" "database" || return 1
    load_mysql_credentials || return 1

    if ! db_exists "$db_name"; then
        log_error "Database '$db_name' does not exist"
        return 1
    fi

    log_info "Backing up database '$db_name'..."
    local dump_file
    dump_file=$(dump_database "$db_name") || {
        log_error "Failed to backup database '$db_name'"
        return 1
    }

    audit_log "INFO" "Database backup: $db_name -> $dump_file"
    log_info "Backup saved: $dump_file"
    echo ""
    echo "  File: $dump_file"
    echo "  Size: $(du -h "$dump_file" 2>/dev/null | cut -f1)"
}

# Backup all non-system databases
backup_all_databases() {
    load_mysql_credentials || return 1

    local databases
    databases=$(mysql_cmd "SHOW DATABASES" 2>/dev/null | grep -Ev "^(Database|information_schema|performance_schema|mysql|sys)$")

    if [[ -z "$databases" ]]; then
        log_warn "No user databases found to backup"
        return 0
    fi

    local count=0
    local failed=0
    log_info "Backing up all databases..."

    for db in $databases; do
        log_info "Backing up '$db'..."
        local dump_file
        dump_file=$(dump_database "$db") || {
            log_error "Failed to backup '$db'"
            ((failed++))
            continue
        }
        log_info "  -> $dump_file"
        ((count++))
    done

    audit_log "INFO" "Bulk database backup: $count succeeded, $failed failed"
    log_info "Backup complete: $count databases backed up, $failed failed"
}

# Restore a database from a dump file
restore_database() {
    local db_name="$1"
    local dump_file="$2"

    validate_input "$db_name" "database" || return 1

    if [[ -z "$dump_file" ]]; then
        log_error "Dump file path is required"
        return 1
    fi

    if [[ ! -f "$dump_file" ]]; then
        log_error "File not found: $dump_file"
        return 1
    fi

    load_mysql_credentials || return 1

    if ! db_exists "$db_name"; then
        log_error "Database '$db_name' does not exist. Create it first."
        return 1
    fi

    echo "WARNING: This will overwrite all data in database '$db_name'"
    confirm "Restore '$dump_file' into '$db_name'?" || {
        echo "Aborted."
        return 1
    }

    log_info "Restoring '$dump_file' into '$db_name'..."
    restore_dump "$db_name" "$dump_file" || {
        log_error "Failed to restore database '$db_name'"
        return 1
    }

    audit_log "INFO" "Database restored: $db_name from $dump_file"
    log_info "Database '$db_name' restored successfully"
}

# Import a SQL file into an existing database
import_database() {
    local db_name="$1"
    local sql_file="$2"

    validate_input "$db_name" "database" || return 1

    if [[ -z "$sql_file" ]]; then
        log_error "SQL file path is required"
        return 1
    fi

    if [[ ! -f "$sql_file" ]]; then
        log_error "File not found: $sql_file"
        return 1
    fi

    # Validate file extension
    case "$sql_file" in
        *.sql | *.sql.gz | *.sql.zip) ;;
        *)
            log_error "Unsupported file format (expected .sql, .sql.gz, .sql.zip)"
            return 1
            ;;
    esac

    load_mysql_credentials || return 1

    if ! db_exists "$db_name"; then
        log_error "Database '$db_name' does not exist"
        return 1
    fi

    log_info "Importing '$sql_file' into '$db_name'..."
    restore_dump "$db_name" "$sql_file" || {
        log_error "Import failed"
        return 1
    }

    audit_log "INFO" "SQL import: $sql_file -> $db_name"
    log_info "Import into '$db_name' completed successfully"
}

# Export a database to a specific file
export_db_to_file() {
    local db_name="$1"
    local output_file="${2:-}"

    validate_input "$db_name" "database" || return 1
    load_mysql_credentials || return 1

    if ! db_exists "$db_name"; then
        log_error "Database '$db_name' does not exist"
        return 1
    fi

    # Default output path
    if [[ -z "$output_file" ]]; then
        local timestamp
        timestamp=$(date '+%Y%m%d_%H%M%S')
        output_file="${ST_DB_BACKUP_DIR}/${db_name}_export_${timestamp}.sql.gz"
    fi

    log_info "Exporting '$db_name' to '$output_file'..."
    export_to_file "$db_name" "$output_file" || {
        log_error "Export failed"
        return 1
    }

    audit_log "INFO" "Database export: $db_name -> $output_file"
    log_info "Export saved: $output_file"
    echo ""
    echo "  File: $output_file"
    echo "  Size: $(du -h "$output_file" 2>/dev/null | cut -f1)"
}

# Grant read-only access (high-level operation)
grant_user_readonly() {
    local db_name="$1"
    local username="$2"

    validate_input "$db_name" "database" || return 1
    validate_input "$username" "username" || return 1

    load_mysql_credentials || return 1

    if ! db_exists "$db_name"; then
        log_error "Database '$db_name' does not exist"
        return 1
    fi

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    log_info "Granting read-only access on '$db_name' to '$username'..."
    grant_readonly "$db_name" "$username" || return 1

    audit_log "INFO" "Granted SELECT on $db_name to $username"
    log_info "User '$username' now has read-only access to '$db_name'"
}

# Grant read-write access (high-level operation)
grant_user_readwrite() {
    local db_name="$1"
    local username="$2"

    validate_input "$db_name" "database" || return 1
    validate_input "$username" "username" || return 1

    load_mysql_credentials || return 1

    if ! db_exists "$db_name"; then
        log_error "Database '$db_name' does not exist"
        return 1
    fi

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    log_info "Granting read-write access on '$db_name' to '$username'..."
    grant_readwrite "$db_name" "$username" || return 1

    audit_log "INFO" "Granted SELECT,INSERT,UPDATE,DELETE on $db_name to $username"
    log_info "User '$username' now has read-write access to '$db_name'"
}

# Show grants for a user (high-level operation)
show_grants() {
    local username="$1"

    validate_input "$username" "username" || return 1
    load_mysql_credentials || return 1

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    print_header "Grants for: $username"
    show_user_grants "$username" | tail -n +2 | sed 's/^/  /'
}
