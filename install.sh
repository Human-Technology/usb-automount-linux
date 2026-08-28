#!/bin/bash
# install.sh — installer and uninstaller for usb-automount.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMP_SOURCE_DIR=""
readonly INSTALL_SCRIPT="/usr/local/bin/usb-automount.sh"
readonly INSTALL_SERVICE="/etc/systemd/system/usb-automount@.service"
readonly INSTALL_RULES="/etc/udev/rules.d/99-usb-automount.rules"
readonly INSTALL_CONFIG_DIR="/etc/usb-automount"
readonly INSTALL_CONFIG="${INSTALL_CONFIG_DIR}/usb-automount.conf"
readonly INSTALL_HOOKS_DIR="${INSTALL_CONFIG_DIR}/hooks.d"
readonly INSTALL_LOGROTATE="/etc/logrotate.d/usb-automount"
readonly INSTALL_MANPAGE="/usr/local/share/man/man8/usb-automount.8"

if [ -t 1 ]; then
    readonly GREEN=$'\033[0;32m'
    readonly YELLOW=$'\033[1;33m'
    readonly RESET=$'\033[0m'
else
    readonly GREEN=""
    readonly YELLOW=""
    readonly RESET=""
fi

cleanup_download() {
    if [ -n "$TEMP_SOURCE_DIR" ] && [ -d "$TEMP_SOURCE_DIR" ]; then
        rm -rf -- "$TEMP_SOURCE_DIR"
    fi
}

download_sources() {
    local archive

    if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
        printf '%s\n' 'Error: curl and tar are required for installation from stdin.' >&2
        exit 1
    fi

    TEMP_SOURCE_DIR=$(mktemp -d -t usb-automount.XXXXXX)
    archive="${TEMP_SOURCE_DIR}/source.tar.gz"
    trap cleanup_download EXIT

    printf '%sDownloading release files...%s\n' "$YELLOW" "$RESET"
    curl -fsSL \
        'https://github.com/Human-Technology/usb-automount-linux/archive/refs/heads/main.tar.gz' \
        -o "$archive"
    tar -xzf "$archive" -C "$TEMP_SOURCE_DIR" --strip-components=1
    rm -f -- "$archive"
    SCRIPT_DIR="$TEMP_SOURCE_DIR"
}

print_header() {
    printf '%s%s%s\n' "$GREEN" 'usb-automount for Linux' "$RESET"
    printf '%s\n' '========================='
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        printf '%s\n' 'Error: run this script as root (for example, sudo ./install.sh).' >&2
        exit 1
    fi
}

reload_services() {
    systemctl daemon-reload
    udevadm control --reload-rules
}

install_files() {
    local preserve_legacy_paths=false

    print_header
    printf '%s\n' 'Installing usb-automount...'

    if [ -f "${INSTALL_SCRIPT}" ] && [ ! -f "${INSTALL_CONFIG}" ]; then
        preserve_legacy_paths=true
    fi

    install -Dm755 "${SCRIPT_DIR}/usb-automount.sh" "${INSTALL_SCRIPT}"
    install -Dm644 "${SCRIPT_DIR}/usb-automount@.service" "${INSTALL_SERVICE}"
    install -Dm644 "${SCRIPT_DIR}/99-usb-automount.rules" "${INSTALL_RULES}"

    mkdir -p "${INSTALL_CONFIG_DIR}" "${INSTALL_HOOKS_DIR}"
    if [ -f "${INSTALL_CONFIG}" ]; then
        install -Dm644 "${SCRIPT_DIR}/usb-automount.conf" "${INSTALL_CONFIG}.new"
        printf 'Existing configuration preserved; new defaults: %s.new\n' "${INSTALL_CONFIG}"
    else
        install -Dm644 "${SCRIPT_DIR}/usb-automount.conf" "${INSTALL_CONFIG}"
        if [ "$preserve_legacy_paths" = true ]; then
            sed -i 's/^USE_LABEL=true$/USE_LABEL=false/' "${INSTALL_CONFIG}"
            printf '%s\n' 'Legacy /media/usb-* mount paths preserved for this upgrade.'
        fi
    fi

    if [ -f "${SCRIPT_DIR}/hooks.d/00-example-hook.sh.sample" ]; then
        if [ ! -e "${INSTALL_HOOKS_DIR}/00-example-hook.sh.sample" ]; then
            install -Dm644 "${SCRIPT_DIR}/hooks.d/00-example-hook.sh.sample" \
                "${INSTALL_HOOKS_DIR}/00-example-hook.sh.sample"
        fi
    fi

    if [ -d /etc/logrotate.d ]; then
        install -Dm644 "${SCRIPT_DIR}/usb-automount.logrotate" "${INSTALL_LOGROTATE}"
    fi

    install -Dm644 "${SCRIPT_DIR}/usb-automount.8" "${INSTALL_MANPAGE}"
    if command -v mandb >/dev/null 2>&1; then
        mandb -q || true
    fi

    reload_services
    udevadm trigger --subsystem-match=block --action=add
    udevadm settle
    printf '%sInstallation complete.%s\n' "$GREEN" "$RESET"
    printf 'Configuration: %s\nHooks: %s\nLogs: /var/log/usb-automount.log\n' \
        "${INSTALL_CONFIG}" "${INSTALL_HOOKS_DIR}"
}

uninstall_files() {
    print_header
    printf '%s\n' 'Removing usb-automount...'

    systemctl list-units --type=service --all --no-legend 'usb-automount@*' 2>/dev/null |
        awk '{print $1}' |
        while IFS= read -r service; do
            if [ -n "$service" ]; then
                systemctl stop "$service" 2>/dev/null || true
            fi
        done || true

    rm -f "${INSTALL_SCRIPT}" "${INSTALL_SERVICE}" "${INSTALL_RULES}" \
        "${INSTALL_LOGROTATE}" "${INSTALL_MANPAGE}"

    reload_services
    printf '%sUninstallation complete.%s\n' "$GREEN" "$RESET"
    printf 'Configuration and hooks were preserved in %s.\n' "${INSTALL_CONFIG_DIR}"
}

check_root

if [ "${1:-install}" = "install" ] && [ ! -f "${SCRIPT_DIR}/usb-automount.sh" ]; then
    download_sources
fi

case "${1:-install}" in
    install)
        install_files
        ;;
    remove|uninstall)
        uninstall_files
        ;;
    *)
        printf 'Usage: %s [install|remove]\n' "$0" >&2
        exit 1
        ;;
esac
