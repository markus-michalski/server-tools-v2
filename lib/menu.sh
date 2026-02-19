#!/bin/bash
# Menu library: interactive TUI menus for server administration
#
# Provides main menu and submenus for all server-tools modules.
# Each submenu delegates to the corresponding library's high-level operations.

[[ -n "${_MENU_SOURCED:-}" ]] && return
_MENU_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"
source "${BASH_SOURCE%/*}/config.sh"
source "${BASH_SOURCE%/*}/security.sh"
source "${BASH_SOURCE%/*}/backup.sh"
source "${BASH_SOURCE%/*}/database.sh"
source "${BASH_SOURCE%/*}/vhost.sh"
source "${BASH_SOURCE%/*}/ssl.sh"
source "${BASH_SOURCE%/*}/cron.sh"
source "${BASH_SOURCE%/*}/status.sh"
source "${BASH_SOURCE%/*}/log.sh"
source "${BASH_SOURCE%/*}/firewall.sh"
source "${BASH_SOURCE%/*}/fail2ban.sh"

# =============================================================================
# MENU HELPERS
# =============================================================================

# Display a menu and read user choice into MENU_CHOICE
# Note: MENU_CHOICE is intentionally global so callers can read it after show_menu returns.
# Menus are always sequential (never nested), so this is safe.
show_menu() {
    local title="$1"
    shift
    local options=("$@")

    clear
    echo "=== $title ==="
    echo ""

    local i=1
    for option in "${options[@]}"; do
        echo "  $i. $option"
        ((i++))
    done

    echo ""
    MENU_CHOICE=""
    read -r -p "Choose an option (1-${#options[@]}): " MENU_CHOICE
}

# Wait for user to press Enter
press_enter() {
    echo ""
    read -r -p "Press Enter to continue..."
}

# =============================================================================
# DATABASE MENU
# =============================================================================

database_menu() {
    if ! load_mysql_credentials; then
        log_error "Cannot connect to MySQL. Check /root/.my.cnf"
        press_enter
        return
    fi
    local submenu=true

    while $submenu; do
        show_menu "Database Management" \
            "Create database & user" \
            "Create database for existing user" \
            "Delete database only (keep user)" \
            "Delete database & user" \
            "Assign database to additional user" \
            "Reassign database to different user" \
            "Grant read-only access" \
            "Grant read-write access" \
            "Show user grants" \
            "Backup database" \
            "Backup all databases" \
            "Restore database from backup" \
            "Import SQL file" \
            "Export database to file" \
            "List databases" \
            "Show database info" \
            "Back to main menu"

        case $MENU_CHOICE in
            1)
                local db_name db_user db_pass
                read -r -p "Database name: " db_name
                read -r -p "Database user: " db_user
                read -r -s -p "Password (empty for auto-generated): " db_pass
                echo
                if [[ -z "$db_pass" ]]; then
                    db_pass=$(generate_password "")
                    log_info "Secure password generated"
                fi
                create_database "$db_name" "$db_user" "$db_pass" || true
                press_enter
                ;;
            2)
                local db_name db_user
                read -r -p "Database name: " db_name
                read -r -p "Existing user: " db_user
                create_db_for_user "$db_name" "$db_user" || true
                press_enter
                ;;
            3)
                local db_name db_user
                list_databases || true
                echo ""
                read -r -p "Database to delete: " db_name
                read -r -p "User to revoke access from (empty to skip): " db_user
                delete_database_keep_user "$db_name" "$db_user" || true
                press_enter
                ;;
            4)
                local db_name db_user
                list_databases || true
                echo ""
                read -r -p "Database to delete: " db_name
                read -r -p "User to delete: " db_user
                delete_database "$db_name" "$db_user" "true" || true
                press_enter
                ;;
            5)
                local db_name db_user
                read -r -p "Database name: " db_name
                read -r -p "User to grant access: " db_user
                assign_db_to_user "$db_name" "$db_user" || true
                press_enter
                ;;
            6)
                local db_name old_user new_user
                list_databases || true
                echo ""
                read -r -p "Database name: " db_name
                read -r -p "Current user: " old_user
                read -r -p "New user: " new_user
                reassign_db_to_user "$db_name" "$old_user" "$new_user" || true
                press_enter
                ;;
            7)
                local db_name db_user
                read -r -p "Database name: " db_name
                read -r -p "User: " db_user
                grant_user_readonly "$db_name" "$db_user" || true
                press_enter
                ;;
            8)
                local db_name db_user
                read -r -p "Database name: " db_name
                read -r -p "User: " db_user
                grant_user_readwrite "$db_name" "$db_user" || true
                press_enter
                ;;
            9)
                local db_user
                read -r -p "Username: " db_user
                show_grants "$db_user" || true
                press_enter
                ;;
            10)
                local db_name
                read -r -p "Database name: " db_name
                backup_database "$db_name" || true
                press_enter
                ;;
            11)
                backup_all_databases || true
                press_enter
                ;;
            12)
                local db_name dump_file
                read -r -p "Database name: " db_name
                read -r -p "Dump file path: " dump_file
                restore_database "$db_name" "$dump_file" || true
                press_enter
                ;;
            13)
                local db_name sql_file
                read -r -p "Database name: " db_name
                read -r -p "SQL file path: " sql_file
                import_database "$db_name" "$sql_file" || true
                press_enter
                ;;
            14)
                local db_name output_file
                read -r -p "Database name: " db_name
                read -r -p "Output file (empty for default): " output_file
                export_db_to_file "$db_name" "$output_file" || true
                press_enter
                ;;
            15)
                list_databases || true
                press_enter
                ;;
            16)
                local db_name
                read -r -p "Database name: " db_name
                show_db_info "$db_name" || true
                press_enter
                ;;
            17)
                submenu=false
                ;;
            *)
                log_error "Invalid option"
                press_enter
                ;;
        esac
    done
}

# =============================================================================
# VHOST MENU
# =============================================================================

vhost_menu() {
    local submenu=true

    while $submenu; do
        show_menu "Virtual Host Management" \
            "Create virtual host" \
            "Delete virtual host" \
            "List virtual hosts" \
            "Change PHP version" \
            "Show vhost info" \
            "Create domain redirect (301/302)" \
            "Add www redirect" \
            "Force HTTPS redirect" \
            "Back to main menu"

        case $MENU_CHOICE in
            1)
                local domain aliases available_php php_version custom_docroot
                read -r -p "Domain: " domain
                read -r -p "Aliases (space-separated, empty for none): " aliases
                available_php=$(detect_php_versions)
                if [[ -z "$available_php" ]]; then
                    log_error "No PHP-FPM versions found"
                    press_enter
                    continue
                fi
                echo "Available PHP versions: $available_php"
                read -r -p "PHP version [$ST_DEFAULT_PHP_VERSION]: " php_version
                php_version=${php_version:-$ST_DEFAULT_PHP_VERSION}
                read -r -p "Custom DocumentRoot (empty for default): " custom_docroot
                create_vhost "$domain" "$aliases" "$php_version" "$custom_docroot" || true
                press_enter
                ;;
            2)
                local domain
                list_vhosts || true
                echo ""
                read -r -p "Domain to delete: " domain
                delete_vhost "$domain" || true
                press_enter
                ;;
            3)
                list_vhosts || true
                press_enter
                ;;
            4)
                local available_php domain php_version
                list_vhosts || true
                echo ""
                available_php=$(detect_php_versions)
                if [[ -z "$available_php" ]]; then
                    log_error "No PHP-FPM versions found"
                    press_enter
                    continue
                fi
                echo "Available PHP versions: $available_php"
                read -r -p "Domain: " domain
                read -r -p "New PHP version: " php_version
                change_php_version "$domain" "$php_version" || true
                press_enter
                ;;
            5)
                local domain
                read -r -p "Domain: " domain
                show_vhost_info "$domain" || true
                press_enter
                ;;
            6)
                local source_domain target_url code
                read -r -p "Source domain: " source_domain
                read -r -p "Target URL (e.g. https://new-domain.com/): " target_url
                read -r -p "Redirect code [301]: " code
                create_redirect "$source_domain" "$target_url" "${code:-301}" || true
                press_enter
                ;;
            7)
                local domain direction dir
                read -r -p "Domain: " domain
                echo "  1. Redirect non-www to www"
                echo "  2. Redirect www to non-www"
                read -r -p "Direction [1]: " direction
                dir="to_www"
                [[ "$direction" == "2" ]] && dir="from_www"
                add_www_redirect "$domain" "$dir" || true
                press_enter
                ;;
            8)
                local domain
                read -r -p "Domain: " domain
                force_https "$domain" || true
                press_enter
                ;;
            9)
                submenu=false
                ;;
            *)
                log_error "Invalid option"
                press_enter
                ;;
        esac
    done
}

# =============================================================================
# SSL MENU
# =============================================================================

ssl_menu() {
    local submenu=true

    while $submenu; do
        show_menu "SSL Certificate Management" \
            "Create SSL certificate" \
            "Create wildcard certificate (DNS challenge)" \
            "Delete SSL certificate" \
            "List certificates" \
            "Check expiring certificates" \
            "Setup automatic renewal" \
            "Recreate all certificates (Apache mode)" \
            "Back to main menu"

        case $MENU_CHOICE in
            1)
                local domain email
                list_vhosts || true
                echo ""
                read -r -p "Domain: " domain
                read -r -p "Email (empty for default): " email
                setup_ssl "$domain" "$email" || true
                press_enter
                ;;
            2)
                local domain provider
                read -r -p "Domain (e.g. example.com for *.example.com): " domain
                read -r -p "DNS provider (cloudflare/digitalocean/route53): " provider
                setup_wildcard_ssl "$domain" "$provider" || true
                press_enter
                ;;
            3)
                local domain
                list_certificates || true
                echo ""
                read -r -p "Domain: " domain
                delete_ssl "$domain" || true
                press_enter
                ;;
            4)
                list_certificates || true
                press_enter
                ;;
            5)
                local days
                read -r -p "Days threshold [30]: " days
                check_expiring_soon "${days:-30}" || true
                press_enter
                ;;
            6)
                setup_ssl_renewal || true
                press_enter
                ;;
            7)
                recreate_all_ssl || true
                press_enter
                ;;
            8)
                submenu=false
                ;;
            *)
                log_error "Invalid option"
                press_enter
                ;;
        esac
    done
}

# =============================================================================
# CRON MENU
# =============================================================================

cron_menu() {
    local submenu=true

    while $submenu; do
        show_menu "Cron Job Management" \
            "Add cron job" \
            "Remove cron job" \
            "List cron jobs" \
            "Back to main menu"

        case $MENU_CHOICE in
            1)
                local schedule command name
                read -r -p "Schedule (e.g. '0 4 * * *'): " schedule
                read -r -p "Command: " command
                read -r -p "Job name: " name
                add_cron "$schedule" "$command" "$name" || true
                press_enter
                ;;
            2)
                local pattern
                list_crons || true
                echo ""
                read -r -p "Search pattern to find job: " pattern
                remove_cron "$pattern" || true
                press_enter
                ;;
            3)
                list_crons || true
                press_enter
                ;;
            4)
                submenu=false
                ;;
            *)
                log_error "Invalid option"
                press_enter
                ;;
        esac
    done
}

# =============================================================================
# FIREWALL MENU
# =============================================================================

firewall_menu() {
    local submenu=true

    while $submenu; do
        show_menu "Firewall Management (UFW)" \
            "Show firewall status" \
            "Allow port" \
            "Deny port" \
            "Remove rule" \
            "Enable/Disable firewall" \
            "Back to main menu"

        case $MENU_CHOICE in
            1)
                show_firewall_status || true
                press_enter
                ;;
            2)
                local port proto
                read -r -p "Port number: " port
                read -r -p "Protocol (tcp/udp, empty for both): " proto
                allow_port "$port" "$proto" || true
                press_enter
                ;;
            3)
                local port proto
                read -r -p "Port number: " port
                read -r -p "Protocol (tcp/udp, empty for both): " proto
                deny_port "$port" "$proto" || true
                press_enter
                ;;
            4)
                remove_rule || true
                press_enter
                ;;
            5)
                toggle_firewall || true
                press_enter
                ;;
            6)
                submenu=false
                ;;
            *)
                log_error "Invalid option"
                press_enter
                ;;
        esac
    done
}

# =============================================================================
# FAIL2BAN MENU
# =============================================================================

fail2ban_menu() {
    local submenu=true

    while $submenu; do
        show_menu "Fail2Ban Management" \
            "Show Fail2Ban status" \
            "Show banned IPs" \
            "Unban IP address" \
            "Back to main menu"

        case $MENU_CHOICE in
            1)
                show_fail2ban_status || true
                press_enter
                ;;
            2)
                show_banned || true
                press_enter
                ;;
            3)
                local ip
                show_banned || true
                echo ""
                read -r -p "IP address to unban: " ip
                unban_ip "$ip" || true
                press_enter
                ;;
            4)
                submenu=false
                ;;
            *)
                log_error "Invalid option"
                press_enter
                ;;
        esac
    done
}

# =============================================================================
# LOG VIEWER MENU
# =============================================================================

log_menu() {
    local submenu=true

    while $submenu; do
        show_menu "Log Viewer" \
            "Show Apache errors" \
            "Show Apache access log" \
            "Show MySQL errors" \
            "Show audit log" \
            "Search in logs" \
            "Back to main menu"

        case $MENU_CHOICE in
            1)
                local domain lines
                read -r -p "Domain (empty for global): " domain
                read -r -p "Lines to show [$ST_LOG_LINES]: " lines
                show_apache_errors "$domain" "${lines:-$ST_LOG_LINES}" || true
                press_enter
                ;;
            2)
                local domain lines
                read -r -p "Domain (empty for global): " domain
                read -r -p "Lines to show [$ST_LOG_LINES]: " lines
                show_apache_access "$domain" "${lines:-$ST_LOG_LINES}" || true
                press_enter
                ;;
            3)
                local lines
                read -r -p "Lines to show [$ST_LOG_LINES]: " lines
                show_mysql_errors "${lines:-$ST_LOG_LINES}" || true
                press_enter
                ;;
            4)
                local filter lines
                read -r -p "Filter (empty for all): " filter
                read -r -p "Lines to show [$ST_LOG_LINES]: " lines
                show_audit_log_entries "${lines:-$ST_LOG_LINES}" "$filter" || true
                press_enter
                ;;
            5)
                local pattern lines
                read -r -p "Search pattern: " pattern
                read -r -p "Max results [$ST_LOG_LINES]: " lines
                search_logs "$pattern" "${lines:-$ST_LOG_LINES}" || true
                press_enter
                ;;
            6)
                submenu=false
                ;;
            *)
                log_error "Invalid option"
                press_enter
                ;;
        esac
    done
}

# =============================================================================
# MAIN MENU
# =============================================================================

main_menu() {
    local running=true

    while $running; do
        show_menu "Server Tools v${ST_VERSION}" \
            "Database Management" \
            "Virtual Host Management" \
            "SSL Certificate Management" \
            "Cron Job Management" \
            "Firewall Management" \
            "Fail2Ban" \
            "Log Viewer" \
            "System Status" \
            "Exit"

        case $MENU_CHOICE in
            1) database_menu ;;
            2) vhost_menu ;;
            3) ssl_menu ;;
            4) cron_menu ;;
            5) firewall_menu ;;
            6) fail2ban_menu ;;
            7) log_menu ;;
            8)
                show_full_status
                press_enter
                ;;
            9)
                echo "Goodbye!"
                running=false
                ;;
            *)
                log_error "Invalid option"
                press_enter
                ;;
        esac
    done
}
