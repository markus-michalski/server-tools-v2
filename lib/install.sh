#!/bin/bash
# Install library: system-wide install/uninstall of server-tools itself.
# Depends on SCRIPT_DIR and LIB_DIR, both set by bin/server-tools before the
# library sourcing loop runs -- this is the one library that needs to know
# where the *source checkout* lives, not just where other libraries live.

[[ -n "${_INSTALL_SOURCED:-}" ]] && return
_INSTALL_SOURCED=1

source "${BASH_SOURCE%/*}/core.sh"
source "${BASH_SOURCE%/*}/config.sh"
source "${BASH_SOURCE%/*}/security.sh"

# Shortcut names created by install_tools and removed by uninstall_tools.
# Single source of truth so the two can never drift apart (#24).
readonly ST_INSTALL_SHORTCUTS=(st servertools)

# Marker check so uninstall_tools' "rm -rf $install_dir" only ever fires on
# a directory that actually looks like a server-tools install -- $install_dir
# is config-overridable (ST_INSTALL_DIR), including from /etc/server-tools/config,
# so this is the guard against a bad value (empty, "/", a typo) turning an
# uninstall into an arbitrary recursive delete.
_st_install_dir_looks_like_ours() {
    local dir="$1"
    [[ -n "$dir" && "$dir" == /* && "$dir" != "/" ]] || return 1
    [[ -f "${dir}/core.sh" && -f "${dir}/install.sh" ]]
}

install_tools() {
    local install_dir="$ST_INSTALL_DIR"
    local bin_dir="$ST_BIN_DIR"
    local config_dir
    config_dir=$(dirname "$ST_CONFIG_FILE")

    # Refuse to run from an already-installed copy: LIB_DIR (source libs)
    # and install_dir (install target) would be the same directory, so
    # cp/install below would fail partway through on "same file" errors
    # under set -e, after some config/credential dirs were already created.
    if [[ "$(realpath "$LIB_DIR")" == "$(realpath -m "$install_dir")" ]]; then
        die "install must be run from a source checkout (e.g. 'sudo ./bin/server-tools install' or 'sudo make install'), not from the installed copy"
    fi

    print_header "Server Tools Installation"

    # Create config directory
    if [[ ! -d "$config_dir" ]]; then
        mkdir -p "$config_dir"
        chmod 755 "$config_dir"
        echo "  Config directory created: $config_dir"
    fi

    # Create default config if missing
    if [[ ! -f "$ST_CONFIG_FILE" ]]; then
        local example_conf="${SCRIPT_DIR}/../conf/server-tools.conf.example"
        if [[ -f "$example_conf" ]]; then
            cp "$example_conf" "$ST_CONFIG_FILE"
        else
            cat >"$ST_CONFIG_FILE" <<'CONFIGEOF'
# Server Tools Configuration
# Uncomment and modify values as needed

# Paths
#ST_CREDENTIAL_DIR="/root/db-credentials"
#ST_AUDIT_LOG="/var/log/server-tools-audit.log"
#ST_BACKUP_DIR="/root/server-tools-backups"

# Defaults
#ST_DEFAULT_PHP_VERSION="8.3"
#ST_CERTBOT_EMAIL="admin@example.com"

# Passwords
#ST_PASSWORD_LENGTH=25
#ST_PASSWORD_MIN_LENGTH=12

# Features
#ST_AUTO_BACKUP=true
#ST_AUDIT_LOGGING=true
CONFIGEOF
        fi
        chmod 600 "$ST_CONFIG_FILE"
        echo "  Config created: $ST_CONFIG_FILE"
    fi

    # Create credential directory
    if [[ ! -d "$ST_CREDENTIAL_DIR" ]]; then
        local old_umask
        old_umask=$(umask)
        umask 077
        mkdir -p "$ST_CREDENTIAL_DIR"
        umask "$old_umask"
        echo "  Credential directory created: $ST_CREDENTIAL_DIR"
    fi

    # Create backup directory
    if [[ ! -d "$ST_BACKUP_DIR" ]]; then
        mkdir -p "$ST_BACKUP_DIR"
        chmod 700 "$ST_BACKUP_DIR"
        echo "  Backup directory created: $ST_BACKUP_DIR"
    fi

    # Create audit log directory
    local log_dir
    log_dir=$(dirname "$ST_AUDIT_LOG")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir"
        chmod 755 "$log_dir"
    fi

    # Install libraries
    mkdir -p "$install_dir"
    cp "${LIB_DIR}"/*.sh "$install_dir/"
    chmod 644 "$install_dir"/*.sh
    mkdir -p "$install_dir/webserver"
    cp "${LIB_DIR}"/webserver/*.sh "$install_dir/webserver/"
    chmod 644 "$install_dir"/webserver/*.sh
    echo "  Libraries installed: $install_dir"

    # Record the installed version as a marker file. Without it, core.sh's
    # version detection falls back to "dev" forever, since there is no git
    # repo at install_dir to describe -- the git tag only exists in the
    # source checkout we're installing from.
    #
    # -c safe.directory=... is needed because install runs as root (via
    # check_root) inside a checkout a normal user usually owns; without it,
    # git's "dubious ownership" guard makes describe fail and we'd silently
    # record "dev" -- the exact symptom this marker file exists to fix.
    local repo_dir version
    repo_dir=$(cd "${SCRIPT_DIR}/.." && pwd)
    if ! version=$(git -c safe.directory="$repo_dir" -C "$repo_dir" describe --tags --always 2>/dev/null) || [[ -z "$version" ]]; then
        version="dev"
        log_warn "Could not determine version via 'git describe' in $repo_dir; recording version as 'dev'"
    fi
    echo "$version" >"${install_dir}/.version"

    # Install main script. No explicit -o/-g: check_root already guarantees
    # we're running as root, so the file is owned by root:root regardless --
    # hardcoding it here only made the installer harder to test without root.
    install -m 700 "${SCRIPT_DIR}/server-tools" "${bin_dir}/server-tools"
    echo "  Binary installed: ${bin_dir}/server-tools"

    # Update LIB_DIR in installed script to point to installed location.
    # install_dir is config-overridable, so escape sed/replacement
    # metacharacters in it before splicing it into the expression.
    local install_dir_escaped
    install_dir_escaped=$(printf '%s' "$install_dir" | sed -e 's/[\&|]/\\&/g')
    sed -i "s|^[[:space:]]*LIB_DIR=.*|    LIB_DIR=\"${install_dir_escaped}\"|" "${bin_dir}/server-tools"

    # Create shortcuts
    for shortcut in "${ST_INSTALL_SHORTCUTS[@]}"; do
        ln -sf "${bin_dir}/server-tools" "${bin_dir}/${shortcut}"
        echo "  Shortcut created: $shortcut"
    done

    echo ""
    audit_log "INFO" "Server tools installed to $install_dir"
    log_info "Installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Edit config: $ST_CONFIG_FILE"
    echo "  2. Run: server-tools (or st)"
    echo "  3. Show config: server-tools --config"
}

# Remove everything install_tools created: the binary, its shortcuts, and
# the installed library copy. Config, credentials, backups and the audit
# log are intentionally left in place -- uninstall removes the tool, not
# the user's data.
uninstall_tools() {
    local install_dir="$ST_INSTALL_DIR"
    local bin_dir="$ST_BIN_DIR"
    local binary="${bin_dir}/server-tools"

    print_header "Server Tools Uninstall"

    if [[ -e "$binary" || -L "$binary" ]]; then
        rm -f "$binary"
        echo "  Removed: $binary"
    fi

    for shortcut in "${ST_INSTALL_SHORTCUTS[@]}"; do
        local shortcut_path="${bin_dir}/${shortcut}"
        # Only remove it if it's actually our symlink -- an unrelated
        # binary that happens to be named "st" shouldn't get deleted.
        if [[ -L "$shortcut_path" ]] && [[ "$(readlink "$shortcut_path")" == "$binary" ]]; then
            rm -f "$shortcut_path"
            echo "  Removed shortcut: $shortcut"
        fi
    done

    if [[ -d "$install_dir" ]]; then
        if _st_install_dir_looks_like_ours "$install_dir"; then
            rm -rf "$install_dir"
            echo "  Removed: $install_dir"
        else
            log_warn "ST_INSTALL_DIR ('$install_dir') doesn't look like a server-tools install (missing core.sh/install.sh) -- leaving it in place"
        fi
    fi

    echo ""
    audit_log "INFO" "Server tools uninstalled from $install_dir"
    log_info "Uninstall complete!"
    echo ""
    echo "Note: config ($ST_CONFIG_FILE), credentials, backups and the audit"
    echo "log were left in place. Remove them manually if no longer needed."
}
