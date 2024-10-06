# Automontaje de Dispositivos USB en Linux

Este proyecto proporciona un script y las configuraciones necesarias para automatizar el montaje y desmontaje de dispositivos USB en sistemas Linux. Al conectar una unidad USB, el dispositivo se monta automáticamente en un directorio específico. Al desconectar la unidad, se desmonta y se elimina el directorio de montaje, incluso si la desconexión es abrupta.

## Índice

- [Requisitos Previos](#requisitos-previos)
- [Características](#características)
- [Instalación](#instalación)
  - [1. Clonar el Repositorio](#1-clonar-el-repositorio)
  - [2. Configurar el Script de Automontaje](#2-configurar-el-script-de-automontaje)
  - [3. Configurar el Servicio de systemd](#3-configurar-el-servicio-de-systemd)
  - [4. Configurar las Reglas de udev](#4-configurar-las-reglas-de-udev)
  - [5. Recargar las Configuraciones](#5-recargar-las-configuraciones)
- [Ver logs](#ver-logs)
- [Uso](#uso)
- [Solución de Problemas](#solución-de-problemas)

## Requisitos Previos

Antes de comenzar, asegúrate de tener los siguientes requisitos:

- Sistema operativo Linux (probado en Debian, Ubuntu y derivadas).
- Privilegios de superusuario (root) para instalar y configurar el script y los servicios.

## Características

- **Montaje automático**: Monta automáticamente los dispositivos de almacenamiento USB en `/media/usb-*` cuando se conectan.
- **Desmontaje automático**: Desmonta automáticamente los dispositivos USB y elimina el punto de montaje cuando se desconectan.
- **Registro de eventos**: Registra los eventos de montaje y desmontaje en `/var/log/usb-automount.log`.

## Instalación

Sigue estos pasos para configurar el montaje y desmontaje automático de USB en tu sistema.

### 1. Clonar este repositorio

Primero, clona el repositorio en tu máquina local:

```bash
git clone [https://github.com/tu-usuario/usb-automount-linux.git](https://github.com/Human-Technology/usb-automount-linux.git)
cd usb-automount-linux
```

### 2. Copiar el script de montaje

Copia el script `usb-automount.sh` al directorio `/usr/local/bin/`, dale permisos de ejecución y establece al prietario como root:

```bash
sudo cp usb-automount.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/usb-automount.sh
sudo chown root:root /usr/local/bin/usb-automount.sh
```

Asegurate de que el script utiliza rutas absolutas para todos los comandos y que el `PAHT` está configurado correctamente:

```bash
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

### 3. Configurar el Servicio de systemd
Copia el archivo de servicio `usb-automount@.service` a `/etc/systemd/system/`:

```bash
sudo cp usb-automount@.service /etc/systemd/system/
```

Asegúrate de que el archivo tiene los permisos correctos:

```bash
sudo chmod 644 /etc/systemd/system/usb-automount@.service
sudo chown root:root /etc/systemd/system/usb-automount@.service
```

El contenido del archivo de servicio debe ser el siguiente:

```bash
[Unit]
Description=Automontaje de USB para %I
Requires=dev-%i.device
BindsTo=dev-%i.device
After=dev-%i.device

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/usb-automount.sh %I add
ExecStop=/usr/local/bin/usb-automount.sh %I remove
TimeoutStopSec=5s

[Install]
WantedBy=dev-%i.device

```

### 4. Crear las reglas de udev

Copia el archivo `99-usb-automount.rules` al directorio `/etc/udev/rules.d/`:

```bash
sudo cp 99-usb-automount.rules /etc/udev/rules.d/
```

### 4. Recarga las configuraciones

Despues de copiar y configurar los archivos, es necesario recargar las reglas de udev y los archivos de servicio de systemd:

```bash
sudo udevadm control --reload-rules
sudo systemctl daemon-reload
```

## Uso
Una vez completada la instalación, el sistema montará automáticamente cualquier dispositivo USB que conectes y desmontará y limpiará el punto de montaje al desconectarlo, incluso si la desconexión es abrupta.

- **Montaje automático:**
  Al conectar una unidad USB, se montará automáticamente en `/media/usb-[dispositivo]`, donde `[dispositivo]` es el identificador del dispositivo, como `sdb1`.
  
- **Montaje automático:**
  Al desconectar la unidad USB, el sistema desmontará el dispositivo y eliminará el directorio de montaje correspondiente.
  
## Ver logs

El script registra todas las acciones de montaje y desmontaje en `/var/log/usb-automount.log`. Puedes consultar el log con:

```bash
cat /var/log/usb-automount.log
```

El comando debería mostrar tu dispositivo USB montado en /media/usb-*.

## Solución de problemas
- **¿El dispositivo no se monta?** Asegúrate de que el script tiene permisos de ejecución y está ubicado en `/usr/local/bin/`.
- **¿No se crea el punto de montaje?** Revisa los logs en `/var/log/usb-automount.log` para ver si hay errores.
- **¿Problemas de permisos?** Asegúrate de que tienes los permisos necesarios para escribir en `/media/` y ejecutar el script como root.
- **Reiniciar el sistema: Si los problemas persisten, reinicia el sistema para asegurar que todas las configuraciones se carguen correctamente.

## Contribuir
Si encuentras algún problema o te gustaría contribuir al proyecto, siéntete libre de abrir un pull request o reportar un issue.
