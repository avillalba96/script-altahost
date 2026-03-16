# script-altahost

Script para automatizar el alta y configuración inicial de servidores UBUNTU/DEBIAN/PVE/PBS para proyectos CUSTOM o cualquier cliente.

El script está pensado para **todas las versiones en soporte activo o extendido** de las distros indicadas. Se evitan dependencias deprecadas (p. ej. `apt-key`) y se usan versiones actuales de Zabbix LTS, Docker Compose (plugin), etc.

## Compatibilidad

| Entorno        | Versiones objetivo (soporte activo/extendido) |
|----------------|------------------------------------------------|
| Debian         | 11, 12, 13                                    |
| Ubuntu         | 20.04, 22.04, 24.04                           |
| Proxmox VE     | 7, 8                                          |
| Proxmox Backup | 2, 3                                          |
| Docker         | Solo Ubuntu (según README)                     |

- Cloud/Debian y Cloud/Ubuntu en las versiones anteriores.
- Ubuntu + Docker: instalación opcional de Docker + plugin Compose.
- PVE/PBS: repos enterprise y no-subscription; fail2ban, ZFS, etc.

## Instalación

1. Instala dependencias básicas:

   ```bash
   apt-get update; apt-get install -y git screen
   ```

2. Ejecuta en una terminal con screen:

   ```bash
   screen
   ```

3. Clona y ejecuta el script (en una VM recién instalada si es posible):

   ```bash
   git clone https://github.com/avillalba96/script-altahost && cd script-altahost/install && ./altahost-start.sh
   ```

## Funcionalidades principales

- Configuración automática de SSH, banners, usuarios y servicios básicos.
- Filtro SSH por país con **ipinfo** (IPv4 e IPv6; sin geoip por compatibilidad en Ubuntu 24 / Debian 13).
- Instalación opcional de Zabbix (7.4 LTS), WireGuard, Docker + Compose plugin, Borg, etc.
- Personalización de banners de bienvenida (MOTD) genéricos.
- Soporte para RAID ZFS (ARC generado según RAM; buenas prácticas para equipos con al menos 8 GB).
- MegaRAID: repositorio con keyring `signed-by` (sin `apt-key` deprecado).
 - Zona horaria configurable vía menú (por defecto `America/Argentina/Buenos_Aires`).

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

Se deja a mano los comandos aplicados sobre local-zfs. El script ya aplica ARC según RAM (2 GB mín, 50 % máx, tope 16 GB).

```bash
zfs set reservation=20G rpool/ROOT
zfs set dedup=off rpool
zfs set compression=lz4 rpool
zfs set sync=disabled rpool
pvesm set local-zfs --blocksize 128k
pvesm set local-zfs --sparse 1
```

## TO-DO

1. Permitir definir la zona horaria también en modos no interactivos (por variable/archivo para cloud-init, etc.)
2. Volver Genérico <https://github.com/avillalba96/borg_config>
3. Implementar el script de forma genérica <https://github.com/avillalba96/script-pve_cloudinit>
4. Revisar periódicamente versiones (Zabbix, ipinfo, etc.) en el bloque de variables del script

## Autores

- Maxi - [Maximiliano Baez](https://github.com/MaximilianoBz)
- Pablito - [Pablo Ramos](https://github.com/avillalba96)
- Alejandro - [Alejandro Villalba](https://github.com/avillalba96)
- Matias - [Matias Yaccuzzi](https://github.com/matiassy)
