#!/bin/bash

# Variables
device=$1  # Primer argumento, el dispositivo (por ejemplo, sda1)
action=$2  # Segundo argumento, indica la acción (add o remove)

# Obtener el nombre del punto de montaje
mountpoint="/media/usb-$device"

# Si el evento es "add", montamos el dispositivo
if [ "$action" != "remove" ]; then
    # Crear el punto de montaje si no existe
    mkdir -p $mountpoint

    # Montar el dispositivo
    if mount /dev/$device $mountpoint; then
        echo "Dispositivo /dev/$device montado en $mountpoint" >> /var/log/usb-automount.log
    else
        echo "Error al montar /dev/$device" >> /var/log/usb-automount.log
    fi
fi

# Si el evento es "remove", desmontamos el dispositivo
if [ "$action" == "remove" ]; then
    # Intentar desmontar el dispositivo
    if umount /dev/$device; then
        echo "Dispositivo /dev/$device desmontado de $mountpoint" >> /var/log/usb-automount.log
        # Eliminar el directorio de montaje
        rm -rf $mountpoint
    else
        echo "Error al desmontar /dev/$device" >> /var/log/usb-automount.log
    fi
fi
