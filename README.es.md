# 🔌 usb-automount

[![Licencia: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![ShellCheck](https://github.com/Human-Technology/usb-automount-linux/actions/workflows/lint.yml/badge.svg)](https://github.com/Human-Technology/usb-automount-linux/actions)
[![Versión: 2.0](https://img.shields.io/badge/version-2.0-blue.svg)](https://github.com/Human-Technology/usb-automount-linux/releases)

**Montaje automático de unidades extraíbles para servidores Linux sin interfaz gráfica y Raspberry Pi.**

Conecta una unidad USB o una partición SD para montarla automáticamente. Al
retirarla, se limpia su punto de montaje. El proyecto usa udev y systemd, sin
mantener un demonio en ejecución.

> 🇬🇧 [Read in English](README.md)

Para la instalación, configuración, hooks, respaldos y solución de problemas,
consulta el [manual completo](docs/MANUAL.es.md).

## Características

- Montaje y desmontaje automático mediante udev y systemd.
- Puntos de montaje basados en etiquetas, como `/media/RESPALDO`; las rutas
  clásicas por nombre de dispositivo siguen disponibles mediante configuración.
- Directorio de montaje, tamaño mínimo, exclusiones, registros, notificaciones
  y hooks configurables.
- Hooks ejecutables posteriores al montaje y desmontaje para respaldos y
  sincronizaciones.
- Rotación de registros, página de manual y CI con ShellCheck.
- Compatibilidad con discos USB y particiones SD (`mmcblk…p…`); NVMe no está
  incluido.

## Inicio rápido

Instalación en una línea desde la rama `main`:

```bash
curl -fsSL https://raw.githubusercontent.com/Human-Technology/usb-automount-linux/main/install.sh | sudo bash
```

O clona el repositorio para inspeccionarlo antes:

```bash
git clone https://github.com/Human-Technology/usb-automount-linux.git
cd usb-automount-linux
sudo ./install.sh
```

Conecta una partición compatible y sigue los eventos con:

```bash
tail -f /var/log/usb-automount.log
```

## Configuración

El instalador crea `/etc/usb-automount/usb-automount.conf`. Edítalo para cambiar
el comportamiento; una reinstalación nunca sobreescribe la configuración existente.

| Opción | Predeterminado | Descripción |
| --- | --- | --- |
| `MOUNT_DIR` | `/media` | Directorio base para puntos de montaje. |
| `USE_LABEL` | `true` | Usa la etiqueta del sistema de archivos como nombre. |
| `MIN_PARTITION_SIZE` | `104857600` | Tamaño mínimo en bytes (100 MiB). |
| `EXCLUDED_DEVICES` | `""` | Dispositivos a omitir separados por comas, como `sda,sdb`. |
| `LOG_FILE` | `/var/log/usb-automount.log` | Ruta del registro de eventos. |
| `NOTIFY` | `auto` | Notificaciones: `auto`, `always` o `never`. |
| `HOOKS_DIR` | `/etc/usb-automount/hooks.d` | Directorio de hooks ejecutables. |

Con `USE_LABEL=true`, una unidad con etiqueta `RESPALDO` se monta en
`/media/RESPALDO`. Las etiquetas se limpian para crear nombres de directorio
seguros. Etiquetas duplicadas ya montadas reciben un sufijo numérico. Usa
`USE_LABEL=false` para conservar el formato clásico, por ejemplo
`/media/usb-sdb1`. Al actualizar una instalación v1 sin archivo de configuración,
el instalador conserva automáticamente el formato clásico.

## Hooks

Coloca scripts ejecutables en `/etc/usb-automount/hooks.d/`. Se ejecutan después
de un montaje o desmontaje correcto y reciben estas variables de entorno:

| Variable | Ejemplo | Descripción |
| --- | --- | --- |
| `USB_DEVICE` | `sdb1` | Nombre del dispositivo. |
| `USB_MOUNTPOINT` | `/media/RESPALDO` | Punto de montaje. |
| `USB_FSTYPE` | `ext4` | Tipo de sistema de archivos. |
| `USB_LABEL` | `RESPALDO` | Etiqueta, cuando existe. |
| `USB_UUID` | `1234-ABCD` | UUID, cuando existe. |
| `USB_ACTION` | `post-mount` | `post-mount` o `post-unmount`. |

Ejemplo de hook de respaldo:

```bash
#!/bin/bash
# /etc/usb-automount/hooks.d/01-respaldo.sh

if [ "$USB_ACTION" = "post-mount" ] && [ "$USB_UUID" = "TU-UUID-AQUI" ]; then
    rsync -av --delete /home/user/documentos/ "$USB_MOUNTPOINT/respaldo/"
fi
```

Hazlo ejecutable con `sudo chmod +x /etc/usb-automount/hooks.d/01-respaldo.sh`.
Se instala un ejemplo inactivo como `00-example-hook.sh.sample`.

## Raspberry Pi

usb-automount funciona bien en Raspberry Pi OS Lite, NAS, servidores multimedia
y estaciones de respaldo desatendidas. También se detectan particiones de la
tarjeta SD; excluye la tarjeta del sistema en la configuración si puede ser
elegible para montaje. Para discos mecánicos alimentados por USB, usa un hub con
alimentación propia.

El soporte de sistemas de archivos depende del kernel y de los ayudantes de
montaje instalados en el sistema. Instala el paquete de tu distribución si exFAT
o NTFS lo requiere.

## Comparación

| Capacidad | usb-automount | usbmount | udiskie |
| --- | :---: | :---: | :---: |
| Diseñado para sistemas headless | ✅ | ✅ | ⚠️ |
| Rutas basadas en etiquetas | ✅ | ❌ | ✅ |
| Sin demonio permanente | ✅ | ✅ | ❌ |
| Ciclo de vida nativo udev → systemd | ✅ | ❌ | ❌ |
| Hooks de montaje y desmontaje | ✅ | ✅ | ✅ |
| Notificaciones de escritorio opcionales | ✅ | ❌ | ✅ |
| Raspberry Pi y tarjetas SD | ✅ | ⚠️ | ⚠️ |

[usbmount](https://github.com/rbrito/usbmount) es una solución tradicional
basada en udev. [udiskie](https://github.com/coldfix/udiskie) es un front end
completo para udisks2 orientado principalmente a sesiones de usuario.
usb-automount se concentra en una canalización systemd pequeña y administrada
por root para equipos desatendidos.

## Instalación manual

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

## Solución de problemas

- **El dispositivo no se monta:** revisa `tail -f /var/log/usb-automount.log` y
  verifica que la partición tenga un sistema de archivos reconocido.
- **La ruta cambió:** establece `USE_LABEL=false` para recuperar las rutas por
  nombre de dispositivo.
- **Una partición nunca debe montarse:** añádela, o añade su disco padre, a
  `EXCLUDED_DEVICES`, por ejemplo `EXCLUDED_DEVICES="mmcblk0,sda"`.
- **Los hooks no se ejecutan:** verifica que sean archivos regulares y ejecutables.
- **Los cambios no se aplican:** ejecuta `sudo udevadm control --reload-rules`
  y `sudo systemctl daemon-reload`.

Consulta el manual instalado con `man usb-automount`.

## Desinstalación

```bash
sudo ./install.sh remove
```

Se eliminan los binarios y archivos de integración instalados. La configuración
y los hooks permanecen en `/etc/usb-automount/` por seguridad.

## Contribuir

Consulta [CONTRIBUTING.md](CONTRIBUTING.md).

## Licencia

Licencia MIT — consulta [LICENSE](LICENSE).
