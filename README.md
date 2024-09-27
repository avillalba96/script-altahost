# **script-altahost**

Script para dar alta a UBUNTU/DEBIAN/PVE/PBS en base a necesidad de Lunix SRL

**Verificado en:**

```bash
Cloud/Debian9+
Cloud/Ubuntu20.04+
Ubuntu+Docker
PVE v6+
PBS v1+
```

## **Instalación** 🔧

```bash
apt-get update; apt-get install -y git screen
git clone https://github.com/avillalba96/script-altahost && cd "$(basename "$_" .git)" && cd install && ./alta.lunixstart.sh
```

## **Actualización del banner**

Cuando se actualizan los paquetes de PVE/PBS estos sobreescriben nuestro banner de bienvenida, por lo tanto en caso de mantenerlo es necesario volver a bajarlo:

```bash
### BANNER LUNIX
# PVE
wget https://raw.githubusercontent.com/avillalba96/script-altahost/main/install/systemd/pvebanner-service -O /usr/bin/pvebanner && chmod +x /usr/bin/pvebanner
sed -i "s/.data.status.toLowerCase() !==/.data.status.toLowerCase() ==/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
sed -i "s/www.proxmox.com/www.lunix.com.ar/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
wget https://github.com/avillalba96/script-altahost/raw/main/install/images/proxmox_logo.png -O /usr/share/pve-manager/images/proxmox_logo.png
systemctl restart pvebanner.service
systemctl restart pveproxy.service
# PBS
wget https://raw.githubusercontent.com/avillalba96/script-altahost/main/install/systemd/pbsbanner-service -O /usr/lib/x86_64-linux-gnu/proxmox-backup/proxmox-backup-banner && chmod +x /usr/lib/x86_64-linux-gnu/proxmox-backup/proxmox-backup-banner
sed -i "s/.data.status.toLowerCase() !==/.data.status.toLowerCase() ==/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
sed -i "s/www.proxmox.com/www.lunix.com.ar/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
wget https://github.com/avillalba96/script-altahost/raw/main/install/images/proxmox_logo.png -O /usr/share/javascript/proxmox-backup/images/proxmox_logo.png
systemctl restart proxmox-backup-banner.service
systemctl restart proxmox-backup-proxy.service


### BANNER GENERICO
# PVE
wget https://raw.githubusercontent.com/avillalba96/script-altahost/main/install/systemd/pvebanner-service_example -O /usr/bin/pvebanner && chmod +x /usr/bin/pvebanner && systemctl restart pvebanner.service
# PBS
wget https://raw.githubusercontent.com/avillalba96/script-altahost/main/install/systemd/pbsbanner-service_example -O /usr/lib/x86_64-linux-gnu/proxmox-backup/proxmox-backup-banner && chmod +x /usr/lib/x86_64-linux-gnu/proxmox-backup/proxmox-backup-banner && systemctl restart proxmox-backup-banner.service
```

### **RAID ZFS *(configuracion basica, machete)***

Se deja a mano los comandos aplicados sobre local-zfs

```bash
zfs set reservation=20G rpool/ROOT
zfs set dedup=off rpool
zfs set compression=lz4 rpool
zfs set sync=disabled rpool
pvesm set local-zfs --blocksize 128k
pvesm set local-zfs --sparse 1
```

### **Autores** ✒️

* **Maxi** - [Maximiliano Baez](https://github.com/MaximilianoBz)
* **Franco** - [Franco Grismado](https://github.com/fgrismado)
* **Pablito** - [Pablo Ramos](https://github.com/avillalba96)
* **Alejandro** - [Alejandro Villalba](https://github.com/avillalba96)

### **Cosas por hacer** 📦

* Ver altahosts.log, hay errores *(tmbn esta el script alta vpn, una linea)*
* Verficiar porque no se genera /var/log/syslog *(proxmox sabemos que no se genera)*
* Sacar de la instalacion la opcion de KEXEC
* Generar instalacion de cliente teleport (ver tema de usar token permanente y/o rotativo)
* borg version y completo, zabbix version, docker version, ubuntu/debian version, generate_user, colores en los logs y echo, que sea mas generico y no tanto LUNIX(por ejemplo el motd traerlo de un url, el usuario, el borg, lo que sea que haga referencia a lunix) la idea es lograr un altahosts mas generalizado
* generalirar vpn-ssp *(la palabra no molesta)*, quitar el checkping no hace falta
* no genera el /etc/lunix/alta_lunix al finalizar correctamente, pero tmbn generalizarlo
* Generar para docker la carpeta en /u/var-lib/docker (revisar como solucionar al no tener el disco secundario montado)

```bash
#Create folder
mkdir -p /u/var-lib-docker
#Stop all containers
systemctl stop docker.socket
systemctl stop docker.service
systemctl stop containerd.service
#Copy all data
rsync -avh --progress /var/lib/docker/ /u/var-lib-docker/.
#Remove old folder
rm -r /var/lib/docker
#Create symlink
ln -s /u/var-lib-docker /var/lib/docker
#Reboot and start all containers
reboot
```
