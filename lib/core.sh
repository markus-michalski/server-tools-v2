#!/bin/bash
# Core library: logging, error handling, dependency checks
# Sourced by all other libraries and the main entry point.

[[ -n "${_CORE_SOURCED:-}" ]] && return
_CORE_SOURCED=1

# Version
export ST_VERSION="2.0.0"

# Color support (respects NO_COLOR: https://no-color.org/)
if [[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    readonly _RED=$'\033[0;31m'
    readonly _YELLOW=$'\033[0;33m'
    readonly _GREEN=$'\033[0;32m'
    readonly _BLUE=$'\033[0;34m'
    readonly _BOLD=$'\033[1m'
    readonly _RESET=$'\033[0m'
else
    readonly _RED="" _YELLOW="" _GREEN="" _BLUE="" _BOLD="" _RESET=""
fi

# --- Logging ---

log_info() {
    echo "${_GREEN}[INFO]${_RESET} $*" >&2
}

log_warn() {
    echo "${_YELLOW}[WARN]${_RESET} $*" >&2
}

log_error() {
    echo "${_RED}[ERROR]${_RESET} $*" >&2
}

log_debug() {
    if [[ "${ST_DEBUG:-0}" == "1" ]]; then
        echo "${_BLUE}[DEBUG]${_RESET} $*" >&2
    fi
}

# Fatal error: log and exit
die() {
    log_error "$@"
    exit 1
}

# --- Dependency checks ---

# Check if a command is available
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Require a command or die with helpful message
require_command() {
    local cmd="$1"
    local install_hint="${2:-}"

    if ! command_exists "$cmd"; then
        if [[ -n "$install_hint" ]]; then
            die "'$cmd' is required but not installed. Install with: $install_hint"
        else
            die "'$cmd' is required but not installed."
        fi
    fi
}

# Check root privileges
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "This tool must be run as root."
    fi
}

# Verify all required system commands are available
check_dependencies() {
    local missing=()

    for cmd in mysql apache2ctl openssl; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required commands: ${missing[*]}"
    fi
}

# --- User interaction ---

# Ask for confirmation, returns 0 for yes, 1 for no
# Skips prompt when ST_AUTO_CONFIRM is set (for CLI --yes flag)
# Usage: confirm "Delete database?" || return 1
confirm() {
    local prompt="${1:-Continue?}"

    # Auto-confirm for non-interactive CLI usage
    if [[ "${ST_AUTO_CONFIRM:-}" == "true" ]]; then
        return 0
    fi

    local response
    read -r -p "${_BOLD}${prompt} (y/N):${_RESET} " response
    [[ "$response" =~ ^[yYjJ]$ ]]
}

# Print a section header
print_header() {
    echo ""
    echo "${_BOLD}=== $* ===${_RESET}"
    echo ""
}
