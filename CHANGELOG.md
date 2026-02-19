# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [2.0.0] - 2026-02-18

### Added

- Modular architecture with composable building blocks pattern
- Input validation for all user inputs (domains, database names, paths, emails)
- Audit logging for all administrative actions
- Automatic backups before destructive operations
- Secure credential file storage with PDO DSN and Symfony DATABASE_URL
- Apache security headers (X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy)
- PHP version switching for virtual hosts with rollback on failure
- SSL certificate expiry monitoring
- Bulk SSL certificate recreation
- Configurable settings via `/etc/server-tools/config`
- BATS unit tests (126 tests)
- ShellCheck and shfmt integration
- GitHub Actions CI pipeline
- MIT License

### Changed

- Complete rewrite from single-file monolith to modular multi-file architecture
- All UI text translated to English
- Configuration variables use `ST_` prefix
- Improved error handling with rollback support
- Database menu now includes "create for existing user" and "assign to user" operations

### Removed

- German UI text
- Emoji in menu headers (replaced with clean ASCII)

## [1.0.0] - 2025-01-01

### Added

- Initial release with database, vhost, SSL, and cron management
- Interactive menu system
- Single-file architecture

[Unreleased]: https://github.com/markus-michalski/server-tools-v2/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/markus-michalski/osticket-prioritiy-icons/releases/tag/v2.0.0
