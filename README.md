# Server Tools V2

A simplified server administration tool for managing web hosting environments on Linux systems with Apache, MySQL, and PHP.

## Features

- **Database Management**: Create, delete, and list MySQL databases with auto-generated credentials
- **Virtual Host Management**: Apache virtual host creation with PHP-FPM integration  
- **SSL Certificate Management**: Let's Encrypt integration via Certbot
- **Cron Job Management**: System-wide cron job administration
- **Interactive Menu System**: User-friendly command-line interface

## Requirements

- Linux (Ubuntu/Debian recommended)
- Apache2 with mod_headers and mod_rewrite
- MySQL/MariaDB with root access configured in `/root/.my.cnf`
- PHP-FPM (versions 8.2, 8.3, 8.4)
- Root privileges

## Installation

1. Make the script executable:
   ```bash
   chmod +x server-tools.sh
   ```

2. Install system-wide:
   ```bash
   sudo ./server-tools.sh install
   ```

This creates convenient shortcuts: `servertools`, `st`, `tools`, `server`

## Usage

Launch the interactive menu:
```bash
sudo servertools
```
or
```bash
sudo st
```

## Core Features

### Database Management
- Creates UTF8MB4 databases with dedicated users
- Auto-generates secure passwords using OpenSSL
- Stores credentials in `/root/db-credentials/[database_name].txt`
- Includes PHP PDO and Symfony connection strings

### Virtual Host Management
- Apache virtual host configuration with security headers
- PHP-FPM integration with version selection (8.2, 8.3, 8.4)
- Automatic document root setup with proper www-data permissions
- Custom welcome page with PHP info

### SSL Certificate Management
- Free Let's Encrypt certificates via Certbot
- Automatic Apache SSL configuration
- Email defaults to `webmaster@[domain]`

### Cron Job Management
- System-wide cron jobs in `/etc/cron.d/`
- Interactive search and removal functionality

## File Structure

```
/root/
├── .my.cnf                    # MySQL root credentials
└── db-credentials/            # Database credentials (700 permissions)
    └── [database_name].txt    # Individual database credentials

/var/www/
└── [domain]/
    ├── html/                  # Document root (www-data:www-data)
    │   └── index.php         # Welcome page
    └── logs/                  # Apache logs
        ├── access.log
        └── error.log

/etc/apache2/sites-available/
├── [domain].conf             # HTTP virtual host
└── [domain]-le-ssl.conf      # HTTPS virtual host (Certbot)

/etc/cron.d/
└── [job_name]                # System cron jobs
```

## Security Features

- Root privilege enforcement
- Strict file permissions (700/644/755)
- Secure credential storage (600 permissions)
- Security headers configuration
- No sensitive data logging

## License

This project is provided as-is for server administration purposes.