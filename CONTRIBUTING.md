# Contributing to usb-automount

Thank you for contributing.

## Workflow

1. Fork the repository and create a branch, for example `feat/my-feature`.
2. Make a focused change.
3. Run the checks below.
4. Test on a real Linux system with removable media where possible.
5. Commit with a conventional prefix: `feat:`, `fix:`, `docs:`, or `ci:`.
6. Open a pull request describing the behaviour change.

## Checks

```bash
bash -n usb-automount.sh install.sh usb-automount.conf
shellcheck usb-automount.sh install.sh hooks.d/00-example-hook.sh.sample
```

## Code style

- Use Bash and four-space indentation.
- Keep the default configuration backward-compatible.
- Use `log()` for script event messages.
- Do not introduce a runtime dependency beyond standard Linux system tools.
- Preserve user configuration during installation and uninstallation.

## Testing hooks

Create a temporary hook to observe the hook environment:

```bash
sudo tee /etc/usb-automount/hooks.d/99-test.sh >/dev/null <<'EOF'
#!/bin/bash
echo "${USB_ACTION}: ${USB_DEVICE} at ${USB_MOUNTPOINT}" >> /tmp/usb-hook-test.log
EOF
sudo chmod +x /etc/usb-automount/hooks.d/99-test.sh
```

## Reporting issues

Include your Linux distribution and version, the last 20 log entries, and the
output of `udevadm info /dev/<device>`.
