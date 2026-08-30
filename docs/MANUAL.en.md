# User Manual — usb-automount

This guide covers installing, configuring, and using **usb-automount**.

`usb-automount` automatically detects and mounts USB drives and SD-card
partitions on Linux using **udev + systemd**, without keeping a daemon running.
It is intended for headless servers, Raspberry Pi, homelabs, NAS appliances,
media servers, and removable-media automations.

## Contents

1. [How it works](#how-it-works)
2. [Requirements and installation](#requirements-and-installation)
3. [First test](#first-test)
4. [Configuration](#configuration)
5. [Labels and exclusions](#labels-and-exclusions)
6. [Hooks](#hooks)
7. [Automatic backup](#automatic-backup)
8. [Logs and notifications](#logs-and-notifications)
9. [Raspberry Pi, updating, and uninstalling](#raspberry-pi-updating-and-uninstalling)
10. [Troubleshooting and limitations](#troubleshooting-and-limitations)
11. [Quick commands](#quick-commands)

## How it works

When a compatible partition is connected, udev detects it and asks systemd to
start `usb-automount@<device>.service`. The service identifies the filesystem,
creates a mount point, mounts the partition, and runs `post-mount` hooks. When
the device disappears, the unit's `BindsTo=` relationship makes systemd stop
the service: it unmounts the device, cleans up the mount point, and runs
`post-unmount` hooks.

```text
USB / SD → udev → systemd → identify filesystem → mount → hooks
```

For example, a drive labeled `BACKUP` normally mounts at `/media/BACKUP`.

## Requirements and installation

You need a Linux distribution using systemd, udev, Bash, and the `mount`,
`umount`, `mountpoint`, `blkid`, `findmnt`, and `blockdev` utilities (normally
provided by `util-linux`). On Debian, Ubuntu, or Raspberry Pi OS:

```bash
sudo apt update
sudo apt install curl git util-linux
```

Additional filesystem or backup support may require:

```bash
sudo apt install ntfs-3g       # NTFS
sudo apt install exfatprogs    # exFAT
sudo apt install rsync         # backups
sudo apt install libnotify-bin # desktop notifications
```

Quick installation from the `main` branch:

```bash
curl -fsSL https://raw.githubusercontent.com/Human-Technology/usb-automount-linux/main/install.sh | sudo bash
```

Or clone the repository and run the installer:

```bash
git clone https://github.com/Human-Technology/usb-automount-linux.git
cd usb-automount-linux
sudo ./install.sh
```

The principal installed files are:

```text
/usr/local/bin/usb-automount.sh
/etc/systemd/system/usb-automount@.service
/etc/udev/rules.d/99-usb-automount.rules
/etc/usb-automount/usb-automount.conf
/etc/usb-automount/hooks.d/
/etc/logrotate.d/usb-automount
/usr/local/share/man/man8/usb-automount.8
```

## First test

Watch the log, then connect a drive:

```bash
sudo tail -f /var/log/usb-automount.log
```

Confirm that Linux detected a filesystem partition and mounted it:

```bash
lsblk -f
ls /media
findmnt /media/BACKUP
```

A typical `lsblk -f` result:

```text
NAME   FSTYPE LABEL   UUID
sdb
└─sdb1 ext4   BACKUP  6a2fedac-a59d-4bba-9d90-123456789abc
```

## Configuration

Edit `/etc/usb-automount/usb-automount.conf`:

```bash
sudo nano /etc/usb-automount/usb-automount.conf
```

```bash
MOUNT_DIR="/media"
USE_LABEL=true
MIN_PARTITION_SIZE=104857600
EXCLUDED_DEVICES=""
LOG_FILE="/var/log/usb-automount.log"
NOTIFY="auto"
HOOKS_DIR="/etc/usb-automount/hooks.d"
```

| Option | Purpose |
| --- | --- |
| `MOUNT_DIR` | Mount-point base directory, e.g. `/mnt/removable`. |
| `USE_LABEL` | With `true`, use the filesystem label; with `false`, use `/media/usb-sdb1`. |
| `MIN_PARTITION_SIZE` | Minimum bytes; `104857600` is 100 MiB. Use `0` to disable this size filter. |
| `EXCLUDED_DEVICES` | Comma-separated device names to skip, e.g. `sda,sdb2,mmcblk0`. |
| `LOG_FILE` | Event-log location. |
| `NOTIFY` | `auto`, `always`, or `never`. |
| `HOOKS_DIR` | Directory of executable scripts run after mounting and unmounting. |

Reinstalling preserves an existing configuration file and writes new defaults as
`usb-automount.conf.new`. When upgrading an older installation without a config
file, the installer preserves legacy paths by using `USE_LABEL=false`.

## Labels and exclusions

With `USE_LABEL=true`, labels such as `BACKUP`, `MEDIA`, and `PHOTOS` become
`/media/BACKUP`, `/media/MEDIA`, and `/media/PHOTOS`. Inspect a label with:

```bash
lsblk -f
sudo blkid /dev/sdb1
```

To assign an ext4 label, unmount the partition first:

```bash
sudo umount /dev/sdb1
sudo e2label /dev/sdb1 BACKUP
```

Unsafe characters are replaced by underscores, so `MY BACKUP` becomes
`MY_BACKUP`. If a mount point for the same label already exists, a numeric suffix
is used, such as `BACKUP_1`.

Exclude disks or partitions, for example:

```bash
EXCLUDED_DEVICES="sda,sdb2,mmcblk0"
```

Excluding a disk (`sda` or `mmcblk0`) also excludes its partitions.

## Hooks

Regular, executable files in `HOOKS_DIR` run after every successful mount and
unmount. They receive these environment variables:

| Variable | Example |
| --- | --- |
| `USB_DEVICE` | `sdb1` |
| `USB_MOUNTPOINT` | `/media/BACKUP` |
| `USB_FSTYPE` | `ext4` |
| `USB_LABEL` | `BACKUP` |
| `USB_UUID` | `6a2fedac-...` |
| `USB_ACTION` | `post-mount` or `post-unmount` |

Create a test hook:

```bash
sudo nano /etc/usb-automount/hooks.d/01-test.sh
```

```bash
#!/bin/bash
if [ "$USB_ACTION" = "post-mount" ]; then
    echo "Drive connected: $USB_DEVICE at $USB_MOUNTPOINT"
    echo "Label: $USB_LABEL; UUID: $USB_UUID; FS: $USB_FSTYPE"
fi
```

```bash
sudo chmod +x /etc/usb-automount/hooks.d/01-test.sh
```

For a removal hook, check `USB_ACTION = post-unmount`. Disable a hook without
deleting it using `sudo chmod -x`. Hooks run with elevated privileges, and a
slow hook keeps the service cycle busy; install only trusted scripts.

## Automatic backup

Identify a backup target by UUID rather than label alone. Obtain it with
`sudo blkid -s UUID -o value /dev/sdb1`, then create this hook:

```bash
sudo nano /etc/usb-automount/hooks.d/01-backup.sh
```

```bash
#!/bin/bash
BACKUP_UUID="6a2fedac-a59d-4bba-9d90-123456789abc"

if [ "$USB_ACTION" != "post-mount" ] || [ "$USB_UUID" != "$BACKUP_UUID" ]; then
    exit 0
fi

echo "=== Starting backup ==="
mkdir -p "$USB_MOUNTPOINT/server-backup"
rsync -av /srv/documents/ "$USB_MOUNTPOINT/server-backup/"
sync
echo "=== Backup completed ==="
```

```bash
sudo chmod +x /etc/usb-automount/hooks.d/01-backup.sh
```

After carefully validating source and destination, you can create a mirror with
`rsync -av --delete`. `--delete` removes destination files no longer present in
the source, so test without it first.

## Logs and notifications

The main log is `/var/log/usb-automount.log` and is managed by logrotate:

```bash
sudo tail -f /var/log/usb-automount.log
sudo tail -100 /var/log/usb-automount.log
sudo journalctl -u usb-automount@sdb1.service
sudo journalctl -b -u usb-automount@sdb1.service
```

`NOTIFY="auto"` attempts a notification when a suitable graphical session is
available; `NOTIFY="always"` requires `notify-send`; use `NOTIFY="never"` on
headless servers.

## Raspberry Pi, updating, and uninstalling

SD partitions such as `mmcblk0p1` and `mmcblk1p1` are supported. To ignore a
system SD card, use `EXCLUDED_DEVICES="mmcblk0"`. Some mechanical USB disks need
more power than a Raspberry Pi supplies directly; use a powered hub if needed.

To update a cloned copy:

```bash
cd usb-automount-linux
git pull
sudo ./install.sh
sudo diff /etc/usb-automount/usb-automount.conf /etc/usb-automount/usb-automount.conf.new
```

To remove the installed binaries and integration while preserving configuration
and hooks for safety:

```bash
sudo ./install.sh remove
```

`sudo ./install.sh uninstall` is also accepted. To permanently remove your
configuration and hooks afterwards, use `sudo rm -rf /etc/usb-automount`.

## Troubleshooting and limitations

When a drive does not mount, first confirm that the system detects it, then
inspect the log and relevant systemd unit:

```bash
lsblk -f
sudo tail -100 /var/log/usb-automount.log
sudo systemctl status usb-automount@sdb1.service
sudo udevadm monitor --udev --property
```

After changing rules or services, reload them and retrigger events:

```bash
sudo udevadm control --reload-rules
sudo systemctl daemon-reload
sudo udevadm trigger --subsystem-match=block --action=add
```

Inspect a filesystem with `sudo blkid /dev/sdb1`. Verify that a hook is
executable (`ls -la /etc/usb-automount/hooks.d/`) and has an interpreter such
as `#!/bin/bash`. A temporary hook that prints each `USB_*` variable to stdout
is useful for debugging; hook output is written to the main log.

Current limitations:

- USB partitions `sd…N` and SD partitions `mmcblk…pN` are supported; NVMe is not.
- Partitions with no recognized filesystem, or below 100 MiB by default, are not mounted.
- NTFS and exFAT rely on the host's available mount helpers.
- Notifications require a suitable graphical session.

Do not physically unplug a drive while data is being written. After a backup,
wait for it to finish, run `sync`, and if appropriate manually unmount it with
`sudo umount /media/BACKUP`. Automatic cleanup does not replace these practices
for avoiding data corruption.

## Quick commands

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/Human-Technology/usb-automount-linux/main/install.sh | sudo bash
# List drives and configure
lsblk -f
sudo nano /etc/usb-automount/usb-automount.conf
# Logs, hooks, and UUID
sudo tail -f /var/log/usb-automount.log
ls -la /etc/usb-automount/hooks.d/
sudo blkid -s UUID -o value /dev/sdb1
# Service, manual, and uninstall
sudo systemctl status usb-automount@sdb1.service
man usb-automount
sudo ./install.sh remove
```

## More information

Repository: <https://github.com/Human-Technology/usb-automount-linux>

[README in English](../README.md) · [README en español](../README.es.md) ·
[Manual en español](MANUAL.es.md)

## License

usb-automount is distributed under the [MIT License](../LICENSE).
