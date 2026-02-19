# Server Tools v2

A modular Bash toolkit for managing MySQL databases, Apache virtual hosts, Let's Encrypt SSL certificates, and system cron jobs on Debian/Ubuntu servers.

## Features

- **Database Management** - Create/delete MySQL databases and users with secure credential storage
- **Virtual Host Management** - Apache vHosts with PHP-FPM, security headers, and PHP version switching
- **SSL Management** - Let's Encrypt certificates via Certbot with automatic renewal
- **Cron Management** - System-wide cron jobs via `/etc/cron.d`
- **Security** - Input validation, audit logging, automatic backups before destructive operations
- **Firewall Management** - UFW firewall rules via CLI and interactive menu
- **Fail2Ban Management** - Jail status, ban/unban IPs, configuration overview
- **Log Viewer** - View and search Apache, MySQL, and audit logs
- **System Status** - Overview of services, disk usage, and system health
- **Interactive Menu** - TUI-based menu system for easy server administration

## Requirements

- Debian/Ubuntu-based Linux
- Bash 4.4+
- Root access
- Apache 2.4+, MySQL/MariaDB, PHP-FPM (depending on features used)

## Installation

### Quick Install

```bash
git clone https://github.com/markusmichalski/server-tools-v2.git
cd server-tools-v2
git checkout "$(git tag -l 'v*' | sort -V | tail -1)"
sudo ./bin/server-tools install
```

> **Note:** Always check out the latest release tag. The `main` branch may contain untested changes.
> Available releases: [GitHub Releases](https://github.com/markusmichalski/server-tools-v2/releases)

This installs:
- Libraries to `/usr/local/lib/server-tools/`
- Binary to `/usr/local/bin/server-tools`
- Shortcuts: `st`, `servertools`
- Default config to `/etc/server-tools/config`

### Updating

```bash
cd server-tools-v2
git pull --tags
git checkout "$(git tag -l 'v*' | sort -V | tail -1)"
sudo ./bin/server-tools install
```

### Manual Usage (without install)

```bash
git clone https://github.com/markusmichalski/server-tools-v2.git
cd server-tools-v2
git checkout "$(git tag -l 'v*' | sort -V | tail -1)"
sudo ./bin/server-tools
```

## Usage

```bash
# Start interactive menu
sudo server-tools

# Or use shortcuts
sudo st

# CLI options
server-tools --version     # Show version
server-tools --config      # Show current configuration
server-tools --help        # Show help
```

## Configuration

Configuration file: `/etc/server-tools/config`

Copy the example config and adjust:

```bash
sudo cp conf/server-tools.conf.example /etc/server-tools/config
sudo chmod 600 /etc/server-tools/config
sudo nano /etc/server-tools/config
```

Key settings:

| Variable | Default | Description |
|---|---|---|
| `ST_CREDENTIAL_DIR` | `/root/db-credentials` | Database credential file storage |
| `ST_DEFAULT_PHP_VERSION` | `8.3` | Default PHP version for new vHosts |
| `ST_CERTBOT_EMAIL` | `admin@example.com` | Default email for Let's Encrypt |
| `ST_PASSWORD_LENGTH` | `25` | Generated password length |
| `ST_AUTO_BACKUP` | `true` | Auto-backup before destructive operations |
| `ST_AUDIT_LOGGING` | `true` | Enable security audit logging |

See [conf/server-tools.conf.example](conf/server-tools.conf.example) for all options.

## Architecture

The project follows a **Composable Building Blocks** pattern. Each module has:

- **Building blocks** - Small, atomic functions that do one thing (testable in isolation)
- **High-level operations** - Compose building blocks into complete workflows

```
lib/
├── core.sh        # Logging, error handling, dependency checks
├── config.sh      # Configuration loading, validation, defaults
├── security.sh    # Input validation, escaping, audit logging
├── backup.sh      # Backup creation, cleanup, listing
├── database.sh    # MySQL database & user CRUD
├── vhost.sh       # Apache virtual host management
├── ssl.sh         # Let's Encrypt certificate management
├── cron.sh        # System cron job management
├── status.sh      # System status overview
├── log.sh         # Log viewer and search
├── firewall.sh    # UFW firewall management
├── fail2ban.sh    # Fail2Ban jail management
├── cli.sh         # CLI argument parsing and routing
└── menu.sh        # Interactive TUI menus
```

### Adding New Features

The composable architecture makes adding features straightforward. Example: adding "create database for existing user" only requires composing existing building blocks:

```bash
create_db_for_user() {
    local db_name="$1" user="$2"
    validate_input "$db_name" "database" || return 1
    user_exists "$user" || { log_error "User does not exist"; return 1; }
    create_db_only "$db_name" || return 1
    grant_privileges "$db_name" "$user" || return 1
    log_info "Database '$db_name' granted to existing user '$user'"
}
```

Then add a menu entry - done.

## Database Credentials

When creating databases, credential files are saved to `ST_CREDENTIAL_DIR` (default: `/root/db-credentials/`). Each file includes:

- Database name, user, password
- MySQL CLI connection command
- PDO DSN
- Symfony `DATABASE_URL`

## Security

- All user input is validated before use (domains, database names, paths, emails)
- SQL injection attempts are blocked
- Path traversal attempts are blocked
- Credential files have restricted permissions (600)
- Audit logging tracks all administrative actions
- Automatic backups before destructive operations
- Apache config test before reload (with rollback on failure)

## Development

### Running Tests

```bash
# Setup BATS test framework (first time)
make setup-tests

# Run all tests
make test

# Run tests with verbose output
make test-verbose

# Run a specific test file
npx bats tests/unit/database.bats
```

### Linting

```bash
# Run ShellCheck
make lint

# Check formatting
make format-check

# Auto-format
make format

# Run all checks
make check
```

### Project Structure

```
server-tools-v2/
├── bin/server-tools              # Entry point
├── lib/*.sh                      # Libraries
├── tests/unit/*.bats             # BATS unit tests
├── conf/server-tools.conf.example
├── Makefile
└── .github/workflows/ci.yml     # CI pipeline
```

## Documentation

Detailed setup guides and usage instructions:

- [English](https://faq.markus-michalski.net/en/bash-scripts/server-tools)
- [Deutsch](https://faq.markus-michalski.net/de/bash-scripts/server-tools)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

[MIT](LICENSE) - Markus Michalski
