# Montaje Automático de USB en Linux con udev

Este proyecto proporciona un script y reglas de *udev* para montar y desmontar automáticamente dispositivos USB cuando se conectan o desconectan en un sistema Linux.

## Requisitos

- Sistema operativo Linux (cualquier distribución que soporte *udev*).
- Acceso a permisos de superusuario (root).

## Características

- **Montaje automático**: Monta automáticamente los dispositivos de almacenamiento USB en `/media/usb-*` cuando se conectan.
- **Desmontaje automático**: Desmonta automáticamente los dispositivos USB y elimina el punto de montaje cuando se desconectan.
- **Registro de eventos**: Registra los eventos de montaje y desmontaje en `/var/log/usb-automount.log`.

## Instalación

Sigue estos pasos para configurar el montaje y desmontaje automático de USB en tu sistema.

### 1. Clonar este repositorio

Primero, clona el repositorio en tu máquina local:

```bash
git clone https://github.com/tu-usuario/usb-automount-linux.git
cd usb-automount-linux
```

### 2. Copiar el script de montaje

Copia el script usb-automount.sh al directorio /usr/local/bin/ y dale permisos de ejecución:

```bash
sudo cp usb-automount.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/usb-automount.sh
```

### 3. Crear la regla de udev

Copia el archivo 99-usb-automount.rules al directorio /etc/udev/rules.d/:

```bash
sudo cp 99-usb-automount.rules /etc/udev/rules.d/
```

### 4. Recarga las reglas de udev

Despues de agregar la regla de udev, recarga las reglas para que tengan efecto:

```bash
sudo udevadm control --reload-rules
```

### 5. Probar el montaje automático de USB

Ahora, cuando conectes un dispositivo USB, debería montarse automáticamente en /media/usb-*.
Puedes verificarlo ejecutando:

```bash
df -h
```

El comando debería mostrar tu dispositivo USB montado en /media/usb-*.

### 6. Ver logs

El script registra todas las acciones de montaje y desmontaje en /var/log/usb-automount.log. Puedes consultar el log con:

```bash
cat /var/log/usb-automount.log
```

El comando debería mostrar tu dispositivo USB montado en /media/usb-*.

### Solución de problemas
- ¿El dispositivo no se monta? Asegúrate de que el script tiene permisos de ejecución y está ubicado en /usr/local/bin/.
- ¿No se crea el punto de montaje? Revisa los logs en /var/log/usb-automount.log para ver si hay errores.
- ¿Problemas de permisos? Asegúrate de que tienes los permisos necesarios para escribir en /media/ y ejecutar el script como root.

### Contribuir
Si encuentras algún problema o te gustaría contribuir al proyecto, siéntete libre de abrir un pull request o reportar un issue.
