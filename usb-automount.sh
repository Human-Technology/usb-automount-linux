#!/bin/bash
# usb-automount.sh — mount and unmount removable filesystem partitions.

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Default configuration. Values in CONFIG_FILE override these defaults.
MOUNT_DIR="/media"
# Preserve the v1 mount path when the script is upgraded without installing a
# config file. Fresh installations get USE_LABEL=true from usb-automount.conf.
USE_LABEL=false
MIN_PARTITION_SIZE=104857600
EXCLUDED_DEVICES=""
LOG_FILE="/var/log/usb-automount.log"
NOTIFY="auto"
HOOKS_DIR="/etc/usb-automount/hooks.d"
RUNTIME_DIR="/run/usb-automount"

CONFIG_FILE="/etc/usb-automount/usb-automount.conf"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

log() {
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

notify() {
    local title="$1"
    local body="$2"
    local user

    case "$NOTIFY" in
        never)
            return
            ;;
        always)
            ;;
        auto)
            if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
                return
            fi
            ;;
        *)
            log "Invalid NOTIFY value '$NOTIFY'; notifications disabled"
            return
            ;;
    esac

    if ! command -v notify-send >/dev/null 2>&1; then
        return
    fi

    user=$(who | awk '/\(:/ { print $1; exit }')
    if [ -n "$user" ]; then
        su "$user" -c "DISPLAY=${DISPLAY:-:0} notify-send -- '$title' '$body'" \
            >/dev/null 2>&1 || true
    fi
}

resolve_mountpoint() {
    local dev="$1"
    local base_name="usb-${dev}"
    local device_label
    local target
    local index=1

    if [ "$USE_LABEL" = true ]; then
        device_label=$(blkid -o value -s LABEL "/dev/$dev" 2>/dev/null || true)
        if [ -n "$device_label" ]; then
            device_label=$(printf '%s' "$device_label" | sed 's/[^a-zA-Z0-9._-]/_/g')
            case "$device_label" in
                .|..)
                    ;;
                *)
                    base_name="$device_label"
                    ;;
            esac
        fi
    fi

    target="${MOUNT_DIR}/${base_name}"
    while mountpoint -q "$target" 2>/dev/null; do
        target="${MOUNT_DIR}/${base_name}_${index}"
        index=$((index + 1))
    done

    printf '%s\n' "$target"
}

save_state() {
    local temporary_state_file="${state_file}.tmp.$$"

    if ! mkdir -p "$RUNTIME_DIR"; then
        log "Could not create runtime directory $RUNTIME_DIR"
        return 1
    fi

    if ! {
        printf 'mountpoint=%q\n' "$mountpoint"
        printf 'fs_type=%q\n' "$fs_type"
        printf 'label=%q\n' "$label"
        printf 'uuid=%q\n' "$uuid"
    } > "$temporary_state_file"; then
        log "Could not write runtime state for /dev/$device"
        rm -f -- "$temporary_state_file"
        return 1
    fi

    if ! mv -f -- "$temporary_state_file" "$state_file"; then
        log "Could not save runtime state for /dev/$device"
        rm -f -- "$temporary_state_file"
        return 1
    fi
}

load_state() {
    [ -f "$state_file" ] || return 1

    # State files are written by this root-owned service using shell escaping.
    # shellcheck source=/dev/null
    source "$state_file"
}

mount_device() {
    if [ "$fs_type" = "ntfs" ] && command -v mount.ntfs-3g >/dev/null 2>&1; then
        mount -t ntfs-3g "/dev/$device" "$mountpoint"
    else
        mount -t "$fs_type" "/dev/$device" "$mountpoint"
    fi
}

run_hooks() {
    local hook_action="$1"
    local hook
    local line

    [ -d "$HOOKS_DIR" ] || return

    export USB_DEVICE="$device"
    export USB_MOUNTPOINT="$mountpoint"
    export USB_FSTYPE="${fs_type:-unknown}"
    export USB_LABEL="${label:-}"
    export USB_UUID="${uuid:-}"
    export USB_ACTION="$hook_action"

    for hook in "$HOOKS_DIR"/*; do
        if [ -f "$hook" ] && [ -x "$hook" ]; then
            log "Running hook: $(basename "$hook") ($hook_action)"
            while IFS= read -r line; do
                log "  hook[$(basename "$hook")]: $line"
            done < <("$hook" 2>&1)
        fi
    done
}

if [ "$#" -ne 2 ]; then
    log "Usage error: expected device and action (add or remove)"
    exit 1
fi

device="$1"
action="$2"

case "$action" in
    add|remove)
        ;;
    *)
        log "Usage error: unsupported action '$action'"
        exit 1
        ;;
esac

case "$device" in
    sd*)
        if [[ ! "$device" =~ ^sd[a-z]+[0-9]+$ ]]; then
            log "Unsupported device name: /dev/$device"
            exit 1
        fi
        base_device=${device%%[0-9]*}
        ;;
    mmcblk*)
        if [[ ! "$device" =~ ^mmcblk[0-9]+p[0-9]+$ ]]; then
            log "Unsupported device name: /dev/$device"
            exit 1
        fi
        base_device=${device%%p[0-9]*}
        ;;
    *)
        log "Unsupported device name: /dev/$device"
        exit 1
        ;;
esac

state_file="${RUNTIME_DIR}/${device}.state"

if [ -n "$EXCLUDED_DEVICES" ]; then
    IFS=',' read -r -a excluded_devices <<< "$EXCLUDED_DEVICES"
    for excluded_device in "${excluded_devices[@]}"; do
        excluded_device=$(printf '%s' "$excluded_device" | tr -d '[:space:]')
        if [ "$base_device" = "$excluded_device" ] || [ "$device" = "$excluded_device" ]; then
            log "Device /dev/$device is excluded by configuration, skipping"
            exit 0
        fi
    done
fi

if [ "$action" = "add" ]; then
    case "$MIN_PARTITION_SIZE" in
        ''|*[!0-9]*)
            log "Invalid MIN_PARTITION_SIZE value: $MIN_PARTITION_SIZE"
            exit 1
            ;;
    esac

    existing_mountpoint=$(findmnt -n -o TARGET --source "/dev/$device" 2>/dev/null || true)
    if [ -n "$existing_mountpoint" ]; then
        log "Skipping /dev/$device: already mounted at $existing_mountpoint"
        exit 0
    fi

    partition_size=$(blockdev --getsize64 "/dev/$device" 2>/dev/null) || {
        log "Could not get the size of /dev/$device"
        exit 1
    }

    case "$partition_size" in
        ''|*[!0-9]*)
            log "Invalid partition size for /dev/$device: $partition_size"
            exit 1
            ;;
    esac

    if [ "$partition_size" -lt "$MIN_PARTITION_SIZE" ]; then
        log "Skipping /dev/$device: partition is smaller than $MIN_PARTITION_SIZE bytes"
        exit 0
    fi

    fs_type=$(blkid -o value -s TYPE "/dev/$device" 2>/dev/null || true)
    if [ -z "$fs_type" ]; then
        log "Could not detect a filesystem on /dev/$device"
        exit 1
    fi

    mountpoint=$(resolve_mountpoint "$device")
    mountpoint_created=false
    if [ ! -d "$mountpoint" ]; then
        if ! mkdir -p "$mountpoint"; then
            log "Could not create mount point $mountpoint"
            exit 1
        fi
        mountpoint_created=true
    fi

    label=$(blkid -o value -s LABEL "/dev/$device" 2>/dev/null || true)
    uuid=$(blkid -o value -s UUID "/dev/$device" 2>/dev/null || true)
    if ! save_state; then
        if [ "$mountpoint_created" = true ]; then
            rmdir "$mountpoint" 2>/dev/null || true
        fi
        exit 1
    fi

    if mount_device; then
        log "Device /dev/$device ($fs_type) mounted at $mountpoint"
        notify "USB Mounted" "/dev/$device mounted at $mountpoint"
        run_hooks "post-mount"
        exit 0
    fi

    log "Could not mount /dev/$device ($fs_type) at $mountpoint"
    rm -f -- "$state_file"
    rmdir "$RUNTIME_DIR" 2>/dev/null || true
    if [ "$mountpoint_created" = true ]; then
        rmdir "$mountpoint" 2>/dev/null || true
    fi
    exit 1
fi

# On removal the device may no longer exist. Runtime state identifies only
# mounts created by this service and preserves metadata for post-unmount hooks.
if ! load_state; then
    mountpoint="${MOUNT_DIR}/usb-${device}"
    legacy_source=$(findmnt -n -o SOURCE --target "$mountpoint" 2>/dev/null || true)
    if [ "$legacy_source" != "/dev/$device" ]; then
        log "No managed mount found for /dev/$device; nothing to unmount"
        exit 0
    fi
    fs_type="unknown"
    label=""
    uuid=""
fi

log "Attempting to unmount /dev/$device from $mountpoint"

if mountpoint -q "$mountpoint" 2>/dev/null; then
    if ! umount "$mountpoint" 2>/dev/null; then
        log "Regular unmount failed for $mountpoint; attempting a lazy unmount"
        umount -l "$mountpoint" 2>/dev/null || true
    fi
fi

if mountpoint -q "$mountpoint" 2>/dev/null; then
    log "Mount point $mountpoint is still mounted"
    exit 1
fi

rmdir "$mountpoint" 2>/dev/null || true
rm -f -- "$state_file"
rmdir "$RUNTIME_DIR" 2>/dev/null || true
log "Device /dev/$device unmounted from $mountpoint"
notify "USB Removed" "$mountpoint unmounted"
run_hooks "post-unmount"
