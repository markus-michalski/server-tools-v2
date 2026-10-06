# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `server-tools uninstall` command, and a CI job that exercises both
  `make install`/`make uninstall` and `./bin/server-tools install`/`uninstall`
  against real system paths on every push (#23)

### Changed
- `make install`/`make uninstall` now delegate to `bin/server-tools
  install`/`uninstall` instead of duplicating the installer logic -- the two
  had drifted apart (binary mode/owner, missing shortcut, missing `.version`
  marker, missing config/credential/backup/audit directory setup), which is
  how the `lib/webserver/*.sh` installer gap below went unnoticed (#22)

### Deprecated
- Nothing yet

### Removed
- Nothing yet

### Fixed
- `make install` now also installs `lib/webserver/*.sh`; previously only
  `lib/*.sh` was copied, so installs done via `make install` (not the
  documented `./bin/server-tools install`, which already handled this)
  failed at startup when `lib/vhost.sh` sourced `webserver/apache.sh`
  (since Nginx support landed in 2.5.0, #11/#19)
- Uninstalling no longer leaves a dangling `servertools` symlink behind --
  it was created by `install_tools` but only `server-tools`/`st` were ever
  removed (#24)
- An installed copy of server-tools now writes a `.version` marker, so
  `server-tools --version` reports the real installed version instead of
  permanently falling back to `dev` (there is no git repo at the install
  location to describe); version detection also no longer silently reports
  `dev` when git's "dubious ownership" check trips under root
- `uninstall` now only ever removes paths that actually look like a
  server-tools install (and only removes the `st`/`servertools` shortcuts if
  they're still our symlinks), refusing instead of recursively deleting an
  unexpected `ST_INSTALL_DIR` value; `install` now fails fast with a clear
  error if run from an already-installed copy instead of dying partway
  through on a "same file" error

### Security
- Nothing yet

## [2.5.0] - 2026-09-11

### Added
- add 'vhost audit' to surface template drift (#13) (#17)
- add Nginx support for vhost management (#11) (#19)

### Fixed
- stop truncating www/HTTPS redirect snippets to a comment (#18) (#20)

## [2.4.1] - 2026-09-10

### Added
- emit X-Forwarded-Proto/Port headers in generated vhosts (#15)

### Changed
- add /.claude/worktrees* to .gitignore

## [2.4.0] - 2026-06-06

### Added
- make MySQL/MariaDB optional, support both naming conventions

### Changed
- add .git-workflow to .gitignore

### Fixed
- fix shfmt formatting in mysql_available()
- restore http:// for localhost ProxyPass in SSL vhost after certbot (#10)

## [2.3.1] - 2026-04-01


## [2.3.0] - 2026-03-13

### Added
- add reverse proxy mode for vhost creation

### Fixed
- allow port numbers in URL validation

## [2.2.0] - 2026-02-19

### Added
- add per-domain SSH user management with ACL-based isolation

### Changed
- trigger CI re-run

### Fixed
- export global flags to silence ShellCheck SC2034

## [2.1.2] - 2026-02-19

### Changed
- clean up changelog by removing empty sections and updating unreleased version

### Fixed
- allow hyphens in database names and usernames
- prevent sed from mangling its own line during install

## [2.1.1] - 2026-02-19

### Changed
- add update instructions to README

### Fixed
- use tag -l instead of describe for checkout command

## [2.1.0] - 2026-02-19

### Changed
- recommend checking out latest release tag instead of main
- update README with missing modules and documentation links
- remove trailing blank lines in cli.sh

### Fixed
- consume stdin in mysql mock to prevent SIGPIPE with pipefail

### Security
- fix audit findings from comprehensive code review
- harden credential handling, config sourcing, and input validation

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

[Unreleased]: https://github.com/markus-michalski/server-tools-v2/compare/v2.5.0...HEAD
[2.0.0]: https://github.com/markus-michalski/server-tools-v2/releases/tag/v2.0.0
[2.1.0]: https://github.com/markus-michalski/server-tools-v2/releases/tag/v2.1.0
[2.1.1]: https://github.com/markus-michalski/server-tools-v2/releases/tag/v2.1.1
[2.1.2]: https://github.com/markus-michalski/server-tools-v2/releases/tag/v2.1.2
[2.2.0]: https://github.com/markus-michalski/server-tools-v2/releases/tag/v2.2.0
[2.3.0]: https://github.com/markus-michalski/server-tools-v2/releases/tag/v2.3.0
[2.3.1]: https://github.com/markus-michalski/server-tools-v2/releases/tag/v2.3.1
[2.4.0]: https://github.com/markus-michalski/server-tools-v2/releases/tag/v2.4.0
[2.4.1]: https://github.com/markus-michalski/server-tools-v2/releases/tag/v2.4.1
[2.5.0]: https://github.com/markus-michalski/server-tools-v2/releases/tag/v2.5.0
