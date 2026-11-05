#!/usr/bin/env bash
# Laboratorio compacto OCP de 3 nodos para KVM/libvirt (solo pruebas).
# Ejemplos:
#   ./provision-ocp-lab.sh check
#   ./provision-ocp-lab.sh network
#   ./provision-ocp-lab.sh vms /ruta/a/discovery.iso
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VIRSH=(sudo virsh -c qemu:///system)
NETWORK_NAME=ocp-lab
BRIDGE=virbr50
IMAGE_DIR=/var/lib/libvirt/images
ISO_DEST=/var/lib/libvirt/boot/ocp-discovery.iso

case "${1:-help}" in
  check)
    echo '=== Hardware ==='
    lscpu | grep -Ei 'Model name|CPU\(s\)|Virtualization' || true
    free -h
    df -h /var/lib/libvirt/images || true
    echo '=== Extensiones AMD (svm) ==='
    grep -m1 -o svm /proc/cpuinfo || true
    echo '=== Nested KVM ==='
    if [[ -f /sys/module/kvm_amd/parameters/nested ]]; then
      cat /sys/module/kvm_amd/parameters/nested
    else
      echo 'No disponible (revisar kvm_amd / BIOS / procesador).'
    fi
    echo '=== Libvirt ==='
    "${VIRSH[@]}" list --all
    ;;
  network)
    if "${VIRSH[@]}" net-info "$NETWORK_NAME" >/dev/null 2>&1; then
      echo "La red $NETWORK_NAME ya existe. Revise su XML antes de cambiarla."
    else
      "${VIRSH[@]}" net-define "$HERE/ocp-lab-network.xml"
    fi
    "${VIRSH[@]}" net-autostart "$NETWORK_NAME"
    if ! "${VIRSH[@]}" net-info "$NETWORK_NAME" | grep -E '^Active:[[:space:]]+yes'; then
      "${VIRSH[@]}" net-start "$NETWORK_NAME"
    fi
    "${VIRSH[@]}" net-info "$NETWORK_NAME"
    "${VIRSH[@]}" net-dumpxml "$NETWORK_NAME"
    echo "DNS de prueba: dig @192.168.150.1 api.ocp.lab.test +short"
    ;;
  vms)
    ISO_SRC="${2:-}"
    if [[ ! -f "$ISO_SRC" ]]; then
      echo 'Uso: ./provision-ocp-lab.sh vms /ruta/a/discovery.iso' >&2
      exit 2
    fi
    if ! "${VIRSH[@]}" net-info "$NETWORK_NAME" | grep -E '^Active:[[:space:]]+yes'; then
      echo "La red $NETWORK_NAME debe estar activa. Ejecute primero: $0 network" >&2
      exit 3
    fi
    sudo install -d -m 0755 /var/lib/libvirt/boot
    sudo install -m 0644 "$ISO_SRC" "$ISO_DEST"
    if command -v restorecon >/dev/null 2>&1; then
      sudo restorecon -v "$ISO_DEST" || true
    fi
    for n in 1 2 3; do
      name="$(printf 'ocp-%02d' "$n")"
      mac="$(printf '52:54:00:15:00:%02d' "$((10 + n))")"
      disk="$IMAGE_DIR/$name.qcow2"
      if "${VIRSH[@]}" dominfo "$name" >/dev/null 2>&1; then
        echo "Ya existe $name; no se modifica."
        continue
      fi
      if sudo test -e "$disk"; then
        echo "El disco $disk ya existe: no se sobrescribirá." >&2
        exit 4
      fi
      sudo qemu-img create -f qcow2 "$disk" 120G
      if command -v restorecon >/dev/null 2>&1; then
        sudo restorecon -v "$disk" || true
      fi
      sudo virt-install \
        --connect qemu:///system \
        --name "$name" \
        --memory 16384 \
        --vcpus 4 \
        --cpu host-passthrough \
        --machine q35 \
        --boot uefi,cdrom,hd \
        --os-variant generic \
        --disk "path=$disk,format=qcow2,bus=virtio" \
        --network "network=$NETWORK_NAME,model=virtio,mac=$mac" \
        --cdrom "$ISO_DEST" \
        --graphics vnc,listen=127.0.0.1 \
        --noautoconsole
    done
    "${VIRSH[@]}" list --all
    "${VIRSH[@]}" net-dhcp-leases "$NETWORK_NAME"
    echo 'A partir de aquí continúe en Red Hat Assisted Installer.'
    echo 'Al finalizar la instalación, retire el ISO si alguno de los nodos arranca de nuevo en discovery.'
    ;;
  *)
    cat <<'USAGE'
Uso:
  ./provision-ocp-lab.sh check
  ./provision-ocp-lab.sh network
  ./provision-ocp-lab.sh vms /ruta/a/discovery.iso
ATENCIÓN: herramientas para laboratorio, NO para producción.
USAGE
    ;;
esac
