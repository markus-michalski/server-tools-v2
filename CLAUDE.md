# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a simplified server administration tool written in Bash for managing web hosting environments. The tool provides a menu-driven interface for common server management tasks on Linux systems running Apache, MySQL, and PHP.

## Architecture

### Main Script Structure
- **Single-file architecture**: The entire tool is contained in `server-tools.sh`
- **Modular function organization**: Functions are grouped by functionality (database, vhost, SSL, cron)
- **Menu-driven interface**: Hierarchical menu system with interactive prompts
- **Installation mechanism**: Self-installing script that creates system-wide shortcuts

### Core Functional Modules

1. **Database Management** (`create_db`, `delete_db`, `list_databases`)
   - MySQL database and user creation/deletion
   - Credential storage in `/root/db-credentials/`
   - Auto-generated passwords using OpenSSL

2. **Virtual Host Management** (`create_vhost`, `delete_vhost`, `list_vhosts`)
   - Apache virtual host configuration
   - PHP-FPM integration with version selection (8.2, 8.3, 8.4)
   - Document root creation with proper www-data permissions
   - Security headers configuration

3. **SSL Certificate Management** (`setup_ssl`, `delete_ssl`)
   - Let's Encrypt integration via Certbot
   - Automatic Apache SSL configuration

4. **Cron Job Management** (`add_cron`, `remove_cron`, `list_crons`)
   - System-wide cron jobs in `/etc/cron.d/`
   - Interactive cron job search and removal

### Key Design Patterns

- **Root privilege checking**: All operations require root access
- **Interactive confirmations**: Destructive operations prompt for confirmation
- **Credential management**: Database credentials are securely stored and managed
- **Error handling**: Basic error checking with user feedback
- **File permissions**: Strict permission management (700/644/755) for security

## Installation and Usage

### Installation
```bash
# Install the tool system-wide
sudo ./server-tools.sh install
```

This creates shortcuts: `servertools`, `st`, `tools`, `server`

### Running
```bash
# Launch the interactive menu
sudo servertools
# or
sudo st
```

## System Dependencies

- **Operating System**: Linux (tested on Ubuntu/Debian)
- **Web Server**: Apache2 with mod_headers and mod_rewrite
- **Database**: MySQL/MariaDB with root access configured in `/root/.my.cnf`
- **PHP**: PHP-FPM versions 8.2, 8.3, 8.4
- **SSL**: Certbot with Apache plugin for Let's Encrypt certificates
- **Tools**: OpenSSL for password generation

## File System Layout

```
/root/
├── .my.cnf                    # MySQL root credentials
└── db-credentials/            # Database credential storage (700 permissions)
    └── [database_name].txt    # Individual database credentials

/var/www/
└── [domain]/
    ├── html/                  # Document root (www-data:www-data)
    │   └── index.php         # Welcome page with PHP info
    └── logs/                  # Apache logs (www-data:www-data)
        ├── access.log
        └── error.log

/etc/apache2/sites-available/
├── [domain].conf             # HTTP virtual host
└── [domain]-le-ssl.conf      # HTTPS virtual host (created by Certbot)

/etc/cron.d/
└── [job_name]                # System cron jobs
```

## Common Operations

### Database Operations
- Creates UTF8MB4 databases with dedicated users
- Stores credentials in `/root/db-credentials/[db_name].txt`
- Includes connection strings for PHP PDO and Symfony

### Virtual Host Operations
- Creates Apache virtual hosts with PHP-FPM integration
- Sets up proper directory structure with www-data ownership
- Configures security headers and logging
- Supports custom document roots

### SSL Operations
- Uses Let's Encrypt via Certbot for free SSL certificates
- Automatically configures Apache SSL virtual hosts
- Email defaults to `webmaster@[domain]`

## Security Considerations

- **Root access required**: All operations require root privileges
- **Credential protection**: Database credentials stored with 600 permissions
- **Directory permissions**: Strict permission management throughout
- **Security headers**: X-Content-Type-Options, X-Frame-Options, X-XSS-Protection configured
- **No sensitive data exposure**: Passwords are not logged or displayed after creation