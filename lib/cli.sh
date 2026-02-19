#!/bin/bash
# CLI library: non-interactive command-line interface
#
# Maps CLI subcommands to high-level operations from other modules.
# Provides argument parsing with --name, --value style flags.

[[ -n "${_CLI_SOURCED:-}" ]] && return
_CLI_SOURCED=1

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
# CLI HELPERS
# =============================================================================

# Show usage for a subcommand and exit
cli_usage() {
    local command="$1"
    shift
    echo "Usage: server-tools $command $*"
    exit 1
}

# =============================================================================
# DATABASE CLI
# =============================================================================

cli_database() {
    local action="${1:-}"
    shift 2>/dev/null || true

    case "$action" in
        create)
            local name="" user="" password=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --name)
                        name="$2"
                        shift 2
                        ;;
                    --user)
                        user="$2"
                        shift 2
                        ;;
                    --password)
                        password="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$name" || -z "$user" ]] && cli_usage "db create" "--name <db> --user <user> [--password <pass>]"
            create_database "$name" "$user" "$password"
            ;;
        create-for-user)
            local name="" user=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --name)
                        name="$2"
                        shift 2
                        ;;
                    --user)
                        user="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$name" || -z "$user" ]] && cli_usage "db create-for-user" "--name <db> --user <user>"
            create_db_for_user "$name" "$user"
            ;;
        delete)
            local name="" user="" drop_user="false"
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --name)
                        name="$2"
                        shift 2
                        ;;
                    --user)
                        user="$2"
                        shift 2
                        ;;
                    --drop-user)
                        drop_user="true"
                        shift
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$name" ]] && cli_usage "db delete" "--name <db> [--user <user>] [--drop-user]"
            if [[ "$drop_user" == "true" ]]; then
                delete_database "$name" "$user" "true"
            else
                delete_database_keep_user "$name" "$user"
            fi
            ;;
        backup)
            local name=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --name)
                        name="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$name" ]] && cli_usage "db backup" "--name <db>"
            backup_database "$name"
            ;;
        backup-all)
            backup_all_databases
            ;;
        restore)
            local name="" file=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --name)
                        name="$2"
                        shift 2
                        ;;
                    --file)
                        file="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$name" || -z "$file" ]] && cli_usage "db restore" "--name <db> --file <path>"
            restore_database "$name" "$file"
            ;;
        import)
            local name="" file=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --name)
                        name="$2"
                        shift 2
                        ;;
                    --file)
                        file="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$name" || -z "$file" ]] && cli_usage "db import" "--name <db> --file <path>"
            import_database "$name" "$file"
            ;;
        export)
            local name="" output=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --name)
                        name="$2"
                        shift 2
                        ;;
                    --output)
                        output="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$name" ]] && cli_usage "db export" "--name <db> [--output <path>]"
            export_db_to_file "$name" "$output"
            ;;
        list)
            list_databases
            ;;
        info)
            local name=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --name)
                        name="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$name" ]] && cli_usage "db info" "--name <db>"
            show_db_info "$name"
            ;;
        grant)
            local name="" user="" level="all"
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --name)
                        name="$2"
                        shift 2
                        ;;
                    --user)
                        user="$2"
                        shift 2
                        ;;
                    --level)
                        level="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$name" || -z "$user" ]] && cli_usage "db grant" "--name <db> --user <user> [--level all|readonly|readwrite]"
            case "$level" in
                readonly) grant_user_readonly "$name" "$user" ;;
                readwrite) grant_user_readwrite "$name" "$user" ;;
                all) assign_db_to_user "$name" "$user" ;;
                *) die "Invalid grant level: $level (use: all, readonly, readwrite)" ;;
            esac
            ;;
        grants)
            local user=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --user)
                        user="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$user" ]] && cli_usage "db grants" "--user <user>"
            show_grants "$user"
            ;;
        --help | -h | "")
            cat <<EOF
Usage: server-tools db <action> [options]

Actions:
  create          Create database and user
  create-for-user Create database for existing user
  delete          Delete database (optionally with user)
  backup          Backup a single database
  backup-all      Backup all databases
  restore         Restore from backup file
  import          Import SQL file
  export          Export database to file
  list            List all databases
  info            Show database details
  grant           Grant access to user
  grants          Show user grants

Run 'server-tools db <action> --help' for details.
EOF
            ;;
        *)
            die "Unknown db action: $action. Use 'server-tools db --help'"
            ;;
    esac
}

# =============================================================================
# VHOST CLI
# =============================================================================

cli_vhost() {
    local action="${1:-}"
    shift 2>/dev/null || true

    case "$action" in
        create)
            local domain="" php="" aliases="" docroot=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --domain)
                        domain="$2"
                        shift 2
                        ;;
                    --php)
                        php="$2"
                        shift 2
                        ;;
                    --aliases)
                        aliases="$2"
                        shift 2
                        ;;
                    --docroot)
                        docroot="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$domain" ]] && cli_usage "vhost create" "--domain <domain> [--php <version>] [--aliases <aliases>]"
            create_vhost "$domain" "$aliases" "${php:-$ST_DEFAULT_PHP_VERSION}" "$docroot"
            ;;
        delete)
            local domain=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --domain)
                        domain="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$domain" ]] && cli_usage "vhost delete" "--domain <domain>"
            delete_vhost "$domain"
            ;;
        list)
            list_vhosts
            ;;
        php)
            local domain="" version=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --domain)
                        domain="$2"
                        shift 2
                        ;;
                    --version)
                        version="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$domain" || -z "$version" ]] && cli_usage "vhost php" "--domain <domain> --version <php>"
            change_php_version "$domain" "$version"
            ;;
        info)
            local domain=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --domain)
                        domain="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$domain" ]] && cli_usage "vhost info" "--domain <domain>"
            show_vhost_info "$domain"
            ;;
        redirect)
            local from="" to="" code="301"
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --from)
                        from="$2"
                        shift 2
                        ;;
                    --to)
                        to="$2"
                        shift 2
                        ;;
                    --code)
                        code="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$from" || -z "$to" ]] && cli_usage "vhost redirect" "--from <domain> --to <url> [--code 301|302]"
            create_redirect "$from" "$to" "$code"
            ;;
        --help | -h | "")
            cat <<EOF
Usage: server-tools vhost <action> [options]

Actions:
  create    Create virtual host
  delete    Delete virtual host
  list      List virtual hosts
  php       Change PHP version
  info      Show vhost details
  redirect  Create domain redirect

Run 'server-tools vhost <action> --help' for details.
EOF
            ;;
        *)
            die "Unknown vhost action: $action. Use 'server-tools vhost --help'"
            ;;
    esac
}

# =============================================================================
# SSL CLI
# =============================================================================

cli_ssl() {
    local action="${1:-}"
    shift 2>/dev/null || true

    case "$action" in
        create)
            local domain="" email=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --domain)
                        domain="$2"
                        shift 2
                        ;;
                    --email)
                        email="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$domain" ]] && cli_usage "ssl create" "--domain <domain> [--email <email>]"
            setup_ssl "$domain" "$email"
            ;;
        delete)
            local domain=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --domain)
                        domain="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$domain" ]] && cli_usage "ssl delete" "--domain <domain>"
            delete_ssl "$domain"
            ;;
        wildcard)
            local domain="" provider=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --domain)
                        domain="$2"
                        shift 2
                        ;;
                    --provider)
                        provider="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$domain" ]] && cli_usage "ssl wildcard" "--domain <domain> [--provider <name>]"
            setup_wildcard_ssl "$domain" "$provider"
            ;;
        list)
            list_certificates
            ;;
        check)
            local days=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --days)
                        days="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            check_expiring_soon "${days:-30}"
            ;;
        renew)
            setup_ssl_renewal
            ;;
        --help | -h | "")
            cat <<EOF
Usage: server-tools ssl <action> [options]

Actions:
  create    Create SSL certificate
  delete    Delete SSL certificate
  wildcard  Create wildcard certificate (DNS challenge)
  list      List all certificates
  check     Check expiring certificates
  renew     Setup automatic renewal

Run 'server-tools ssl <action> --help' for details.
EOF
            ;;
        *)
            die "Unknown ssl action: $action. Use 'server-tools ssl --help'"
            ;;
    esac
}

# =============================================================================
# CRON CLI
# =============================================================================

cli_cron() {
    local action="${1:-}"
    shift 2>/dev/null || true

    case "$action" in
        add)
            local schedule="" command="" name=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --schedule)
                        schedule="$2"
                        shift 2
                        ;;
                    --command)
                        command="$2"
                        shift 2
                        ;;
                    --name)
                        name="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$schedule" || -z "$command" || -z "$name" ]] \
                && cli_usage "cron add" "--schedule '<cron>' --command '<cmd>' --name '<name>'"
            add_cron "$schedule" "$command" "$name"
            ;;
        remove)
            local pattern=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --pattern)
                        pattern="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$pattern" ]] && cli_usage "cron remove" "--pattern <search>"
            remove_cron "$pattern"
            ;;
        list)
            list_crons
            ;;
        --help | -h | "")
            cat <<EOF
Usage: server-tools cron <action> [options]

Actions:
  add     Add cron job
  remove  Remove cron job
  list    List cron jobs

Run 'server-tools cron <action> --help' for details.
EOF
            ;;
        *)
            die "Unknown cron action: $action. Use 'server-tools cron --help'"
            ;;
    esac
}

# =============================================================================
# STATUS CLI
# =============================================================================

cli_status() {
    show_full_status
}

# =============================================================================
# LOGS CLI
# =============================================================================

cli_logs() {
    local action="${1:-}"
    shift 2>/dev/null || true

    case "$action" in
        apache)
            local domain="" lines=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --domain)
                        domain="$2"
                        shift 2
                        ;;
                    --lines)
                        lines="$2"
                        shift 2
                        ;;
                    --errors)
                        action="apache-errors"
                        shift
                        ;;
                    *) shift ;;
                esac
            done
            if [[ "$action" == "apache-errors" ]]; then
                show_apache_errors "$domain" "${lines:-$ST_LOG_LINES}"
            else
                show_apache_access "$domain" "${lines:-$ST_LOG_LINES}"
            fi
            ;;
        apache-errors)
            local domain="" lines=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --domain)
                        domain="$2"
                        shift 2
                        ;;
                    --lines)
                        lines="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            show_apache_errors "$domain" "${lines:-$ST_LOG_LINES}"
            ;;
        mysql)
            local lines=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --lines)
                        lines="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            show_mysql_errors "${lines:-$ST_LOG_LINES}"
            ;;
        audit)
            local lines="" filter=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --lines)
                        lines="$2"
                        shift 2
                        ;;
                    --filter)
                        filter="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            show_audit_log_entries "${lines:-$ST_LOG_LINES}" "$filter"
            ;;
        search)
            local pattern="" lines=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --pattern)
                        pattern="$2"
                        shift 2
                        ;;
                    --lines)
                        lines="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$pattern" ]] && cli_usage "logs search" "--pattern <text> [--lines <n>]"
            search_logs "$pattern" "${lines:-$ST_LOG_LINES}"
            ;;
        --help | -h | "")
            cat <<EOF
Usage: server-tools logs <action> [options]

Actions:
  apache        Show Apache access log
  apache-errors Show Apache error log
  mysql         Show MySQL error log
  audit         Show audit log
  search        Search across all logs

Common options:
  --domain <domain>   Domain filter (Apache logs)
  --lines <n>         Number of lines (default: $ST_LOG_LINES)

Run 'server-tools logs <action> --help' for details.
EOF
            ;;
        *)
            die "Unknown logs action: $action. Use 'server-tools logs --help'"
            ;;
    esac
}

# =============================================================================
# FIREWALL CLI
# =============================================================================

cli_firewall() {
    local action="${1:-}"
    shift 2>/dev/null || true

    case "$action" in
        status)
            show_firewall_status
            ;;
        allow)
            local port="" proto=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --port)
                        port="$2"
                        shift 2
                        ;;
                    --proto)
                        proto="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$port" ]] && cli_usage "firewall allow" "--port <port> [--proto tcp|udp]"
            allow_port "$port" "$proto"
            ;;
        deny)
            local port="" proto=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --port)
                        port="$2"
                        shift 2
                        ;;
                    --proto)
                        proto="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$port" ]] && cli_usage "firewall deny" "--port <port> [--proto tcp|udp]"
            deny_port "$port" "$proto"
            ;;
        --help | -h | "")
            cat <<EOF
Usage: server-tools firewall <action> [options]

Actions:
  status  Show firewall status
  allow   Allow a port
  deny    Deny a port

Run 'server-tools firewall <action> --help' for details.
EOF
            ;;
        *)
            die "Unknown firewall action: $action. Use 'server-tools firewall --help'"
            ;;
    esac
}

# =============================================================================
# FAIL2BAN CLI
# =============================================================================

cli_fail2ban() {
    local action="${1:-}"
    shift 2>/dev/null || true

    case "$action" in
        status)
            show_fail2ban_status
            ;;
        banned)
            show_banned
            ;;
        unban)
            local ip=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --ip)
                        ip="$2"
                        shift 2
                        ;;
                    *) shift ;;
                esac
            done
            [[ -z "$ip" ]] && cli_usage "fail2ban unban" "--ip <address>"
            unban_ip "$ip"
            ;;
        --help | -h | "")
            cat <<EOF
Usage: server-tools fail2ban <action> [options]

Actions:
  status  Show Fail2Ban status
  banned  Show all banned IPs
  unban   Unban an IP address

Run 'server-tools fail2ban <action> --help' for details.
EOF
            ;;
        *)
            die "Unknown fail2ban action: $action. Use 'server-tools fail2ban --help'"
            ;;
    esac
}


