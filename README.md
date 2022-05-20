# **script-altahost**

Script para dar alta hosts armado en nuestra necesidades

***Verificado en: Debian9+ / Ubuntu18+***

## **Instalación** 🔧

```bash
git clone https://github.com/avillalba96/script-altacertificadovpn.git && cd "$(basename "$_" .git)" && cd install && ./alta.lunixstart.sh
```

### **Autores** ✒️

* **Pablo Ramos** - *Trabajo Inicial* - [Pablo Ramos](https://git.lunix.com.ar/pramos)
* **Maximiliano Baez** - *Colaboracion* - [Maximiliano Baez](https://github.com/MaximilianoBz)
* **Alejandro Villalba** - *Colaboracion* - [Alejandro Villalba](https://github.com/avillalba96)

### **Cosas por hacer** 📦

0. **NO ESTA VERIFICADO:** PBS / aliases(envio de correo)
1. Generar para docker la carpeta en /u/var-lib/docker (revisar como solucionar al no tener el disco secundario montado)

```bash
rm -r /var/lib/docker
mkdir -p /u/var-lib-docker
ln -s /u/var-lib-docker /var/lib/docker
```
