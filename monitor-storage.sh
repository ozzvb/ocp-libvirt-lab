#!/usr/bin/env bash
set -euo pipefail
DIR=/var/lib/libvirt/images
printf '%s\n' '=== Espacio físico del sistema de archivos donde están las VMs ==='
df -h "$DIR"
printf '\n%s\n' '=== Ocupación física de los archivos qcow2 OpenShift ==='
for node in 01 02 03; do
  disk="$DIR/ocp-$node.qcow2"
  if sudo test -e "$disk"; then
    sudo du -h "$disk"
  else
    printf '%s: todavía no existe\n' "$disk"
  fi
done
printf '\n%s\n' 'Mantenga preferiblemente al menos 30-40 GiB libres mientras instala y prueba el clúster.'
