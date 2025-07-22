#!/bin/bash

install_amdfixes() {
  if [[ $AMDFIXES -eq 1 ]]; then
    ## Detect AMD EPYC CPU and Apply Fixes
    if [ "$(grep -i -m 1 "model name" /proc/cpuinfo | grep -i "EPYC")" != "" ]; then
      echo "AMD EPYC detected"
      #Apply EPYC fix to kernel : Fixes random crashing and instability
      if ! grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub | grep -q "idle=nomwait"; then
        echo "Setting kernel idle=nomwait"
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="idle=nomwait /g' /etc/default/grub
        update-grub
      fi
    fi
    if [ "$(grep -i -m 1 "model name" /proc/cpuinfo | grep -i "EPYC")" != "" ] || [ "$(grep -i -m 1 "model name" /proc/cpuinfo | grep -i "Ryzen")" != "" ]; then
      ## Add msrs ignore to fix Windows guest on EPIC/Ryzen host
      echo "options kvm ignore_msrs=Y" >>/etc/modprobe.d/kvm.conf
      echo "options kvm report_ignored_msrs=N" >>/etc/modprobe.d/kvm.conf
    fi
  fi
}

install_ksmtuned() {
  if [[ $KSMTUNED -eq 1 ]]; then
    ## Ensure ksmtuned (ksm-control-daemon) is enabled and optimise according to ram size
    RAM_SIZE_GB=$(($(vmstat -s | grep -i "total memory" | xargs | cut -d" " -f 1) / 1024 / 1000))
    /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' install ksm-control-daemon
    if [[ RAM_SIZE_GB -le 16 ]]; then
      # start at 50% full
      KSM_THRES_COEF=50
      KSM_SLEEP_MSEC=80
    elif [[ RAM_SIZE_GB -le 32 ]]; then
      # start at 60% full
      KSM_THRES_COEF=40
      KSM_SLEEP_MSEC=60
    elif [[ RAM_SIZE_GB -le 64 ]]; then
      # start at 70% full
      KSM_THRES_COEF=30
      KSM_SLEEP_MSEC=40
    elif [[ RAM_SIZE_GB -le 128 ]]; then
      # start at 80% full
      KSM_THRES_COEF=20
      KSM_SLEEP_MSEC=20
    else
      # start at 90% full
      KSM_THRES_COEF=10
      KSM_SLEEP_MSEC=10
    fi
    sed -i -e "s/\# KSM_THRES_COEF=.*/KSM_THRES_COEF=${KSM_THRES_COEF}/g" /etc/ksmtuned.conf
    sed -i -e "s/\# KSM_SLEEP_MSEC=.*/KSM_SLEEP_MSEC=${KSM_SLEEP_MSEC}/g" /etc/ksmtuned.conf
    systemctl enable ksmtuned
  fi
}

install_borg() {
  if [[ $BORGON -eq 1 ]]; then
    wget -O - https://raw.githubusercontent.com/avillalba96/borg_config/master/scripts/client-install.sh | sh
  fi
}

install_zabbix_basic() {
  if [[ $ZABBIXON -eq 1 ]]; then
    # Ingresando dato del Zabbix Proxy
    dialog --clear \
      --form "Escribir Zabbix-Proxy:" 25 60 16 \
      "Zabbix-Proxy: " 1 1 "172.24.0.1" 1 32 25 30 >/tmp/out3.tmp \
      2>&1 >/dev/tty

    IPZABBIX=$(sed -n 1p /tmp/out3.tmp)
    rm -f /tmp/out3.tmp

    ZABBIXVERSION="6.0"
    ZABBIXSUBVERSION="3"
    ZABBIX_SO=$(lsb_release -is | sed 's/[A-Z]/\L&/g')
    ZABBIX_SO_ID=$(lsb_release -rs)
    ZABBIXARCHIVE="zabbix-release_$ZABBIXVERSION-$ZABBIXSUBVERSION+$ZABBIX_SO"$ZABBIX_SO_ID"_all.deb"
    ZABBIXURL="https://repo.zabbix.com/zabbix/$ZABBIXVERSION/$ZABBIX_SO/pool/main/z/zabbix-release/$ZABBIXARCHIVE"
    wget "$ZABBIXURL"

    dpkg -i $ZABBIXARCHIVE
    apt-get update
    aptitude install -y zabbix-agent
    sed -i s/ZABBIXIP/"$IPZABBIX"/g zabbix/zabbix_agentd.conf
    sed s/nuevo.host/"$HOST"."$DOMINIO"/g zabbix/zabbix_agentd.conf >/etc/zabbix/zabbix_agentd.conf
    systemctl start zabbix-agent.service
    systemctl enable zabbix-agent.service
  fi
}

install_qemu() {
  if [[ $QEMUON -eq 1 ]]; then
    aptitude install -y qemu-guest-agent
    systemctl enable qemu-guest-agent.service
    systemctl start qemu-guest-agent.service
  fi
}

install_motd() {
  if [[ $MOTDON -eq 0 ]]; then
    cp images/proxmox_logo.png_example images/proxmox_logo.png
    cp systemd/vmbanner-service_example systemd/vmbanner-service
    cp systemd/pvebanner-service_example systemd/pvebanner-service
    cp systemd/pbsbanner-service_example systemd/pbsbanner-service
  fi

  if [[ $PROXMOX_YES -eq 1 ]]; then
    mv /usr/bin/pvebanner /usr/bin/pvebanner.bkp
    chmod -x /usr/bin/pvebanner.bkp
    sed -i s/FECHA_ALTA/"$FECHA"/g systemd/pvebanner-service
    mv systemd/pvebanner-service /usr/bin/pvebanner
    chmod +x /usr/bin/pvebanner
    #chattr +i /usr/bin/pvebanner
    systemctl restart pvebanner.service
    sed -i "s/.data.status.toLowerCase() !==/.data.status.toLowerCase() ==/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js

    if [[ $MOTDON -ne 1 ]]; then
      sed -i "s/www.proxmox.com/www.lunix.com.ar/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
    fi

    cp images/proxmox_logo.png /usr/share/pve-manager/images/.
    systemctl restart pveproxy.service

  elif [[ $PROXMOX_BACKUP_YES -eq 1 ]]; then
    mv /usr/lib/x86_64-linux-gnu/proxmox-backup/proxmox-backup-banner /usr/lib/x86_64-linux-gnu/proxmox-backup/proxmox-backup-banner.bkp
    chmod -x /usr/lib/x86_64-linux-gnu/proxmox-backup/proxmox-backup-banner.bkp
    sed -i s/FECHA_ALTA/"$FECHA"/g systemd/pbsbanner-service
    mv systemd/pbsbanner-service /usr/lib/x86_64-linux-gnu/proxmox-backup/proxmox-backup-banner
    chmod +x /usr/lib/x86_64-linux-gnu/proxmox-backup/proxmox-backup-banner
    #chattr +i /usr/lib/x86_64-linux-gnu/proxmox-backup/proxmox-backup-banner
    systemctl restart proxmox-backup-banner.service
    sed -i "s/.data.status.toLowerCase() !==/.data.status.toLowerCase() ==/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js

    if [[ $MOTDON -ne 1 ]]; then
      sed -i "s/www.proxmox.com/www.lunix.com.ar/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
    fi

    cp images/proxmox_logo.png /usr/share/javascript/proxmox-backup/images/.
    systemctl restart proxmox-backup-proxy.service

  else
    sed -i s/FECHA_ALTA/"$FECHA"/g systemd/vmbanner-service
    mv systemd/vmbanner-service /usr/bin/vmbanner
    chmod +x /usr/bin/vmbanner
    #chattr +i /usr/bin/vmbanner
    cp systemd/vmbanner.service /lib/systemd/system/vmbanner.service
    systemctl start vmbanner.service
    systemctl enable vmbanner.service
    /lib/systemd/system/vmbanner.service
  fi
}

install_client_vpn() {
  if [[ $VPNON -eq 1 ]]; then
    git clone https://github.com/avillalba96/script-altacertificadovpn.git && cd "$(basename "$_" .git)" && ./altaopenvpn
  fi
}

install_docker() {
  # Instalamos docker
  apt-get update
  apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common lsb-release -y

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  apt-get update
  if ! apt-get install docker-ce docker-ce-cli containerd.io -y; then
    ERRORS+="[ERROR] Falló la instalación de Docker.\n"
  fi

  COMPOSEVERSION="2.38.2"
  curl -L "https://github.com/docker/compose/releases/download/v$COMPOSEVERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose

  cp docker/daemon.json /etc/docker/daemon.json

  sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="cdgroup_enable=memory swapaccount=1"/g' /etc/default/grub
  update-grub

  # Chequeo Zabbix
  install_zabbix_docker

  # UWF-DOCKER (https://github.com/chaifeng/ufw-docker)
  wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
  chmod +x /usr/local/bin/ufw-docker

  # Verificar y configurar disco secundario
  if mountpoint -q /u/; then
    echo -e "\e[32m[OK]\e[0m Disco secundario montado en /u/. Configurando carpeta para Docker..."

    mkdir -p /u/var-lib-docker
    systemctl stop docker.socket && systemctl stop docker.service && systemctl stop containerd.service
    rsync -avh --progress /var/lib/docker/ /u/var-lib-docker/.
    rm -r /var/lib/docker && ln -s /u/var-lib-docker /var/lib/docker

  else
    WARNINGS+="[WARNING] No se detecta un disco secundario montado en /u/. Revisar configuración de fstab y formateo.\n"
  fi
}

install_zabbix_docker() {
  if [[ -f /etc/zabbix/zabbix_agentd.conf ]]; then
    cp zabbix/scripts/docker.py /etc/zabbix/
    chmod 755 /etc/zabbix/docker.py
    cp zabbix/zabbix_agentd.d/linux_zabbix_agent.conf /etc/zabbix/zabbix_agentd.d/
    sudo usermod -a -G docker zabbix
  fi
}

generate_user() {
  useradd "$GENERIC_USER" -m -d "/home/$GENERIC_USER" -s /bin/bash
  if [[ $? -eq 0 ]]; then
    echo "$GENERIC_USER:$USER_PASSWORD" | chpasswd
  fi
}

install_ssh() {
  #aptitude install -y geoip-bin geoip-database
  curl -Ls https://github.com/ipinfo/cli/releases/download/ipinfo-3.3.1/deb.sh | sh
  sed -i s/VMLUNIX/"$HOST"/g /etc/ssh/*
  cp hosts/hosts.allow /etc/hosts.allow
  cp hosts/hosts.deny /etc/hosts.deny
  sed -i "s/.*UseDNS\+.*/UseDNS no/" /etc/ssh/sshd_config
  sed -i "s/.*MaxAuthTries\+.*/MaxAuthTries 3/" /etc/ssh/sshd_config
  sed -i "s/.*MaxSessions\+.*/MaxSessions 5/" /etc/ssh/sshd_config
  sed -i "s/.*ClientAliveInterval\+.*/ClientAliveInterval 300/" /etc/ssh/sshd_config
  sed -i "s/.*ClientAliveCountMax\+.*/ClientAliveCountMax 0/" /etc/ssh/sshd_config
  sed -i "s/.*MaxStartups\+.*/MaxStartups 10:30:60/" /etc/ssh/sshd_config
  sed -i "s/.*LoginGraceTime\+.*/LoginGraceTime 2m/" /etc/ssh/sshd_config

  if [[ ($PROXMOX_YES != 1) && ($PROXMOX_BACKUP_YES != 1) ]]; then
    sed -ri 's/^#?PermitRootLogin\s+.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i "s/.*Port \+.*/Port $SSH_PORT/" /etc/ssh/sshd_config
    #sed -i "s/.*PasswordAuthentication\+.*/PasswordAuthentication no/" /etc/ssh/sshd_config
  fi
}

config_raid() {
  OPTIONS00=(1 "Controladora RAID"
    2 "Raid ZFS"
    3 "Ninguna de las anteriores")
  CHOICE00=$(dialog --clear \
    --menu "Seleccione el tipo de RAID: " \
    15 65 7 \
    "${OPTIONS00[@]}" \
    2>&1 >/dev/tty)
  case $CHOICE00 in
  1)
    config_raid_megacli
    ;;
  2)
    config_raid_zfs
    ;;
  3) ;;
  esac
}

config_raid_megacli() {
  clear
  echo ""
  echo -e "\e[0;31m###########################################################\e[0m"
  echo -e "\e[0;31m# NOTA: Este script considera un solo disco, /dev/sda     #\e[0m"
  echo -e "\e[0;31m# De ser necesario editar config_raid_megacli             #\e[0m"
  echo -e "\e[0;31m###########################################################\e[0m"
  echo ""
  sleep 3

  #Agregamos KEY de Megaraid
  wget -O - https://hwraid.le-vert.net/debian/hwraid.le-vert.net.gpg.key | apt-key add -

  #Agregamos repositorio
  cp apt/debian/sources.list.d/megaraid.list /etc/apt/sources.list.d/

  #Instalamos
  aptitude update
  aptitude install -y megaclisas-status

  #Configuramos SMART
  echo "start_smartd=yes" >>/etc/default/smartmontools

  #Configuramos monitoreo de discos
  DISKS=($(megacli -pdlist -a0 | grep 'Device Id' | cut -d " " -f 3))

  #Agregamos discos al monitoreo
  cp smart/megaraid /etc/smartd.conf

  for disk in "${DISKS[@]}"; do
    echo "/dev/sda -d megaraid,$disk -S on -o on -a -I 194 -s (S/../.././01|L/../../7/02) -m $CORREO" >>/etc/smartd.conf
  done

  systemctl restart smartd.service
  systemctl status smartd.service
}

config_raid_zfs() {
  clear
  echo ""
  echo -e "\e[0;31m################################################\e[0m"
  echo -e "\e[0;31m# NOTA: Este script considera un solo rpool    #\e[0m"
  echo -e "\e[0;31m# De ser necesario editar config_raid_zfs      #\e[0m"
  echo -e "\e[0;31m################################################\e[0m"
  echo ""
  sleep 3
  #zpool list | grep "rpool" | wc -l 2>/dev/null

  #Habilitamos alertas por mail
  apt-get install -y zfs-zed
  echo 'ZED_EMAIL_ADDR="root"' >>/etc/zfs/zed.d/zed.rc
  systemctl restart zfs-zed.service

  #Reservamos espacio para la particion ROOT
  zfs set reservation=20G rpool/ROOT

  #Deshabilitamos deduplicacion
  zfs set dedup=off rpool

  #Cambiamos algoritmo de compresion
  zfs set compression=lz4 rpool

  #Deshabilitamos sync writes, mejora mucho la velocidad de escritura e IOPS
  zfs set sync=disabled rpool

  #Cambiamos el tamaño por defecto de blocksize
  pvesm set local-zfs --blocksize 128k

  #Nos aseguramos que genere volumenes thin
  #Queda principalmente de referencia por si se agrega un pool ZFS a mano
  pvesm set local-zfs --sparse 1

  #Reducimos el uso de SWAP
  sysctl -w vm.swappiness=1

  #Persistente
  sed -i "s/.*vm.swappiness\+.*/vm.swappiness = 1/" /etc/sysctl.conf

  #Configuramos la memoria maxima y minima de zfs
  cp zfs/zfs.conf /etc/modprobe.d/zfs.conf
  update-initramfs -u

  ###############################################

  #Instalar y configurar smartmontools

  #Instalamos
  aptitude update
  aptitude install -y smartmontools

  #Configuramos SMART
  echo "start_smartd=yes" >>/etc/default/smartmontools

  #Agregamos discos al monitoreo
  cp smart/smartmontools /etc/smartd.conf
  sed -i "s/EMAILC/$CORREO/g" /etc/smartd.conf

  #Verificar si está habilitado el smart en cada disco
  #smartctl -a /dev/sda | grep "SMART support is: "

  systemctl restart smartd.service
  systemctl status smartd.service

  ###############################################

  # Instalar el chequeo de ZFS en Zabbix
  if [[ -f /etc/zabbix/zabbix_agentd.conf ]]; then
    cp zabbix/zabbix_agentd.d/ZoL_without_sudo.conf /etc/zabbix/zabbix_agentd.d/.
    systemctl restart zabbix-agent.service
  fi

  ###############################################

  # Instalar sanoid para snaps de mv (Esto causa un incremento en IO-Delay)
  if (whiptail --title "" --yesno "Desea instalar SANOID?" 10 60); then
    apt-get install libc6=2.31-13+deb11u4 -y
    apt-get install debhelper libcapture-tiny-perl libconfig-inifiles-perl pv lzop mbuffer build-essential git -y
    git clone https://github.com/jimsalterjrs/sanoid.git
    cd sanoid || exit
    git checkout $(git tag | grep "^v" | tail -n 1)
    ln -s packages/debian .
    dpkg-buildpackage -uc -us
    apt-get install ../sanoid_*_all.deb
    cd ..
    cp sanoidcfg/sanoid.conf_template /etc/sanoid/sanoid.conf

    systemctl enable sanoid.timer
    systemctl start sanoid.timer
  fi
}

install_server_proxmox_backup_server() {
  # Instalacion y actualizacion de paquetes
  cp apt/debian/sources.list.d/pbs-enterprise.list /etc/apt/sources.list.d/
  cp apt/debian/sources.list.d/pbs-no-subscription.list /etc/apt/sources.list.d/
  aptitude install -y pigz ifupdown2

  # Configuramos fail2ban
  cp fail2ban/filter.d/proxmoxbackupserver.conf /etc/fail2ban/filter.d/
  cp fail2ban/jail.d/proxmoxbackupserver.conf /etc/fail2ban/jail.d/
  cp fail2ban/jail.local /etc/fail2ban/
  systemctl reload fail2ban.service
}

install_server_proxmox() {
  # Select package
  cmd=(dialog --separate-output --checklist "Seleccionar paquetes a instalar:" 22 76 16)
  Opcions=(1 "Proxmox - AMDFIXES" off
    2 "Proxmox - KSMTUNED" off)
  choices=$("${cmd[@]}" "${Opcions[@]}" 2>&1 >/dev/tty)
  clear
  for choice in $choices; do
    case $choice in
    1)
      AMDFIXES=1
      ;;
    2)
      KSMTUNED=1
      ;;
    esac
  done

  # Instalacion y actualizacion de paquetes
  cp apt/debian/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/
  cp apt/debian/sources.list.d/pve-no-subscription.list /etc/apt/sources.list.d/
  aptitude install -y pigz ifupdown2

  # Configuramos fail2ban
  cp fail2ban/filter.d/proxmox.conf /etc/fail2ban/filter.d/
  cp fail2ban/jail.d/proxmox.conf /etc/fail2ban/jail.d/
  cp fail2ban/jail.local /etc/fail2ban/
  systemctl reload fail2ban.service

  # Habilitamos compresion con pigz para gzip
  echo "pigz: 1" >>/etc/vzdump.conf

  # Copiamos script de PVE
  cp scripts/proxmox/* /usr/local/sbin/
  chmod 755 /usr/local/sbin/*
}

install_vm() {
  # Select package
  cmd=(dialog --separate-output --checklist "Seleccionar paquetes a instalar:" 22 76 16)
  Opcions=(1 "Client - QEMU (Proxmox)" off)
  choices=$("${cmd[@]}" "${Opcions[@]}" 2>&1 >/dev/tty)
  clear
  for choice in $choices; do
    case $choice in
    1)
      QEMUON=1
      ;;
    esac
  done

  # Docker para Ubuntu
  INSTALLDOCKER=$(lsb_release -is | grep -ci "ubuntu" 2>/dev/null)
  if [[ $INSTALLDOCKER -eq 1 ]]; then
    if (whiptail --title "" --yesno "Desea instalar DOCKER?" 10 60); then
      install_docker
    fi
  fi
}

finish_script() {
  sysctl --system
  apt-get autoremove && apt-get autoclean

  cd "$DIRALTA" || return
  cd ..
  cd ..
  rm -rf alta* && rm -rf script-altahost* && rm -rf .wget-hsts

  clear
  echo ""
  echo -e "\e[1;32m++++++++++++++++++++++++++++++++++++++++++++++++\e[0m"

  if [[ -n "$ERRORS" ]]; then
    echo -e "\e[0;31mSe detectaron los siguientes errores durante la ejecución:\e[0m"
    echo -e "$ERRORS"
    echo ""
  fi

  if [[ -n "$WARNINGS" ]]; then
    echo -e "\e[1;33mSe detectaron las siguientes advertencias:\e[0m"
    echo -e "$WARNINGS"
    echo ""
  fi

  echo -e "\e[0mFelicitaciones, el proceso ha finalizado\e[0m"
  echo ""
  echo -e "\e[0;31mHOST: \e[1;33m$HOST.$DOMINIO\e[0m"
  echo ""
  echo -e "\e[0;31mRECORDATORIO: \e[0mAgregar equipo al sistema de backups \e[0m"
  echo -e "\e[0m[\e[1;31mBORG \e[0;0m/ \e[1;33mPROXMOX \e[0;0m/ \e[1;33mPBS \e[0;0m/ \e[1;32mVEEAM\e[0m]"
  echo ""
  echo -e "\e[0;31mIMPORTANTE: \e[0mPor favor, reiniciar este equipo\e[0m"
  echo -e "\e[1;32m++++++++++++++++++++++++++++++++++++++++++++++++\e[0m"
  echo ""

  exit
}

init_script() {
  # Definimos carpeta del script sin importa de donde se llame
  DIRALTA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  FECHA="$(date -I)"

  # Actualizamos los apt para la version de debian correspondiente
  NAMEHOST=$(lsb_release -ds)
  VERSIONSO=$(lsb_release -cs)
  grep -rl SO_VERSION apt/. | xargs sed -i "s/SO_VERSION/${VERSIONSO}/g" 2>/dev/null

  # Ingresando datos del equipo
  HOST=$(hostname)
  dialog --clear \
    --form "Completar datos del equipo cliente:" 25 60 16 \
    "Dominio del equipo: " 1 1 "dominio.com" 1 32 25 30 \
    "Usuario generico: " 2 1 "lunix" 2 32 25 30 \
    "Puerto SSH: " 3 1 "23242" 3 32 25 30 \
    "Envio de email: " 4 1 "ing@example.com.ar" 4 32 25 30 \
    "Relayhost (Postfix): " 5 1 "172.26.0.1" 5 32 25 30 \
    --insecure --passwordbox "Contrasena del usuario:" 6 50 >/tmp/out.tmp \
    2>&1 >/dev/tty

  cp /tmp/out.tmp /var/log/out.tmp #TEMPORAL
  tr -d " \t" </tmp/out.tmp >/tmp/out2.tmp
  grep "\S" /tmp/out2.tmp >/tmp/out.tmp

  DOMINIO=$(sed -n 1p /tmp/out.tmp)
  GENERIC_USER=$(sed -n 2p /tmp/out.tmp)
  SSH_PORT=$(sed -n 3p /tmp/out.tmp)
  CORREO=$(sed -n 4p /tmp/out.tmp)
  IPCORREO=$(sed -n 5p /tmp/out.tmp)
  USER_PASSWORD=$(sed -n 6p /tmp/out.tmp)
  rm -f /tmp/out.tmp /tmp/out2.tmp

  # Intentamos obtener la IP principal
  IP=$(ip a | grep inet | grep -v inet6 | grep -v 127.0.0.1 | head -n1 | awk -F'[/ ]+' '{print $3}')

  # Cambiamos hostname antes de instalar paquetes
  PROXMOX_YES=$(pveversion 2>/dev/null | wc -l)
  PROXMOX_BACKUP_YES=$(proxmox-backup-manager versions 2>/dev/null | wc -l)
  echo "$HOST" >/etc/hostname
  hostname -F /etc/hostname
  sed -i s/HOST/"$HOST"/g hosts/hosts_*
  sed -i s/DOMINIO/"$DOMINIO"/g hosts/hosts_*
  if [[ $PROXMOX_YES -eq 1 ]]; then
    sed s/IP/"$IP"/g hosts/hosts_proxmox >/etc/hosts
  elif [[ $PROXMOX_BACKUP_YES -eq 1 ]]; then
    sed s/IP/"$IP"/g hosts/hosts_pbs >/etc/hosts
  else
    sed s/IP/"$IP"/g hosts/hosts_local >/etc/hosts
  fi

  # Instalacion y actualizacion de paquetes
  APTINSTALL=$(echo "$NAMEHOST" | grep -ci debian 2>/dev/null)
  if [[ $APTINSTALL -eq 1 ]]; then
    cp apt/debian/sources.list /etc/apt/
    cp apt/debian/sources.list.d/security.list /etc/apt/sources.list.d/
  else
    cp apt/ubuntu/sources.list /etc/apt/sources.list
  fi
  rm -f /etc/apt/sources.list.d/ubuntu.sources
  apt-get update
  apt-get -y install aptitude gnupg2 gnupg
  aptitude update
  aptitude dist-upgrade -y
  aptitude install -y git vim-syntax-gtk screen htop acpid dirmngr apt-transport-https locales-all iptables

  # Copiamos scripts
  cp scripts/all/* /usr/local/sbin/
  chmod 755 /usr/local/sbin/*

  # Habilitamos cliente NTP
  rm /etc/localtime
  ln -s /usr/share/zoneinfo/America/Buenos_Aires /etc/localtime
  cp systemd/timesyncd.conf /etc/systemd/timesyncd.conf
  timedatectl set-ntp true
  systemctl restart systemd-timesyncd.service

  # Personalizacion
  cp vim/vimrc /root/.vimrc
  update-alternatives --set editor /usr/bin/vim.basic
  cp bash/bashrc /root/.bashrc

  # Utilizamos rsyslog para fail2ban
  aptitude install -y fail2ban
  sed '/logtarget =/c\logtarget = SYSLOG' -i /etc/fail2ban/fail2ban.conf
  sed -i "s/destemail = root@localhost/destemail = $CORREO/g" /etc/fail2ban/jail.conf
  sed -i "s/sender = root@<fq-hostname>/sender = root@$HOST.$DOMINIO/g" /etc/fail2ban/jail.conf
  #  sed -i "s/action = %(action_)s/action = %(action_mw)s/g" /etc/fail2ban/jail.conf
  systemctl reload fail2ban.service

  # Configuramos Postfix
  aptitude install -y postfix mailutils
  cp others/aliases /etc/aliases
  sed -i "s/EMAILC/$CORREO/g" /etc/aliases
  postconf -e "relayhost = $IPCORREO"
  systemctl restart postfix.service
  newaliases

  # Configuramos Cron
  cat crontab/modelo_crontab >>/var/spool/cron/crontabs/root
  chmod 600 /var/spool/cron/crontabs/root
  systemctl restart cron.service

  # Reducimos el uso de SWAP
  sysctl -w vm.swappiness=10
  echo "vm.swappiness = 10" >>/etc/sysctl.conf
}

select_package_init() {
  # Select package
  cmd=(dialog --separate-output --checklist "Seleccionar paquetes a instalar:" 22 76 16)
  Opcions=(1 "Client - VPN (pfSense)" off
    2 "Client - ZABBIX (6.0)" off
    3 "Client - BORG (Lunix SRL)" off
    4 "Client - BANNER (Lunix SRL)" off)
  choices=$("${cmd[@]}" "${Opcions[@]}" 2>&1 >/dev/tty)
  clear
  for choice in $choices; do
    case $choice in
    1)
      VPNON=1
      ;;
    2)
      ZABBIXON=1
      ;;
    3)
      BORGON=1
      ;;
    4)
      MOTDON=1
      ;;
    esac
  done
}

start_install() {
  select_package_init
  init_script
  install_zabbix_basic
  if [[ $PROXMOX_YES -eq 1 ]]; then
    generate_user
    install_server_proxmox
    config_raid
    install_amdfixes
    install_ksmtuned
  elif [[ $PROXMOX_BACKUP_YES -eq 1 ]]; then
    generate_user
    install_server_proxmox_backup_server
    config_raid
  else
    install_vm
    install_qemu
  fi
  install_motd
  install_ssh
  install_borg
  install_client_vpn
  finish_script
}

prepare_system() {
  # Generamos flag de instalacion
  mkdir /etc/lunix 2>/dev/null
  echo "1" >/etc/lunix/alta_script

  # Deshabilitamos IPV6
  echo -e "Acquire::ForceIPv4 \"true\";\\n" >/etc/apt/apt.conf.d/99-force-ipv4
  sed -i '$a net.ipv6.conf.all.disable_ipv6 = 1' /etc/sysctl.conf
  sed -i '$a net.ipv6.conf.default.disable_ipv6 = 1' /etc/sysctl.conf
  sed -i '$a net.ipv6.conf.lo.disable_ipv6 = 1' /etc/sysctl.conf
  sysctl --system

  # Instalamos el paquete necesario para tener el menu de instalacion
  apt-get update && apt-get upgrade -y
  apt-get install -y dialog wget curl lsb-release

  if (whiptail --title "" --yesno "Verificar tener salida irrestricta a Internet. Presione YES para continuar." 10 60); then
    DEBIANVERSION_YES=$(lsb_release -is | grep -ci "debian")
    UBUNTUVERSION_YES=$(lsb_release -is | grep -ci "ubuntu")

    if [[ ("$DEBIANVERSION_YES" == 0) && ("$UBUNTUVERSION_YES" == 0) ]]; then
      rm /etc/lunix/alta_script
      clear
      echo -e "\e[0;31m[ERROR]: \e[0mNo se detecto SO compatible para este script\e[0m"
      exit
    else
      start_install
    fi
  else
    rm /etc/lunix/alta_script
    clear
    echo -e "\e[0;31m[ERRO]: \e[0mSe cancelo la instalacion de SCRIPT ALTA\e[0m"
    exit
  fi
}

main() {
  WHO=$(whoami)
  if [[ ($WHO != root) ]]; then
    echo -e "\e[0;31m[ERROR]: \e[0mSe requiere estar con el usuario \e[1;32m'root'\e[0m"
    exit
  else
    # Seteando variables
    VPNON=0
    ZABBIXON=0
    BORGON=0
    QEMUON=0
    AMDFIXES=0
    KSMTUNED=0
    MOTDON=0

    # Iniciando instalacion
    clear
    mkdir /var/log/lunix/
    if [[ -f /etc/lunix/alta_script ]]; then
      echo -e "\e[0;31m[ERROR]: \e[0mEl equipo ya se encuentra dado de alta\e[0m"
      exit
    fi
    ( (
      prepare_system
    ) 2>&1) | tee /var/log/lunix/alta_lunix.log
  fi
}

main
