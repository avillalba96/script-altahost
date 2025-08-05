# script-altahost

Script para automatizar el alta y configuración inicial de servidores UBUNTU/DEBIAN/PVE/PBS para proyectos CUSTOM o cualquier cliente.

## Compatibilidad

- Cloud/Debian9+
- Cloud/Ubuntu20.04+
- Ubuntu+Docker
- PVE v6+
- PBS v1+

## Instalación

1. Instala dependencias:

   ```bash
   apt-get update; apt-get install -y git screen
   ```

2. Ejecuta en una terminal con screen:

   ```bash
   screen
   ```

3. Clona y ejecuta el script:

   ```bash
   git clone https://github.com/avillalba96/script-altahost && cd script-altahost/install && ./altahost-start.sh
   ```

## Funcionalidades principales

- Configuración automática de SSH, banners, usuarios y servicios básicos.
- Instalación opcional de Zabbix, WireGuard, Docker, etc.
- Personalización de banners de bienvenida (MOTD) genéricos.
- Soporte para RAID ZFS (comandos útiles incluidos).

## Personalización de banners y logo

- Los banners de bienvenida se pueden personalizar editando los archivos:
  - `install/systemd/pvebanner-service_custom`
  - `install/systemd/pbsbanner-service_custom`
  - `install/systemd/vmbanner-service_custom`
- El logo mostrado en la interfaz de Proxmox debe llamarse **proxmox_logo_custom.png** y estar en la carpeta `install/images/`.  
  El script lo instalará automáticamente en el sistema.

## Pasos Opcionales

### Banners genéricos

```bash
# PVE
wget https://raw.githubusercontent.com/avillalba96/script-altahost/main/install/systemd/pvebanner-service_custom -O /usr/bin/pvebanner && chmod +x /usr/bin/pvebanner && systemctl restart pvebanner.service
# PBS
wget https://raw.githubusercontent.com/avillalba96/script-altahost/main/install/systemd/pbsbanner-service_custom -O /usr/lib/x86_64-linux-gnu/proxmox-backup/proxmox-backup-banner && chmod +x /usr/lib/x86_64-linux-gnu/proxmox-backup/proxmox-backup-banner && systemctl restart proxmox-backup-banner.service
```

### RAID ZFS (configuracion basica, machete)

Se deja a mano los comandos aplicados sobre local-zfs

```bash
zfs set reservation=20G rpool/ROOT
zfs set dedup=off rpool
zfs set compression=lz4 rpool
zfs set sync=disabled rpool
pvesm set local-zfs --blocksize 128k
pvesm set local-zfs --sparse 1
```

## TO-DO

1. Arreglar la zona horaria
2. Volver Generico <https://github.com/avillalba96/borg_config>
3. Implementar el script de forma generica <https://github.com/avillalba96/script-pve_cloudinit>

## Autores

- Maxi - [Maximiliano Baez](https://github.com/MaximilianoBz)
- Pablito - [Pablo Ramos](https://github.com/avillalba96)
- Alejandro - [Alejandro Villalba](https://github.com/avillalba96)
- Matias - [Matias Yaccuzzi](https://github.com/matiassy)
