#!/usr/bin/env bats
#
# install_tools/uninstall_tools (lib/install.sh) -- the installer that
# bin/server-tools' "install"/"uninstall" commands and the Makefile's
# install/uninstall targets both delegate to (#22). Runs against temp
# directories via ST_INSTALL_DIR/ST_BIN_DIR, so no root is required.

load ../test_helper

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR NO_COLOR=1
    export ST_CONFIG_FILE="${TEST_TMPDIR}/etc/config"
    export ST_CREDENTIAL_DIR="${TEST_TMPDIR}/credentials"
    export ST_AUDIT_LOG="${TEST_TMPDIR}/log/audit.log"
    export ST_BACKUP_DIR="${TEST_TMPDIR}/backups"
    export ST_INSTALL_DIR="${TEST_TMPDIR}/install/lib"
    export ST_BIN_DIR="${TEST_TMPDIR}/install/bin"
    export ST_AUDIT_LOGGING=true

    mkdir -p "${ST_BIN_DIR}"

    # install_tools/uninstall_tools read SCRIPT_DIR (source checkout root,
    # for bin/server-tools + conf/server-tools.conf.example + git describe)
    # and LIB_DIR (where the *source* libraries live) -- both normally set
    # by bin/server-tools before it sources lib/install.sh.
    SCRIPT_DIR="${PROJECT_ROOT}/bin"
    LIB_DIR="${PROJECT_ROOT}/lib"

    source_lib "install"
}

teardown() {
    [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

@test "install_tools installs the binary" {
    run install_tools
    assert_success
    assert_file_exists "${ST_BIN_DIR}/server-tools"
    assert_file_executable "${ST_BIN_DIR}/server-tools"
}

@test "install_tools creates both shortcuts" {
    run install_tools
    assert_success
    assert_symlink_to "${ST_BIN_DIR}/server-tools" "${ST_BIN_DIR}/st"
    assert_symlink_to "${ST_BIN_DIR}/server-tools" "${ST_BIN_DIR}/servertools"
}

@test "install_tools installs core libraries and the webserver subdirectory" {
    run install_tools
    assert_success
    assert_file_exists "${ST_INSTALL_DIR}/core.sh"
    assert_file_exists "${ST_INSTALL_DIR}/webserver/apache.sh"
    assert_file_exists "${ST_INSTALL_DIR}/webserver/nginx.sh"
}

@test "install_tools writes a .version marker so ST_VERSION doesn't fall back to dev" {
    run install_tools
    assert_success
    assert_file_exists "${ST_INSTALL_DIR}/.version"
    run cat "${ST_INSTALL_DIR}/.version"
    refute_output ""
}

@test "install_tools rewrites LIB_DIR in the installed copy to the install location" {
    run install_tools
    assert_success
    run grep -F "LIB_DIR=\"${ST_INSTALL_DIR}\"" "${ST_BIN_DIR}/server-tools"
    assert_success
}

@test "install_tools escapes sed metacharacters in ST_INSTALL_DIR for the LIB_DIR rewrite" {
    # A path containing '&' (sed's "whole match" token in a replacement) and
    # '|' (this rewrite's own delimiter) must survive into LIB_DIR literally.
    export ST_INSTALL_DIR="${TEST_TMPDIR}/install & lib | dir"

    run install_tools
    assert_success
    run grep -F "LIB_DIR=\"${ST_INSTALL_DIR}\"" "${ST_BIN_DIR}/server-tools"
    assert_success
}

@test "install_tools sets expected permission modes" {
    run install_tools
    assert_success
    assert_file_permission "700" "${ST_BIN_DIR}/server-tools"
    assert_file_permission "644" "${ST_INSTALL_DIR}/core.sh"
    assert_file_permission "600" "${ST_CONFIG_FILE}"
    assert_file_permission "700" "${ST_BACKUP_DIR}"
}

@test "install_tools creates config, credential, backup and audit directories" {
    run install_tools
    assert_success
    assert_file_exists "${ST_CONFIG_FILE}"
    assert_dir_exists "${ST_CREDENTIAL_DIR}"
    assert_dir_exists "${ST_BACKUP_DIR}"
    assert_dir_exists "$(dirname "${ST_AUDIT_LOG}")"
}

@test "install_tools is idempotent (running it twice does not fail)" {
    install_tools >/dev/null
    run install_tools
    assert_success
}

@test "uninstall_tools removes the binary and both shortcuts" {
    install_tools >/dev/null

    run uninstall_tools
    assert_success
    assert_file_not_exists "${ST_BIN_DIR}/server-tools"
    assert_file_not_exists "${ST_BIN_DIR}/st"
}

@test "uninstall_tools removes the servertools shortcut (regression guard, #24)" {
    install_tools >/dev/null

    # Prior to #24/#22, make uninstall only knew about server-tools/st and
    # left a dangling servertools symlink behind.
    run uninstall_tools
    assert_success
    assert_file_not_exists "${ST_BIN_DIR}/servertools"
}

@test "uninstall_tools removes the installed library directory" {
    install_tools >/dev/null

    run uninstall_tools
    assert_success
    assert_dir_not_exists "${ST_INSTALL_DIR}"
}

@test "uninstall_tools preserves config, credentials, backups and the audit log" {
    install_tools >/dev/null

    run uninstall_tools
    assert_success
    assert_file_exists "${ST_CONFIG_FILE}"
    assert_dir_exists "${ST_CREDENTIAL_DIR}"
    assert_dir_exists "${ST_BACKUP_DIR}"
}

@test "uninstall_tools does not fail when nothing was installed" {
    run uninstall_tools
    assert_success
}

@test "uninstall_tools doesn't claim to remove things that were never installed" {
    run uninstall_tools
    assert_success
    refute_output --partial "Removed: ${ST_BIN_DIR}/server-tools"
    refute_output --partial "Removed shortcut:"
}

@test "install_tools refuses to run from the installed copy (LIB_DIR == install target)" {
    LIB_DIR="$ST_INSTALL_DIR"

    run install_tools
    assert_failure
    assert_output --partial "source checkout"
}

@test "uninstall_tools refuses to delete ST_INSTALL_DIR if it doesn't look like a server-tools install" {
    mkdir -p "$ST_INSTALL_DIR"
    touch "${ST_INSTALL_DIR}/some-unrelated-file"

    run uninstall_tools
    assert_success
    assert_dir_exists "${ST_INSTALL_DIR}"
    assert_file_exists "${ST_INSTALL_DIR}/some-unrelated-file"
}

@test "uninstall_tools does not remove a shortcut path that isn't our symlink" {
    install_tools >/dev/null
    rm -f "${ST_BIN_DIR}/st"
    ln -sf /bin/true "${ST_BIN_DIR}/st"

    run uninstall_tools
    assert_success
    assert_link_exists "${ST_BIN_DIR}/st"
    run readlink "${ST_BIN_DIR}/st"
    assert_output "/bin/true"
}
