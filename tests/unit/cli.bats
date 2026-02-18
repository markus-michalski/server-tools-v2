#!/usr/bin/env bats

load ../test_helper

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR NO_COLOR=1
    export ST_CONFIG_FILE="${TEST_TMPDIR}/config"
    export ST_CREDENTIAL_DIR="${TEST_TMPDIR}/credentials"
    export ST_AUDIT_LOG="${TEST_TMPDIR}/audit.log"
    export ST_BACKUP_DIR="${TEST_TMPDIR}/backups"
    export ST_DB_BACKUP_DIR="${TEST_TMPDIR}/db-backups"
    export ST_AUTO_BACKUP=true
    export ST_BACKUP_RETENTION_DAYS=30
    export ST_AUDIT_LOGGING=true
    export ST_PASSWORD_LENGTH=25
    export ST_PASSWORD_MIN_LENGTH=12
    export ST_DEFAULT_PHP_VERSION=8.3
    export ST_PHP_VERSIONS_TO_SCAN="7.4 8.0 8.1 8.2 8.3 8.4"
    export ST_APACHE_SERVER_ADMIN="webmaster@localhost"
    export ST_ALLOWED_DOCROOT_PATHS="/var/www:/srv/www"
    export ST_CREDENTIAL_FILE_PERMISSIONS=600
    export ST_CERTBOT_EMAIL="admin@example.com"
    export ST_APACHE_LOG_DIR="${TEST_TMPDIR}/apache-logs"
    export ST_MYSQL_LOG_FILE="${TEST_TMPDIR}/mysql-error.log"
    export ST_LOG_LINES=50
    export ST_DNS_PROVIDER=""
    export ST_DNS_CREDENTIALS_FILE=""
    export ST_MONITORED_SERVICES="apache2 mysql"
    export ST_DEFAULT_CHARSET="utf8mb4"
    export ST_DEFAULT_COLLATION="utf8mb4_unicode_ci"
    mkdir -p "${ST_CREDENTIAL_DIR}" "${ST_BACKUP_DIR}" "${ST_DB_BACKUP_DIR}" "${ST_APACHE_LOG_DIR}"
    source_lib "cli"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# =============================================================================
# CLI HELPERS
# =============================================================================

@test "cli_usage prints usage and exits with 1" {
    run cli_usage "db create" "--name <db> --user <user>"
    assert_failure
    assert_output "Usage: server-tools db create --name <db> --user <user>"
}

# =============================================================================
# DATABASE CLI - help and argument validation
# =============================================================================

@test "cli_database shows help when no action given" {
    run cli_database
    assert_success
    assert_output --partial "Usage: server-tools db"
    assert_output --partial "create"
    assert_output --partial "backup"
    assert_output --partial "restore"
}

@test "cli_database shows help with --help flag" {
    run cli_database --help
    assert_success
    assert_output --partial "Usage: server-tools db"
}

@test "cli_database create fails without required args" {
    run cli_database create
    assert_failure
    assert_output --partial "Usage: server-tools db create"
}

@test "cli_database create fails without --user" {
    run cli_database create --name mydb
    assert_failure
    assert_output --partial "Usage: server-tools db create"
}

@test "cli_database delete fails without --name" {
    run cli_database delete
    assert_failure
    assert_output --partial "Usage: server-tools db delete"
}

@test "cli_database backup fails without --name" {
    run cli_database backup
    assert_failure
    assert_output --partial "Usage: server-tools db backup"
}

@test "cli_database restore fails without required args" {
    run cli_database restore --name mydb
    assert_failure
    assert_output --partial "Usage: server-tools db restore"
}

@test "cli_database import fails without required args" {
    run cli_database import --file dump.sql
    assert_failure
    assert_output --partial "Usage: server-tools db import"
}

@test "cli_database export fails without --name" {
    run cli_database export
    assert_failure
    assert_output --partial "Usage: server-tools db export"
}

@test "cli_database info fails without --name" {
    run cli_database info
    assert_failure
    assert_output --partial "Usage: server-tools db info"
}

@test "cli_database grant fails without required args" {
    run cli_database grant --name mydb
    assert_failure
    assert_output --partial "Usage: server-tools db grant"
}

@test "cli_database grants fails without --user" {
    run cli_database grants
    assert_failure
    assert_output --partial "Usage: server-tools db grants"
}

@test "cli_database rejects unknown action" {
    run cli_database nonexistent
    assert_failure
    assert_output --partial "Unknown db action"
}

# =============================================================================
# VHOST CLI
# =============================================================================

@test "cli_vhost shows help when no action given" {
    run cli_vhost
    assert_success
    assert_output --partial "Usage: server-tools vhost"
    assert_output --partial "create"
    assert_output --partial "delete"
    assert_output --partial "redirect"
}

@test "cli_vhost create fails without --domain" {
    run cli_vhost create
    assert_failure
    assert_output --partial "Usage: server-tools vhost create"
}

@test "cli_vhost delete fails without --domain" {
    run cli_vhost delete
    assert_failure
    assert_output --partial "Usage: server-tools vhost delete"
}

@test "cli_vhost php fails without required args" {
    run cli_vhost php --domain example.com
    assert_failure
    assert_output --partial "Usage: server-tools vhost php"
}

@test "cli_vhost info fails without --domain" {
    run cli_vhost info
    assert_failure
    assert_output --partial "Usage: server-tools vhost info"
}

@test "cli_vhost redirect fails without required args" {
    run cli_vhost redirect --from old.com
    assert_failure
    assert_output --partial "Usage: server-tools vhost redirect"
}

@test "cli_vhost rejects unknown action" {
    run cli_vhost nonexistent
    assert_failure
    assert_output --partial "Unknown vhost action"
}

# =============================================================================
# SSL CLI
# =============================================================================

@test "cli_ssl shows help when no action given" {
    run cli_ssl
    assert_success
    assert_output --partial "Usage: server-tools ssl"
    assert_output --partial "create"
    assert_output --partial "wildcard"
}

@test "cli_ssl create fails without --domain" {
    run cli_ssl create
    assert_failure
    assert_output --partial "Usage: server-tools ssl create"
}

@test "cli_ssl delete fails without --domain" {
    run cli_ssl delete
    assert_failure
    assert_output --partial "Usage: server-tools ssl delete"
}

@test "cli_ssl wildcard fails without --domain" {
    run cli_ssl wildcard
    assert_failure
    assert_output --partial "Usage: server-tools ssl wildcard"
}

@test "cli_ssl rejects unknown action" {
    run cli_ssl nonexistent
    assert_failure
    assert_output --partial "Unknown ssl action"
}

# =============================================================================
# CRON CLI
# =============================================================================

@test "cli_cron shows help when no action given" {
    run cli_cron
    assert_success
    assert_output --partial "Usage: server-tools cron"
    assert_output --partial "add"
    assert_output --partial "remove"
}

@test "cli_cron add fails without required args" {
    run cli_cron add --schedule "0 4 * * *" --command "/bin/true"
    assert_failure
    assert_output --partial "Usage: server-tools cron add"
}

@test "cli_cron remove fails without --pattern" {
    run cli_cron remove
    assert_failure
    assert_output --partial "Usage: server-tools cron remove"
}

@test "cli_cron rejects unknown action" {
    run cli_cron nonexistent
    assert_failure
    assert_output --partial "Unknown cron action"
}

# =============================================================================
# LOGS CLI
# =============================================================================

@test "cli_logs shows help when no action given" {
    run cli_logs
    assert_success
    assert_output --partial "Usage: server-tools logs"
    assert_output --partial "apache"
    assert_output --partial "mysql"
    assert_output --partial "search"
}

@test "cli_logs search fails without --pattern" {
    run cli_logs search
    assert_failure
    assert_output --partial "Usage: server-tools logs search"
}

@test "cli_logs rejects unknown action" {
    run cli_logs nonexistent
    assert_failure
    assert_output --partial "Unknown logs action"
}

# =============================================================================
# FIREWALL CLI
# =============================================================================

@test "cli_firewall shows help when no action given" {
    run cli_firewall
    assert_success
    assert_output --partial "Usage: server-tools firewall"
    assert_output --partial "status"
    assert_output --partial "allow"
    assert_output --partial "deny"
}

@test "cli_firewall allow fails without --port" {
    run cli_firewall allow
    assert_failure
    assert_output --partial "Usage: server-tools firewall allow"
}

@test "cli_firewall deny fails without --port" {
    run cli_firewall deny
    assert_failure
    assert_output --partial "Usage: server-tools firewall deny"
}

@test "cli_firewall rejects unknown action" {
    run cli_firewall nonexistent
    assert_failure
    assert_output --partial "Unknown firewall action"
}

# =============================================================================
# FAIL2BAN CLI
# =============================================================================

@test "cli_fail2ban shows help when no action given" {
    run cli_fail2ban
    assert_success
    assert_output --partial "Usage: server-tools fail2ban"
    assert_output --partial "status"
    assert_output --partial "banned"
    assert_output --partial "unban"
}

@test "cli_fail2ban unban fails without --ip" {
    run cli_fail2ban unban
    assert_failure
    assert_output --partial "Usage: server-tools fail2ban unban"
}

@test "cli_fail2ban rejects unknown action" {
    run cli_fail2ban nonexistent
    assert_failure
    assert_output --partial "Unknown fail2ban action"
}

# =============================================================================
# CLI ARGUMENT ROUTING (mocked operations)
# =============================================================================

@test "cli_database create routes to create_database with parsed args" {
    # Override create_database to capture args
    create_database() { echo "CALLED: db=$1 user=$2 pass=$3"; }
    export -f create_database

    run cli_database create --name testdb --user testuser --password secret123
    assert_success
    assert_output "CALLED: db=testdb user=testuser pass=secret123"
}

@test "cli_database backup routes to backup_database" {
    backup_database() { echo "BACKUP: $1"; }
    export -f backup_database

    run cli_database backup --name mydb
    assert_success
    assert_output "BACKUP: mydb"
}

@test "cli_database grant routes to correct level" {
    grant_user_readonly() { echo "READONLY: db=$1 user=$2"; }
    export -f grant_user_readonly

    run cli_database grant --name mydb --user reader --level readonly
    assert_success
    assert_output "READONLY: db=mydb user=reader"
}

@test "cli_database grant routes readwrite level" {
    grant_user_readwrite() { echo "READWRITE: db=$1 user=$2"; }
    export -f grant_user_readwrite

    run cli_database grant --name mydb --user writer --level readwrite
    assert_success
    assert_output "READWRITE: db=mydb user=writer"
}

@test "cli_database grant rejects invalid level" {
    run cli_database grant --name mydb --user u --level superadmin
    assert_failure
    assert_output --partial "Invalid grant level"
}

@test "cli_vhost create routes with parsed args" {
    create_vhost() { echo "VHOST: domain=$1 aliases=$2 php=$3"; }
    export -f create_vhost

    run cli_vhost create --domain example.com --php 8.3 --aliases "www.example.com"
    assert_success
    assert_output "VHOST: domain=example.com aliases=www.example.com php=8.3"
}

@test "cli_vhost redirect routes with parsed args" {
    create_redirect() { echo "REDIRECT: from=$1 to=$2 code=$3"; }
    export -f create_redirect

    run cli_vhost redirect --from old.com --to https://new.com --code 302
    assert_success
    assert_output "REDIRECT: from=old.com to=https://new.com code=302"
}

@test "cli_ssl create routes with parsed args" {
    setup_ssl() { echo "SSL: domain=$1 email=$2"; }
    export -f setup_ssl

    run cli_ssl create --domain example.com --email test@example.com
    assert_success
    assert_output "SSL: domain=example.com email=test@example.com"
}

@test "cli_firewall allow routes with parsed args" {
    allow_port() { echo "ALLOW: port=$1 proto=$2"; }
    export -f allow_port

    run cli_firewall allow --port 8080 --proto tcp
    assert_success
    assert_output "ALLOW: port=8080 proto=tcp"
}

@test "cli_fail2ban unban routes with parsed IP" {
    unban_ip() { echo "UNBAN: $1"; }
    export -f unban_ip

    run cli_fail2ban unban --ip 192.168.1.100
    assert_success
    assert_output "UNBAN: 192.168.1.100"
}

@test "cli_logs search routes with parsed args" {
    search_logs() { echo "SEARCH: pattern=$1 lines=$2"; }
    export -f search_logs

    run cli_logs search --pattern "error" --lines 100
    assert_success
    assert_output "SEARCH: pattern=error lines=100"
}

@test "cli_cron add routes with parsed args" {
    add_cron() { echo "CRON: schedule=$1 command=$2 name=$3"; }
    export -f add_cron

    run cli_cron add --schedule "0 4 * * *" --command "/usr/local/bin/backup.sh" --name "daily-backup"
    assert_success
    assert_output "CRON: schedule=0 4 * * * command=/usr/local/bin/backup.sh name=daily-backup"
}

# =============================================================================
# AUTO-CONFIRM (--yes flag)
# =============================================================================

@test "confirm returns true when ST_AUTO_CONFIRM is set" {
    export ST_AUTO_CONFIRM="true"
    run confirm "Delete everything?"
    assert_success
}

@test "confirm requires input when ST_AUTO_CONFIRM is not set" {
    unset ST_AUTO_CONFIRM
    # Pipe 'n' to simulate user declining
    run bash -c 'source "'"${PROJECT_ROOT}"'/lib/core.sh" && echo "n" | confirm "Continue?"'
    assert_failure
}
