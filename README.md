# **script-altahost**

Script para dar alta a UBUNTU/DEBIAN/PVE/PBS en base a necesidad de Lunix SRL

***Verificado en: Debian9+ / Ubuntu18+ / PVE6+***

## **Instalación** 🔧

```bash
apt-get update; apt-get install -y git
git clone https://github.com/avillalba96/script-altahost && cd "$(basename "$_" .git)" && cd install && ./alta.lunixstart.sh
```

### **Autores** ✒️

* **Maxi** - [Maximiliano Baez](https://github.com/MaximilianoBz)
* **Franco** - [Franco Grismado](https://github.com/fgrismado)
* **Pablop** - [Pablo Ramos](https://github.com/avillalba96)
* **Alejandro** - [Alejandro Villalba](https://github.com/avillalba96)

### **Cosas por hacer** 📦

0. **NO ESTA VERIFICADO:** PBS / aliases(envio de correo)
1. Generar para docker la carpeta en /u/var-lib/docker (revisar como solucionar al no tener el disco secundario montado)

```bash
rm -r /var/lib/docker
mkdir -p /u/var-lib-docker
ln -s /u/var-lib-docker /var/lib/docker
```
