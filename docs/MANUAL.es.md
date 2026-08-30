# Manual de uso — usb-automount

Guía de instalación, configuración y uso de **usb-automount**.

`usb-automount` detecta y monta automáticamente unidades USB y particiones de
tarjetas SD en Linux mediante **udev + systemd**, sin mantener un daemon en
ejecución. Está dirigido a servidores headless, Raspberry Pi, homelabs, NAS,
servidores multimedia y automatizaciones con medios extraíbles.

## Índice

1. [Cómo funciona](#cómo-funciona)
2. [Requisitos e instalación](#requisitos-e-instalación)
3. [Primera prueba](#primera-prueba)
4. [Configuración](#configuración)
5. [Etiquetas y exclusiones](#etiquetas-y-exclusiones)
6. [Hooks](#hooks)
7. [Backup automático](#backup-automático)
8. [Logs y notificaciones](#logs-y-notificaciones)
9. [Raspberry Pi, actualización y desinstalación](#raspberry-pi-actualización-y-desinstalación)
10. [Solución de problemas y limitaciones](#solución-de-problemas-y-limitaciones)
11. [Comandos rápidos](#comandos-rápidos)

## Cómo funciona

Al conectar una partición compatible, udev la detecta y pide a systemd iniciar
`usb-automount@<dispositivo>.service`. El servicio identifica el sistema de
archivos, crea un punto de montaje, monta la partición y ejecuta los hooks
`post-mount`. Cuando el dispositivo desaparece, la relación `BindsTo=` del
servicio hace que systemd ejecute su lógica de parada: desmonta, limpia el punto
de montaje y ejecuta los hooks `post-unmount`.

```text
USB / SD → udev → systemd → identificar filesystem → montar → hooks
```

Por ejemplo, la etiqueta `BACKUP` se monta normalmente en `/media/BACKUP`.

## Requisitos e instalación

Se requiere una distribución Linux con systemd, udev, Bash y las herramientas
`mount`, `umount`, `mountpoint`, `blkid`, `findmnt` y `blockdev` (normalmente
incluidas en `util-linux`). En Debian, Ubuntu o Raspberry Pi OS:

```bash
sudo apt update
sudo apt install curl git util-linux
```

Para sistemas de archivos o backups puede necesitar:

```bash
sudo apt install ntfs-3g       # NTFS
sudo apt install exfatprogs    # exFAT
sudo apt install rsync         # backups
sudo apt install libnotify-bin # notificaciones de escritorio
```

Instalación rápida desde la rama `main`:

```bash
curl -fsSL https://raw.githubusercontent.com/Human-Technology/usb-automount-linux/main/install.sh | sudo bash
```

O clona el repositorio y ejecuta el instalador:

```bash
git clone https://github.com/Human-Technology/usb-automount-linux.git
cd usb-automount-linux
sudo ./install.sh
```

Se instalan los componentes principales en:

```text
/usr/local/bin/usb-automount.sh
/etc/systemd/system/usb-automount@.service
/etc/udev/rules.d/99-usb-automount.rules
/etc/usb-automount/usb-automount.conf
/etc/usb-automount/hooks.d/
/etc/logrotate.d/usb-automount
/usr/local/share/man/man8/usb-automount.8
```

## Primera prueba

Observa el log y conecta una unidad:

```bash
sudo tail -f /var/log/usb-automount.log
```

Comprueba que Linux detectó una partición con filesystem y que fue montada:

```bash
lsblk -f
ls /media
findmnt /media/BACKUP
```

Un resultado habitual de `lsblk -f` es:

```text
NAME   FSTYPE LABEL   UUID
sdb
└─sdb1 ext4   BACKUP  6a2fedac-a59d-4bba-9d90-123456789abc
```

## Configuración

Edita `/etc/usb-automount/usb-automount.conf`:

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

| Opción | Función |
| --- | --- |
| `MOUNT_DIR` | Directorio base de los montajes. Por ejemplo, `/mnt/removable`. |
| `USE_LABEL` | Con `true`, usa la etiqueta; con `false`, usa `/media/usb-sdb1`. |
| `MIN_PARTITION_SIZE` | Tamaño mínimo en bytes; `104857600` equivale a 100 MiB. Usa `0` para no filtrar por tamaño. |
| `EXCLUDED_DEVICES` | Nombres separados por comas que no deben montarse, por ejemplo `sda,sdb2,mmcblk0`. |
| `LOG_FILE` | Ruta del registro. |
| `NOTIFY` | `auto`, `always` o `never`. |
| `HOOKS_DIR` | Directorio de scripts ejecutables posteriores al montaje y desmontaje. |

Una reinstalación conserva el archivo de configuración existente y escribe los
nuevos valores predeterminados como `usb-automount.conf.new`. Si actualizas una
instalación antigua sin configuración, el instalador conserva las rutas clásicas
con `USE_LABEL=false`.

## Etiquetas y exclusiones

Con `USE_LABEL=true`, etiquetas como `BACKUP`, `MEDIA` o `PHOTOS` producen
`/media/BACKUP`, `/media/MEDIA` y `/media/PHOTOS`. Consulta una etiqueta con:

```bash
lsblk -f
sudo blkid /dev/sdb1
```

Para asignar una etiqueta ext4, desmonta antes la partición y ejecuta:

```bash
sudo umount /dev/sdb1
sudo e2label /dev/sdb1 BACKUP
```

Los caracteres inseguros se convierten en guiones bajos; por ejemplo,
`MY BACKUP` se convierte en `MY_BACKUP`. Si ya existe un punto de montaje para
la misma etiqueta, se añade un sufijo numérico, como `BACKUP_1`.

Para excluir discos o particiones, configura por ejemplo:

```bash
EXCLUDED_DEVICES="sda,sdb2,mmcblk0"
```

Excluir un disco (`sda` o `mmcblk0`) también excluye sus particiones.

## Hooks

Los archivos regulares y ejecutables de `HOOKS_DIR` se ejecutan después de cada
montaje y desmontaje correcto. Reciben estas variables de entorno:

| Variable | Ejemplo |
| --- | --- |
| `USB_DEVICE` | `sdb1` |
| `USB_MOUNTPOINT` | `/media/BACKUP` |
| `USB_FSTYPE` | `ext4` |
| `USB_LABEL` | `BACKUP` |
| `USB_UUID` | `6a2fedac-...` |
| `USB_ACTION` | `post-mount` o `post-unmount` |

Crea un hook de prueba:

```bash
sudo nano /etc/usb-automount/hooks.d/01-test.sh
```

```bash
#!/bin/bash
if [ "$USB_ACTION" = "post-mount" ]; then
    echo "Unidad conectada: $USB_DEVICE en $USB_MOUNTPOINT"
    echo "Etiqueta: $USB_LABEL; UUID: $USB_UUID; FS: $USB_FSTYPE"
fi
```

```bash
sudo chmod +x /etc/usb-automount/hooks.d/01-test.sh
```

Para un hook de retirada, comprueba `USB_ACTION = post-unmount`. Para
desactivarlo sin borrarlo, elimina su permiso ejecutable con `sudo chmod -x`.
Los hooks se ejecutan con privilegios elevados y un hook lento mantiene ocupado
el ciclo del servicio: instala únicamente scripts de confianza.

## Backup automático

Es preferible identificar el destino por UUID, no solo por etiqueta. Obténlo
con `sudo blkid -s UUID -o value /dev/sdb1` y crea este hook:

```bash
sudo nano /etc/usb-automount/hooks.d/01-backup.sh
```

```bash
#!/bin/bash
BACKUP_UUID="6a2fedac-a59d-4bba-9d90-123456789abc"

if [ "$USB_ACTION" != "post-mount" ] || [ "$USB_UUID" != "$BACKUP_UUID" ]; then
    exit 0
fi

echo "=== Iniciando backup ==="
mkdir -p "$USB_MOUNTPOINT/server-backup"
rsync -av /srv/documents/ "$USB_MOUNTPOINT/server-backup/"
sync
echo "=== Backup completado ==="
```

```bash
sudo chmod +x /etc/usb-automount/hooks.d/01-backup.sh
```

Después de validar cuidadosamente origen y destino, puedes convertirlo en un
espejo con `rsync -av --delete`. `--delete` elimina del destino los archivos que
ya no existan en el origen; pruébalo primero sin esa opción.

## Logs y notificaciones

El log principal está en `/var/log/usb-automount.log` y se rota mediante
logrotate:

```bash
sudo tail -f /var/log/usb-automount.log
sudo tail -100 /var/log/usb-automount.log
sudo journalctl -u usb-automount@sdb1.service
sudo journalctl -b -u usb-automount@sdb1.service
```

`NOTIFY="auto"` intenta notificar cuando hay una sesión gráfica válida;
`NOTIFY="always"` requiere `notify-send`; para servidores headless usa
`NOTIFY="never"`.

## Raspberry Pi, actualización y desinstalación

Se admiten particiones SD como `mmcblk0p1` y `mmcblk1p1`. Si la tarjeta del
sistema debe ignorarse, usa `EXCLUDED_DEVICES="mmcblk0"`. Algunos discos USB
mecánicos requieren más corriente de la que suministra una Raspberry Pi; usa un
hub alimentado si es necesario.

Para actualizar una copia clonada:

```bash
cd usb-automount-linux
git pull
sudo ./install.sh
sudo diff /etc/usb-automount/usb-automount.conf /etc/usb-automount/usb-automount.conf.new
```

Para desinstalar los binarios y la integración, conservando configuración y
hooks por seguridad:

```bash
sudo ./install.sh remove
```

También se acepta `sudo ./install.sh uninstall`. Si deseas borrar después toda
la configuración y los hooks, `sudo rm -rf /etc/usb-automount` lo hace de forma
permanente.

## Solución de problemas y limitaciones

Si una unidad no se monta, confirma primero que el sistema la detecta y revisa
el log y la unidad systemd correspondiente:

```bash
lsblk -f
sudo tail -100 /var/log/usb-automount.log
sudo systemctl status usb-automount@sdb1.service
sudo udevadm monitor --udev --property
```

Tras modificar reglas o servicios, recarga y vuelve a disparar eventos:

```bash
sudo udevadm control --reload-rules
sudo systemctl daemon-reload
sudo udevadm trigger --subsystem-match=block --action=add
```

Verifica un filesystem con `sudo blkid /dev/sdb1`, que el hook sea ejecutable
(`ls -la /etc/usb-automount/hooks.d/`) y que tenga un intérprete como
`#!/bin/bash`. Para depurarlo, un hook temporal puede imprimir todas las
variables `USB_*` al log.

Limitaciones actuales:

- Se admiten particiones USB `sd…N` y SD `mmcblk…pN`; NVMe no está soportado.
- No se montan particiones sin filesystem reconocido ni las menores de 100 MiB
  de forma predeterminada.
- NTFS y exFAT dependen de los ayudantes disponibles en el sistema.
- Las notificaciones requieren una sesión gráfica adecuada.

No retires físicamente una unidad mientras se escriben datos. Tras un backup,
espera a que termine, ejecuta `sync` y, si procede, desmonta manualmente con
`sudo umount /media/BACKUP`. La limpieza automática no sustituye estas buenas
prácticas contra la corrupción de datos.

## Comandos rápidos

```bash
# Instalar
curl -fsSL https://raw.githubusercontent.com/Human-Technology/usb-automount-linux/main/install.sh | sudo bash
# Ver unidades y configurar
lsblk -f
sudo nano /etc/usb-automount/usb-automount.conf
# Logs, hooks y UUID
sudo tail -f /var/log/usb-automount.log
ls -la /etc/usb-automount/hooks.d/
sudo blkid -s UUID -o value /dev/sdb1
# Servicio, manual y desinstalación
sudo systemctl status usb-automount@sdb1.service
man usb-automount
sudo ./install.sh remove
```

## Más información

Repositorio: <https://github.com/Human-Technology/usb-automount-linux>

[README en español](../README.es.md) · [README in English](../README.md) ·
[Manual in English](MANUAL.en.md)

## Licencia

usb-automount se distribuye bajo la [licencia MIT](../LICENSE).
