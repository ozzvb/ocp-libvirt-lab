# Laboratorio OpenShift Virtualization de tres nodos (KVM/libvirt)

**Solo para pruebas.** Tres máquinas virtuales OpenShift de 4 vCPU, 16 GiB de RAM y disco qcow2 thin de 120 GiB. Hardware de referencia: Ryzen 7 5800XT, 64 GB de RAM. Sistema anfitrión Linux con libvirt y KVM. Este equipo está en el límite de memoria de OpenShift y no garantiza holgura para VMs dentro del clúster.

## Adaptación al almacenamiento limitado de 264 GB

**Solo para laboratorio, no para producción.** Se crean **tres discos de 120 GiB virtuales (360 GiB lógicos)** en formato `qcow2` *thin*, sin preasignar los 360 GiB en el SSD. Se ocupa capacidad real conforme OpenShift escribe datos. **Esto puede agotar el SSD** aunque los discos de las VMs todavía indiquen espacio disponible.

Si los 264 GB son la **capacidad total** del equipo (incluido Linux), la holgura será menor. Verifique antes de comenzar:

```bash
df -h /var/lib/libvirt/images
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
```

Evite ODF, snapshots locales, ISO adicionales e imágenes de VMs dentro de OpenShift en esta fase. Reserve idealmente 30–40 GiB libres de seguridad en el SSD y vigile el espacio durante toda la instalación:

```bash
./monitor-storage.sh
watch -n 60 ./monitor-storage.sh
```

Si no puede mantener esa reserva, detenga el laboratorio y amplíe el almacenamiento o use un disco externo SSD adecuado antes de continuar.

**Si ya creó los discos/VMs de 150 GiB con el paquete anterior**, el script nuevo no los modifica ni reduce. No reduzca discos instalados con un simple `qemu-img resize`; hacerlo sin preparar las particiones y sistemas de archivos puede destruirlos. Para comenzar de cero, cree discos nuevos después de respaldar cualquier información importante.

## Red

- Puente NAT: `virbr50`, red `192.168.150.0/24`, gateway y DNS `192.168.150.1`
- `ocp-01`: `192.168.150.11`, MAC `52:54:00:15:00:11`
- `ocp-02`: `192.168.150.12`, MAC `52:54:00:15:00:12`
- `ocp-03`: `192.168.150.13`, MAC `52:54:00:15:00:13`
- API VIP: `192.168.150.20` → `api.ocp.lab.test`, `api-int.ocp.lab.test`
- Ingress VIP: `192.168.150.21` → `*.apps.ocp.lab.test`
- En Assisted Installer: cluster `ocp`, base domain `lab.test`, tres control plane, cero workers, `machineNetwork=192.168.150.0/24`, cluster-managed networking, VIPs manuales.

El DNS se presta por dnsmasq de libvirt, no por una VM adicional. Para resolver desde el equipo anfitrión, si usa systemd-resolved:

```bash
sudo resolvectl dns virbr50 192.168.150.1
sudo resolvectl domain virbr50 '~ocp.lab.test'
```

Comprobaciones:

```bash
dig @192.168.150.1 api.ocp.lab.test +short
dig @192.168.150.1 console-openshift-console.apps.ocp.lab.test +short
sudo virsh -c qemu:///system net-dhcp-leases ocp-lab
```

## Paquetes del anfitrión

Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst qemu-utils ovmf dnsutils virt-viewer
sudo systemctl enable --now libvirtd
```

Fedora/RHEL:

```bash
sudo dnf install -y qemu-kvm libvirt virt-install qemu-img edk2-ovmf bind-utils virt-viewer
sudo systemctl enable --now libvirtd || sudo systemctl enable --now virtqemud.socket virtnetworkd.socket
```

Compruebe SVM y nested en BIOS/kernel. Si el valor `/sys/module/kvm_amd/parameters/nested` es `N` o `0`, agregue `options kvm_amd nested=1` a `/etc/modprobe.d/kvm_amd.conf` y reinicie.

## Ejecutar

Desde el directorio de estos archivos:

```bash
chmod +x provision-ocp-lab.sh
./provision-ocp-lab.sh check
./provision-ocp-lab.sh network
./provision-ocp-lab.sh vms /ruta/completa/a/discovery.iso
```

**Primero debes crear un clúster de tres nodos en https://console.redhat.com/openshift y descargar su Discovery ISO.** Usa la misma ISO para los tres nodos del mismo clúster.

## Precauciones

- El script no sobrescribe máquinas ni discos ya existentes, pero crea redes y tres VMs: revísalo antes de ejecutarlo.
- La red NAT no es accesible automáticamente desde otros equipos de la LAN.
- No compartas pull secrets, tokens, kubeconfigs ni claves SSH privadas.
- Si las VMs vuelven a iniciar la ISO después de terminar la instalación, apágalas únicamente cuando el instalador confirme que han terminado. Luego inspecciona `virsh domblklist ocp-01 --details`, retira la ISO del CD-ROM con `virsh change-media`, o cambia el orden de arranque para dar prioridad al disco.
- El `dnsmasq:options` personalizado de libvirt usa una extensión documentada sin garantía de compatibilidad en todas las versiones; revisa `virsh net-dumpxml` y las respuestas DNS.
- OpenShift Virtualization sobre KVM anidado es únicamente para pruebas, no una arquitectura de producción con soporte.

## Después de instalar

Descarga `kubeconfig` del Assisted Installer y comprueba:

```bash
export KUBECONFIG=$HOME/ocp-lab/auth/kubeconfig
oc get nodes -o wide
oc get co
oc get infrastructure cluster -o jsonpath='{.status.controlPlaneTopology}{"\n"}{.status.infrastructureTopology}{"\n"}'
```

Deberían aparecer tres nodos `Ready` y topologías `HighlyAvailable`. En una segunda fase instala almacenamiento apto para PVC, OpenShift Virtualization Operator y el recurso HyperConverged. No se recomienda instalar ODF distribuido en un equipo de 64 GB para este laboratorio.

## Referencias

- https://libvirt.org/formatnetwork.html
- https://docs.redhat.com/en/documentation/assisted_installer_for_openshift_container_platform/2026/html/installing_openshift_container_platform_with_the_assisted_installer/installing-with-ui
- https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/installing
# ocp-libvirt-lab
