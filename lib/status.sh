#!/bin/bash
# Status library: service status checks and system resource monitoring
#
# Architecture: building blocks + high-level operations
# - Building blocks: individual checks (service, disk, memory, load)
# - High-level ops: combined status displays

[[ -n "${_STATUS_SOURCED:-}" ]] && return
_STATUS_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"
source "${BASH_SOURCE%/*}/config.sh"

# =============================================================================
# BUILDING BLOCKS - atomic status checks
# =============================================================================

# Check if a single service is running
# Returns: "running", "stopped", "not installed"
check_service() {
    local service="$1"

    if ! command_exists systemctl; then
        echo "unknown (no systemd)"
        return 1
    fi

    if ! systemctl list-unit-files "${service}.service" &>/dev/null; then
        echo "not installed"
        return 1
    fi

    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "running"
        return 0
    else
        echo "stopped"
        return 1
    fi
}

# Get disk usage summary
get_disk_usage() {
    df -h --output=target,size,used,avail,pcent -x tmpfs -x devtmpfs 2>/dev/null \
        || df -h 2>/dev/null \
        || echo "  (unable to determine disk usage)"
}

# Get memory usage
get_memory_usage() {
    free -h 2>/dev/null || echo "  (unable to determine memory usage)"
}

# Get system load average
get_load_average() {
    uptime 2>/dev/null || echo "  (unable to determine load)"
}

# Get OS information
get_os_info() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "${PRETTY_NAME:-${NAME:-Unknown} ${VERSION_ID:-}}"
    else
        uname -sr 2>/dev/null || echo "Unknown"
    fi
}

# =============================================================================
# HIGH-LEVEL OPERATIONS - compose building blocks
# =============================================================================

# Show status of all monitored services
show_service_status() {
    print_header "Service Status"

    # Core services
    local services="apache2 mysql"
    for service in $services; do
        local status
        status=$(check_service "$service")
        local color=""
        local reset=""
        if [[ "${NO_COLOR:-}" != "1" ]]; then
            if [[ "$status" == "running" ]]; then
                color="${GREEN:-}"
            elif [[ "$status" == "stopped" ]]; then
                color="${RED:-}"
            else
                color="${YELLOW:-}"
            fi
            reset="${RESET:-}"
        fi
        printf "  %-20s %s%s%s\n" "$service" "$color" "$status" "$reset"
    done

    # PHP-FPM services
    for version in $ST_PHP_VERSIONS_TO_SCAN; do
        local fpm_service="php${version}-fpm"
        if systemctl list-unit-files "${fpm_service}.service" &>/dev/null 2>&1; then
            local status
            status=$(check_service "$fpm_service")
            local color=""
            local reset=""
            if [[ "${NO_COLOR:-}" != "1" ]]; then
                if [[ "$status" == "running" ]]; then
                    color="${GREEN:-}"
                elif [[ "$status" == "stopped" ]]; then
                    color="${RED:-}"
                fi
                reset="${RESET:-}"
            fi
            printf "  %-20s %s%s%s\n" "$fpm_service" "$color" "$status" "$reset"
        fi
    done
}

# Show system resource usage
show_system_resources() {
    print_header "System Resources"

    echo "OS: $(get_os_info)"
    echo "Hostname: $(hostname 2>/dev/null || echo 'unknown')"
    echo ""

    echo "Load:"
    echo "  $(get_load_average)"
    echo ""

    echo "Memory:"
    get_memory_usage | sed 's/^/  /'
    echo ""

    echo "Disk:"
    get_disk_usage | sed 's/^/  /'
}

# Show combined full status (replaces old system_info)
show_full_status() {
    clear
    show_service_status
    echo ""
    show_system_resources
    echo ""

    echo "Software Versions:"
    echo "  Apache:  $(apache2 -v 2>/dev/null | head -1 | cut -d' ' -f3 || echo 'not installed')"
    echo "  MySQL:   $(mysql --version 2>/dev/null | cut -d' ' -f6 | cut -d',' -f1 || echo 'not installed')"

    # PHP versions
    local available_php
    available_php=$(detect_php_versions 2>/dev/null || echo "")
    if [[ -n "$available_php" ]]; then
        for version in $available_php; do
            echo "  PHP $version: $("php${version}" -v 2>/dev/null | head -1 || echo 'version info unavailable')"
        done
    fi
    echo ""

    echo "Configuration:"
    show_config
    echo ""

    echo "Backups:"
    list_backups
}
