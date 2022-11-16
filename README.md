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

Cuando se actualizan los paquetes de PVE este pisan nuestro banner de bienvenida, por lo tanto en caso de mantenerlo es necesario volver a bajarlo:

```bash
wget https://raw.githubusercontent.com/avillalba96/script-altahost/main/install/systemd/pvebanner-service -O /usr/bin/pvebanner && chmod +x /usr/bin/pvebanner && systemctl restart pvebanner.service
```

### **Autores** ✒️

* **Maxi** - [Maximiliano Baez](https://github.com/MaximilianoBz)
* **Franco** - [Franco Grismado](https://github.com/fgrismado)
* **Pablito** - [Pablo Ramos](https://github.com/avillalba96)
* **Alejandro** - [Alejandro Villalba](https://github.com/avillalba96)

### **Cosas por hacer** 📦

1. Generar para docker la carpeta en /u/var-lib/docker (revisar como solucionar al no tener el disco secundario montado)

```bash
rm -r /var/lib/docker
mkdir -p /u/var-lib-docker
ln -s /u/var-lib-docker /var/lib/docker
```
