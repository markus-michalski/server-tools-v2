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

# =============================================================================
# MENU HELPERS
# =============================================================================

# Display a menu and read user choice
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
            "List databases" \
            "Show database info" \
            "Back to main menu"

        case $MENU_CHOICE in
            1)
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
                read -r -p "Database name: " db_name
                read -r -p "Existing user: " db_user
                create_db_for_user "$db_name" "$db_user" || true
                press_enter
                ;;
            3)
                list_databases || true
                echo ""
                read -r -p "Database to delete: " db_name
                read -r -p "User to revoke access from (empty to skip): " db_user
                delete_database_keep_user "$db_name" "$db_user" || true
                press_enter
                ;;
            4)
                list_databases || true
                echo ""
                read -r -p "Database to delete: " db_name
                read -r -p "User to delete: " db_user
                delete_database "$db_name" "$db_user" "true" || true
                press_enter
                ;;
            5)
                read -r -p "Database name: " db_name
                read -r -p "User to grant access: " db_user
                assign_db_to_user "$db_name" "$db_user" || true
                press_enter
                ;;
            6)
                list_databases || true
                echo ""
                read -r -p "Database name: " db_name
                read -r -p "Current user: " old_user
                read -r -p "New user: " new_user
                reassign_db_to_user "$db_name" "$old_user" "$new_user" || true
                press_enter
                ;;
            7)
                list_databases || true
                press_enter
                ;;
            8)
                read -r -p "Database name: " db_name
                show_db_info "$db_name" || true
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
            "Back to main menu"

        case $MENU_CHOICE in
            1)
                read -r -p "Domain: " domain
                read -r -p "Aliases (space-separated, empty for none): " aliases
                local available_php
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
                list_vhosts || true
                echo ""
                local available_php
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
                read -r -p "Domain: " domain
                show_vhost_info "$domain" || true
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
# SSL MENU
# =============================================================================

ssl_menu() {
    local submenu=true

    while $submenu; do
        show_menu "SSL Certificate Management" \
            "Create SSL certificate" \
            "Delete SSL certificate" \
            "List certificates" \
            "Check expiring certificates" \
            "Setup automatic renewal" \
            "Recreate all certificates (Apache mode)" \
            "Back to main menu"

        case $MENU_CHOICE in
            1)
                list_vhosts || true
                echo ""
                read -r -p "Domain: " domain
                read -r -p "Email (empty for default): " email
                setup_ssl "$domain" "$email" || true
                press_enter
                ;;
            2)
                list_certificates || true
                echo ""
                read -r -p "Domain: " domain
                delete_ssl "$domain" || true
                press_enter
                ;;
            3)
                list_certificates || true
                press_enter
                ;;
            4)
                read -r -p "Days threshold [30]: " days
                check_expiring_soon "${days:-30}" || true
                press_enter
                ;;
            5)
                setup_ssl_renewal || true
                press_enter
                ;;
            6)
                recreate_all_ssl || true
                press_enter
                ;;
            7)
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
                read -r -p "Schedule (e.g. '0 4 * * *'): " schedule
                read -r -p "Command: " command
                read -r -p "Job name: " name
                add_cron "$schedule" "$command" "$name" || true
                press_enter
                ;;
            2)
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
# SYSTEM INFO
# =============================================================================

system_info() {
    clear
    print_header "System Information"

    echo "System:"
    echo "  Hostname:  $(hostname 2>/dev/null || echo 'unknown')"
    echo "  Apache:    $(apache2 -v 2>/dev/null | head -1 | cut -d' ' -f3 || echo 'not installed')"
    echo "  MySQL:     $(mysql --version 2>/dev/null | cut -d' ' -f6 | cut -d',' -f1 || echo 'not installed')"
    echo ""

    echo "Configuration:"
    show_config
    echo ""

    echo "Backups:"
    list_backups
    echo ""

    echo "PHP Versions:"
    local available_php
    available_php=$(detect_php_versions)
    if [[ -n "$available_php" ]]; then
        for version in $available_php; do
            echo "  PHP $version: $("php${version}" -v 2>/dev/null | head -1 || echo 'version info unavailable')"
        done
    else
        echo "  No PHP-FPM versions found"
    fi
    echo ""

    echo "Active Virtual Hosts:"
    if [[ -d "/etc/apache2/sites-enabled" ]]; then
        local vhost_found=0
        for f in /etc/apache2/sites-enabled/*.conf; do
            [[ -f "$f" ]] || continue
            echo "  - $(basename "$f" .conf)"
            vhost_found=1
        done
        [[ $vhost_found -eq 0 ]] && echo "  (none)"
    else
        echo "  Apache not installed"
    fi
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
            "System Information" \
            "Exit"

        case $MENU_CHOICE in
            1) database_menu ;;
            2) vhost_menu ;;
            3) ssl_menu ;;
            4) cron_menu ;;
            5)
                system_info
                press_enter
                ;;
            6)
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
