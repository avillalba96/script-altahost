# **script-altahost**

Script para dar alta a UBUNTU/DEBIAN/PVE/PBS en base a necesidad de Lunix SRL, **pero se puede usar de forma generica para cualquier cliente**

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

* Agregar alta con wireguard y dialog <https://github.com/avillalba96/mkt-wireguard_init>
* Verficiar porque no se genera /var/log/syslog *(proxmox sabemos que no se genera)*
* Que el usuario que genera "lunix" sea consultado para volverlo generico
* Se detectaron los siguientes errores:

```bash
Setting up fail2ban (1.0.2-3ubuntu0.1) ... /usr/lib/python3/dist-packages/fail2ban/tests/fail2banregextestcase.py:224: SyntaxWarning: invalid escape sequence '\s' "1490349000 test failed.dns.ch", "^\s*test <F-ID>\S+</F-ID>" /usr/lib/python3/dist-packages/fail2ban/tests/fail2banregextestcase.py:435: SyntaxWarning: invalid escape sequence '\S' '^'+prefix+'<F-ID>User <F-USER>\S+</F-USER></F-ID> not allowed\n' /usr/lib/python3/dist-packages/fail2ban/tests/fail2banregextestcase.py:443: SyntaxWarning: invalid escape sequence '\S' '^'+prefix+'User <F-USER>\S+</F-USER> not allowed\n' /usr/lib/python3/dist-packages/fail2ban/tests/fail2banregextestcase.py:444: SyntaxWarning: invalid escape sequence '\d' '^'+prefix+'Received disconnect from <F-ID><ADDR> port \d+</F-ID>' /usr/lib/python3/dist-packages/fail2ban/tests/fail2banregextestcase.py:451: SyntaxWarning: invalid escape sequence '\s' _test_variants('common', prefix="\s*\S+ sshd\[<F-MLFID>\d+</F-MLFID>\]:\s+") /usr/lib/python3/dist-packages/fail2ban/tests/fail2banregextestcase.py:537: SyntaxWarning: invalid escape sequence '\[' 'common[prefregex="^svc\[<F-MLFID>\d+</F-MLFID>\] connect <F-CONTENT>.+</F-CONTENT>$"' /usr/lib/python3/dist-packages/fail2ban/tests/servertestcase.py:1375: SyntaxWarning: invalid escape sequence '\s' "{ nft -a list chain inet f2b-table f2b-chain | grep -oP '@addr-set-j-w-nft-mp\s+.*\s+\Khandle\s+(\d+)$'; } | while read -r hdl; do", /usr/lib/python3/dist-packages/fail2ban/tests/servertestcase.py:1378: SyntaxWarning: invalid escape sequence '\s' "{ nft -a list chain inet f2b-table f2b-chain | grep -oP '@addr6-set-j-w-nft-mp\s+.*\s+\Khandle\s+(\d+)$'; } | while read -r hdl; do", /usr/lib/python3/dist-packages/fail2ban/tests/servertestcase.py:1421: SyntaxWarning: invalid escape sequence '\s' "{ nft -a list chain inet f2b-table f2b-chain | grep -oP '@addr-set-j-w-nft-ap\s+.*\s+\Khandle\s+(\d+)$'; } | while read -r hdl; do", /usr/lib/python3/dist-packages/fail2ban/tests/servertestcase.py:1424: SyntaxWarning: invalid escape sequence '\s' "{ nft -a list chain inet f2b-table f2b-chain | grep -oP '@addr6-set-j-w-nft-ap\s+.*\s+\Khandle\s+(\d+)$'; } | while read -r hdl; do", Created symlink /etc/systemd/system/multi-user.target.wants/fail2ban.service → /usr/lib/systemd/system/fail2ban.service. Setting up python3-pyinotify (0.9.6-2ubuntu1) ... Processing triggers for man-db (2.12.0-4build2) ...

######

el WARNING del final de motd, el que te dice si instalo bien docker, no tiene color.
```
