#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Variables
device="$1"  # Primer argumento, el dispositivo (por ejemplo, sdb1)
action="$2"  # Segundo argumento, indica la acción (add o remove)

# Verificar si los argumentos están presentes
if [ -z "$device" ] || [ -z "$action" ]; then
    echo "$(date) - Uso incorrecto: se requieren el dispositivo y la acción (add/remove)" >> /var/log/usb-automount.log
    exit 1
fi

# Obtener el nombre del punto de montaje
mountpoint="/media/usb-$device"

# Si el evento es "add", intentamos montar el dispositivo
if [ "$action" == "add" ]; then

    # Verificamos el tamaño de la partición y descartamos particiones pequeñas (<100MB)
    partition_size=$(/sbin/blockdev --getsize64 "/dev/$device" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "$(date) - No se pudo obtener el tamaño de la partición /dev/$device" >> /var/log/usb-automount.log
        exit 1
    fi

    min_size=$((100 * 1024 * 1024))  # 100MB en bytes

    if [ "$partition_size" -lt "$min_size" ]; then
        echo "$(date) - Partición /dev/$device demasiado pequeña para montar (menos de 100MB), saltando..." >> /var/log/usb-automount.log
        exit 0
    fi

    # Detectar el tipo de sistema de archivos con blkid
    fs_type=$(/sbin/blkid -o value -s TYPE "/dev/$device" 2>/dev/null)
    if [ -z "$fs_type" ]; then
        echo "$(date) - No se pudo detectar el sistema de archivos en /dev/$device" >> /var/log/usb-automount.log
        exit 1
    fi

    # Crear el punto de montaje si no existe
    /bin/mkdir -p "$mountpoint"

    # Montar el dispositivo según el tipo de sistema de archivos
    if [ "$fs_type" == "ntfs" ]; then
        if /bin/mount -t ntfs-3g "/dev/$device" "$mountpoint"; then
            echo "$(date) - Dispositivo /dev/$device (NTFS) montado en $mountpoint" >> /var/log/usb-automount.log
        else
            echo "$(date) - Error al montar /dev/$device (NTFS)" >> /var/log/usb-automount.log
        fi
    elif [[ "$fs_type" == ext* ]]; then
        if /bin/mount -t "$fs_type" "/dev/$device" "$mountpoint"; then
            echo "$(date) - Dispositivo /dev/$device ($fs_type) montado en $mountpoint" >> /var/log/usb-automount.log
        else
            echo "$(date) - Error al montar /dev/$device ($fs_type)" >> /var/log/usb-automount.log
        fi
    elif [ "$fs_type" == "vfat" ] || [ "$fs_type" == "exfat" ]; then
        if /bin/mount -t "$fs_type" "/dev/$device" "$mountpoint"; then
            echo "$(date) - Dispositivo /dev/$device ($fs_type) montado en $mountpoint" >> /var/log/usb-automount.log
        else
            echo "$(date) - Error al montar /dev/$device ($fs_type)" >> /var/log/usb-automount.log
        fi
    else
        if /bin/mount "/dev/$device" "$mountpoint"; then
            echo "$(date) - Dispositivo /dev/$device montado en $mountpoint con sistema de archivos $fs_type" >> /var/log/usb-automount.log
        else
            echo "$(date) - Error al montar /dev/$device (tipo de sistema de archivos desconocido: $fs_type)" >> /var/log/usb-automount.log
        fi
    fi

fi

# Si el evento es "remove", desmontamos el dispositivo
if [ "$action" == "remove" ]; then
    echo "$(date) - Intentando desmontar el dispositivo /dev/$device" >> /var/log/usb-automount.log

    # Intentamos desmontar el punto de montaje
    if /bin/umount "$mountpoint" 2>/dev/null; then
        echo "$(date) - Dispositivo /dev/$device desmontado de $mountpoint" >> /var/log/usb-automount.log
    else
        echo "$(date) - Error al desmontar /dev/$device desde $mountpoint, intentando forzar el desmontaje" >> /var/log/usb-automount.log
        /bin/umount -l "$mountpoint" 2>/dev/null
    fi

    # Eliminar el directorio de montaje si ya no está montado
    if ! /bin/mountpoint -q "$mountpoint"; then
        /bin/rm -rf "$mountpoint"
        echo "$(date) - Directorio de montaje $mountpoint eliminado tras desmontaje" >> /var/log/usb-automount.log
    else
        echo "$(date) - El punto de montaje $mountpoint sigue montado." >> /var/log/usb-automount.log
    fi
fi
