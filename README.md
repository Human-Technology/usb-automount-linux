# 🔌 usb-automount

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![ShellCheck](https://github.com/Human-Technology/usb-automount-linux/actions/workflows/lint.yml/badge.svg)](https://github.com/Human-Technology/usb-automount-linux/actions)
[![Version: 2.0](https://img.shields.io/badge/version-2.0-blue.svg)](https://github.com/Human-Technology/usb-automount-linux/releases)

**Automatic removable-drive mounting for headless Linux servers and Raspberry Pi.**

Plug in a USB drive or SD-card partition and it is mounted automatically. Remove
it and its mount point is cleaned up. The project uses udev and systemd, with no
daemon to keep running.

> 🇪🇸 [Leer en Español](README.es.md)

For installation, configuration, hooks, backups, and troubleshooting, see the
[full manual](docs/MANUAL.en.md).

## Features

- Automatic mount and unmount through udev and systemd.
- Label-based mount points such as `/media/BACKUP`, with legacy device-name
  paths available through configuration.
- Configurable mount directory, minimum partition size, exclusions, logging,
  notifications, and hooks.
- Executable post-mount and post-unmount hooks for backup and sync workflows.
- Log rotation, a man page, and a ShellCheck CI workflow.
- USB disks and SD-card partitions (`mmcblk…p…`) are supported; NVMe is not.

## Quick start

One-line install from the `main` branch:

```bash
curl -fsSL https://raw.githubusercontent.com/Human-Technology/usb-automount-linux/main/install.sh | sudo bash
```

Or clone the repository so you can inspect it first:

```bash
git clone https://github.com/Human-Technology/usb-automount-linux.git
cd usb-automount-linux
sudo ./install.sh
```

Plug in a supported filesystem partition and follow the events with:

```bash
tail -f /var/log/usb-automount.log
```

## Configuration

The installer creates `/etc/usb-automount/usb-automount.conf`. Edit it to
change behaviour; existing configuration is never overwritten by a reinstall.

| Option | Default | Description |
| --- | --- | --- |
| `MOUNT_DIR` | `/media` | Base directory for mount points. |
| `USE_LABEL` | `true` | Use filesystem labels as mount point names. |
| `MIN_PARTITION_SIZE` | `104857600` | Minimum size in bytes (100 MiB). |
| `EXCLUDED_DEVICES` | `""` | Comma-separated devices to skip, such as `sda,sdb`. |
| `LOG_FILE` | `/var/log/usb-automount.log` | Event log path. |
| `NOTIFY` | `auto` | Desktop notification mode: `auto`, `always`, or `never`. |
| `HOOKS_DIR` | `/etc/usb-automount/hooks.d` | Directory containing executable hooks. |

When `USE_LABEL=true`, a drive labeled `BACKUP` mounts at `/media/BACKUP`.
Labels are sanitized for safe directory names. Duplicate mounted labels receive
a numeric suffix. Set `USE_LABEL=false` to retain the legacy path format, for
example `/media/usb-sdb1`. When upgrading a v1 installation that has no config,
the installer automatically preserves the legacy path format.

## Hooks

Put executable scripts in `/etc/usb-automount/hooks.d/`. They run after a
successful mount or unmount and receive these environment variables:

| Variable | Example | Description |
| --- | --- | --- |
| `USB_DEVICE` | `sdb1` | Device name. |
| `USB_MOUNTPOINT` | `/media/BACKUP` | Mount point. |
| `USB_FSTYPE` | `ext4` | Filesystem type. |
| `USB_LABEL` | `BACKUP` | Filesystem label, when available. |
| `USB_UUID` | `1234-ABCD` | Filesystem UUID, when available. |
| `USB_ACTION` | `post-mount` | `post-mount` or `post-unmount`. |

Example backup hook:

```bash
#!/bin/bash
# /etc/usb-automount/hooks.d/01-backup.sh

if [ "$USB_ACTION" = "post-mount" ] && [ "$USB_UUID" = "YOUR-UUID-HERE" ]; then
    rsync -av --delete /home/user/documents/ "$USB_MOUNTPOINT/backup/"
fi
```

Make the hook executable with `sudo chmod +x /etc/usb-automount/hooks.d/01-backup.sh`.
An inactive example is installed as `00-example-hook.sh.sample`.

## Raspberry Pi

usb-automount is suitable for Raspberry Pi OS Lite, NAS appliances, media
servers, and unattended backup stations. SD-card partitions are matched as
well, so exclude the system card in the configuration if it is eligible for
mounting. For bus-powered hard drives, use a powered USB hub.

Filesystem support is supplied by the host kernel and its installed mount
helpers. Install the appropriate system package if your distribution requires
one for exFAT or NTFS.

## Comparison

| Capability | usb-automount | usbmount | udiskie |
| --- | :---: | :---: | :---: |
| Designed for headless systems | ✅ | ✅ | ⚠️ |
| Label-based mount paths | ✅ | ❌ | ✅ |
| No persistent daemon | ✅ | ✅ | ❌ |
| Native udev → systemd lifecycle | ✅ | ❌ | ❌ |
| Post-mount and post-unmount hooks | ✅ | ✅ | ✅ |
| Optional desktop notifications | ✅ | ❌ | ✅ |
| Raspberry Pi and SD-card support | ✅ | ⚠️ | ⚠️ |

[usbmount](https://github.com/rbrito/usbmount) is a legacy udev-oriented
solution. [udiskie](https://github.com/coldfix/udiskie) is a feature-rich
udisks2 front end aimed primarily at user sessions. usb-automount focuses on a
small, root-managed systemd pipeline for unattended systems.

## Manual installation

```bash
sudo install -Dm755 usb-automount.sh /usr/local/bin/usb-automount.sh
sudo install -Dm644 usb-automount@.service /etc/systemd/system/usb-automount@.service
sudo install -Dm644 99-usb-automount.rules /etc/udev/rules.d/99-usb-automount.rules
sudo install -Dm644 usb-automount.conf /etc/usb-automount/usb-automount.conf
sudo install -d /etc/usb-automount/hooks.d
sudo install -Dm644 hooks.d/00-example-hook.sh.sample /etc/usb-automount/hooks.d/00-example-hook.sh.sample
sudo install -Dm644 usb-automount.logrotate /etc/logrotate.d/usb-automount
sudo install -Dm644 usb-automount.8 /usr/local/share/man/man8/usb-automount.8
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=block --action=add
```

## Troubleshooting

- **A device does not mount:** inspect `tail -f /var/log/usb-automount.log` and
  verify the partition contains a recognized filesystem.
- **The mount path changed:** set `USE_LABEL=false` for legacy device-name paths.
- **A partition must never be mounted:** add its device or parent disk to
  `EXCLUDED_DEVICES`, for example `EXCLUDED_DEVICES="mmcblk0,sda"`.
- **Hooks do not run:** ensure the hook is a regular executable file.
- **Changes do not take effect:** run `sudo udevadm control --reload-rules` and
  `sudo systemctl daemon-reload`.

View the installed manual with `man usb-automount`.

## Uninstall

```bash
sudo ./install.sh remove
```

Installed binaries and integration files are removed. Configuration and hooks
remain in `/etc/usb-automount/` for safety.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT License — see [LICENSE](LICENSE).
