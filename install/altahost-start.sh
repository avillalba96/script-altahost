#!/bin/bash
#
# script-altahost: provisioning and initial configuration for Debian/Ubuntu/PVE/PBS.
# Compatible with versions under active or extended support.
#

# ---------- Versions (adjust here for latest stable releases) ----------
ZABBIX_VERSION="7.4"
ZABBIX_RELEASE_REV="1"
IPINFO_VERSION="3.3.1"
# Docker: uses docker-compose-plugin (apt), no fixed version.
# -------------------------------------------------------------------------

# Default support account name (overridden by the install form).
# If that user already exists (e.g. Ubuntu installer user), it is reused and only updated.
SUPPORT_USER="support"
# Default SSH geo-allowlist; prompted again during install (ISO codes, e.g. US,DE,AR).
SSH_ALLOW_COUNTRIES="AR"

# Progress / resume helpers (survive cancel, SSH drop, or script crash)
ALTA_DIR="/etc/altahost"
ALTA_LOG_DIR="/var/log/altahost"
CURRENT_STEP=""
LAST_OK_STEP=""
ALTA_FINISHED=0

progress_log() {
  mkdir -p "$ALTA_LOG_DIR" "$ALTA_DIR"
  chmod 700 "$ALTA_LOG_DIR" 2>/dev/null || true
  # Only step/status metadata — never passwords or key material
  echo "$(date -Is) $*" >>"$ALTA_LOG_DIR/progress.log"
  chmod 600 "$ALTA_LOG_DIR/progress.log" 2>/dev/null || true
}

write_last_step() {
  mkdir -p "$ALTA_LOG_DIR"
  {
    echo "updated=$(date -Is)"
    echo "status=$(cat "$ALTA_DIR/status" 2>/dev/null || echo unknown)"
    echo "current_step=${CURRENT_STEP:-none}"
    echo "last_ok_step=${LAST_OK_STEP:-none}"
    echo "progress_log=${ALTA_LOG_DIR}/progress.log"
    echo "full_log=${ALTA_LOG_DIR}/alta_altahost.log"
  } >"$ALTA_LOG_DIR/last_step"
  chmod 600 "$ALTA_LOG_DIR/last_step" 2>/dev/null || true
}

write_resume_help() {
  local reason="$1"
  mkdir -p "$ALTA_LOG_DIR"
  cat >"$ALTA_LOG_DIR/HOW_TO_RESUME.txt" <<EOF
script-altahost did not finish cleanly.
reason=${reason}
current_step=${CURRENT_STEP:-none}
last_ok_step=${LAST_OK_STEP:-none}
updated=$(date -Is)

What to do next:
1. Re-run:  cd <cloned-repo>/install && ./altahost-start.sh
2. Choose YES when asked to retry an incomplete install.
3. Read last_ok_step above — that is the last phase that finished.
4. Full console log: ${ALTA_LOG_DIR}/alta_altahost.log
5. Step timeline:    ${ALTA_LOG_DIR}/progress.log

Note: a retry restarts the installer from the beginning; steps are written to be idempotent
(safe to repeat: no duplicate cron/sysctl/vzdump lines, banners use a single .bkp, users are reused).
Use last_ok_step / progress.log to see how far it got and what to double-check.

Privacy: these resume/progress files must not contain passwords or SSH private/public key material.
EOF
  chmod 600 "$ALTA_LOG_DIR/HOW_TO_RESUME.txt" 2>/dev/null || true
}

alta_mark_in_progress() {
  mkdir -p "$ALTA_DIR" "$ALTA_LOG_DIR"
  echo "in_progress" >"$ALTA_DIR/status"
  echo "in_progress" >"$ALTA_DIR/alta_script"
  progress_log "STATUS in_progress"
  write_last_step
}

alta_mark_completed() {
  ALTA_FINISHED=1
  mkdir -p "$ALTA_DIR" "$ALTA_LOG_DIR"
  echo "completed" >"$ALTA_DIR/status"
  echo "completed" >"$ALTA_DIR/alta_script"
  CURRENT_STEP="finished"
  progress_log "STATUS completed last_ok=${LAST_OK_STEP:-finish_script}"
  write_last_step
  rm -f "$ALTA_LOG_DIR/HOW_TO_RESUME.txt"
  sanitize_alta_logs
}

alta_mark_interrupted() {
  local reason="${1:-interrupted}"
  [[ "${ALTA_FINISHED:-0}" -eq 1 ]] && return 0
  mkdir -p "$ALTA_DIR" "$ALTA_LOG_DIR"
  echo "interrupted" >"$ALTA_DIR/status"
  echo "interrupted" >"$ALTA_DIR/alta_script"
  progress_log "STATUS ${reason} current=${CURRENT_STEP:-none} last_ok=${LAST_OK_STEP:-none}"
  write_last_step
  write_resume_help "$reason"
  sanitize_alta_logs
}

install_abort() {
  alta_mark_interrupted "${1:-user_abort}"
  clear
  echo -e "\e[0;31m[ABORTED]\e[0m ${1:-user_abort}"
  echo -e "See \e[1;33m${ALTA_LOG_DIR}/HOW_TO_RESUME.txt\e[0m and \e[1;33m${ALTA_LOG_DIR}/last_step\e[0m"
  exit 1
}

step_start() {
  CURRENT_STEP="$1"
  progress_log "START $1"
  write_last_step
  echo -e "\e[1;34m[STEP]\e[0m starting: $1"
}

step_ok() {
  LAST_OK_STEP="$1"
  progress_log "OK $1"
  CURRENT_STEP=""
  write_last_step
  echo -e "\e[1;32m[STEP]\e[0m done: $1"
}

run_step() {
  local name="$1"
  shift
  step_start "$name"
  "$@"
  step_ok "$name"
}

# Read previous run status (supports legacy alta_script=1 as completed)
alta_previous_status() {
  if [[ -f "$ALTA_DIR/status" ]]; then
    cat "$ALTA_DIR/status"
    return 0
  fi
  if [[ -f "$ALTA_DIR/alta_script" ]]; then
    local legacy
    legacy=$(tr -d ' \t\r\n' <"$ALTA_DIR/alta_script")
    case "$legacy" in
    completed | interrupted | in_progress) echo "$legacy" ;;
    1) echo "completed" ;; # old flag meant "already run"
    *) echo "completed" ;;
    esac
    return 0
  fi
  echo "none"
}

# ---------- Idempotent helpers (safe re-run) ----------
ensure_line_in_file() {
  local file="$1"
  local line="$2"
  mkdir -p "$(dirname "$file")" 2>/dev/null || true
  touch "$file"
  grep -qxF "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >>"$file"
}

ensure_sysctl_kv() {
  local key="$1"
  local value="$2"
  local file="${3:-/etc/sysctl.conf}"
  touch "$file"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null; then
    sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$file"
  else
    printf '%s = %s\n' "$key" "$value" >>"$file"
  fi
}

install_file_with_backup() {
  # Copy src -> dest; keep one .bkp of the original dest if missing
  local src="$1"
  local dest="$2"
  local bkp="${dest}.bkp"
  [[ -f "$src" ]] || return 1
  if [[ -e "$dest" && ! -e "$bkp" ]]; then
    cp -a "$dest" "$bkp"
    chmod -x "$bkp" 2>/dev/null || true
  fi
  cp -f "$src" "$dest"
  chmod +x "$dest" 2>/dev/null || true
}

# Redact secrets from persistent logs (passwords / pubkey material never stored on purpose;
# this is a safety net for accidental echo/tee leakage).
sanitize_alta_logs() {
  mkdir -p "$ALTA_LOG_DIR"
  local f
  for f in alta_altahost.log progress.log last_step HOW_TO_RESUME.txt alta_summary.txt; do
    [[ -f "$ALTA_LOG_DIR/$f" ]] || continue
    # OpenSSH public key material
    sed -i -E 's/(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)[[:space:]]+[^[:space:]]+/\1 [REDACTED]/g' "$ALTA_LOG_DIR/$f" 2>/dev/null || true
    # Common password assignments / chpasswd leftovers
    sed -i -E \
      -e 's/(USER_PASSWORD|PASSWORD|password)[[:space:]]*[:=][[:space:]]*[^[:space:]]+/\1=[REDACTED]/gI' \
      -e 's/^[^:]+:[^[:space:]]+$/[REDACTED_CHPASSWD_LINE]/' \
      "$ALTA_LOG_DIR/$f" 2>/dev/null || true
    chmod 600 "$ALTA_LOG_DIR/$f" 2>/dev/null || true
  done
  chmod 700 "$ALTA_LOG_DIR" 2>/dev/null || true
}

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
      mkdir -p /etc/modprobe.d
      ensure_line_in_file /etc/modprobe.d/kvm.conf "options kvm ignore_msrs=Y"
      ensure_line_in_file /etc/modprobe.d/kvm.conf "options kvm report_ignored_msrs=N"
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
    # Download to a file and run (avoids piping directly to shell)
    local borg_script
    borg_script=$(mktemp /tmp/borg-install.XXXXXX)
    if wget -q -O "$borg_script" https://raw.githubusercontent.com/avillalba96/borg_config/master/scripts/client-install.sh; then
      chmod +x "$borg_script"
      bash "$borg_script"
    else
      ERRORS+="[ERROR] Could not download the Borg installer.\n"
    fi
    rm -f "$borg_script"
  fi
}

install_zabbix_basic() {
  if [[ $ZABBIXON -eq 1 ]]; then
    # Prompt for Zabbix Proxy
    local zbx_tmp
    zbx_tmp=$(mktemp /tmp/altahost-zabbix.XXXXXX)
    chmod 600 "$zbx_tmp"
    dialog --clear \
      --form "Enter Zabbix-Proxy:" 25 60 16 \
      "Zabbix-Proxy: " 1 1 "172.24.0.1" 1 32 25 30 >"$zbx_tmp" \
      2>&1 >/dev/tty

    IPZABBIX=$(sed -n 1p "$zbx_tmp")
    rm -f "$zbx_tmp"

    ZABBIX_SO=$(lsb_release -is | sed 's/[A-Z]/\L&/g')
    ZABBIX_SO_ID=$(lsb_release -rs)
    # Zabbix 7.x uses /release/ in the URL path
    if [[ "${ZABBIX_VERSION%%.*}" -ge 7 ]]; then
      ZABBIXARCHIVE="zabbix-release_${ZABBIX_VERSION}-${ZABBIX_RELEASE_REV}+${ZABBIX_SO}${ZABBIX_SO_ID}_all.deb"
      ZABBIXURL="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/${ZABBIX_SO}/pool/main/z/zabbix-release/${ZABBIXARCHIVE}"
    else
      ZABBIXARCHIVE="zabbix-release_${ZABBIX_VERSION}-${ZABBIX_RELEASE_REV}+${ZABBIX_SO}${ZABBIX_SO_ID}_all.deb"
      ZABBIXURL="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/${ZABBIX_SO}/pool/main/z/zabbix-release/${ZABBIXARCHIVE}"
    fi
    wget -q "$ZABBIXURL" -O "$ZABBIXARCHIVE" || wget "$ZABBIXURL" -O "$ZABBIXARCHIVE"

    dpkg -i "$ZABBIXARCHIVE"
    apt-get update
    aptitude install -y zabbix-agent
    sed -i s/ZABBIXIP/"$IPZABBIX"/g "$DIRALTA/zabbix/zabbix_agentd.conf"
    sed s/nuevo.host/"$HOST"."$DOMINIO"/g "$DIRALTA/zabbix/zabbix_agentd.conf" >/etc/zabbix/zabbix_agentd.conf
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
  if [[ $PROXMOX_YES -eq 1 ]]; then
    install_file_with_backup "$DIRALTA/systemd/pvebanner-service_custom" /usr/bin/pvebanner
    systemctl restart pvebanner.service
    # Subscription nag bypass (idempotent replace)
    if [[ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]]; then
      sed -i "s/.data.status.toLowerCase() !==/.data.status.toLowerCase() ==/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
    fi
    install_proxmox_logo
    systemctl restart pveproxy.service

  elif [[ $PROXMOX_BACKUP_YES -eq 1 ]]; then
    install_file_with_backup "$DIRALTA/systemd/pbsbanner-service_custom" /usr/lib/x86_64-linux-gnu/proxmox-backup/proxmox-backup-banner
    systemctl restart proxmox-backup-banner.service
    if [[ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]]; then
      sed -i "s/.data.status.toLowerCase() !==/.data.status.toLowerCase() ==/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
    fi
    install_proxmox_logo
    systemctl restart proxmox-backup-proxy.service

  else
    install_file_with_backup "$DIRALTA/systemd/vmbanner-service_custom" /usr/bin/vmbanner
    cp "$DIRALTA/systemd/vmbanner.service" /lib/systemd/system/vmbanner.service
    systemctl daemon-reload
    systemctl enable vmbanner.service
    systemctl restart vmbanner.service
  fi
}

install_client_vpn() {
  if [[ $VPNON -eq 1 ]]; then
    local vpn_dir
    vpn_dir="$DIRALTA/../script-altacertificadovpn"
    if [[ ! -d "$vpn_dir/.git" ]]; then
      git clone https://github.com/avillalba96/script-altacertificadovpn.git "$vpn_dir"
    fi
    (cd "$vpn_dir" && ./altaopenvpn)
  fi
}

install_docker() {
  # Install Docker
  apt-get update
  apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common lsb-release -y

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  apt-get update
  if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
    ERRORS+="[ERROR] Docker installation failed.\n"
  fi
  # docker compose (v2) as a plugin; use: docker compose (no hyphen)

  cp "$DIRALTA/docker/daemon.json" /etc/docker/daemon.json

  sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="cdgroup_enable=memory swapaccount=1"/g' /etc/default/grub
  update-grub

  # Zabbix check
  install_zabbix_docker

  # UFW-DOCKER (https://github.com/chaifeng/ufw-docker)
  wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
  chmod +x /usr/local/bin/ufw-docker

  # Check and configure secondary disk (idempotent: only migrate once)
  if mountpoint -q /u/; then
    echo -e "\e[32m[OK]\e[0m Secondary disk mounted at /u/. Configuring Docker data directory..."

    mkdir -p /u/var-lib-docker
    if [[ ! -L /var/lib/docker ]]; then
      systemctl stop docker.socket 2>/dev/null || true
      systemctl stop docker.service 2>/dev/null || true
      systemctl stop containerd.service 2>/dev/null || true
      if [[ -d /var/lib/docker ]]; then
        rsync -avh --progress /var/lib/docker/ /u/var-lib-docker/.
        rm -rf /var/lib/docker
      fi
      ln -sfn /u/var-lib-docker /var/lib/docker
      systemctl start containerd.service 2>/dev/null || true
      systemctl start docker.service 2>/dev/null || true
    fi

  else
    WARNINGS+="[WARNING] No secondary disk mounted at /u/. Check fstab and disk formatting.\n"
  fi
}

install_zabbix_docker() {
  if [[ -f /etc/zabbix/zabbix_agentd.conf ]] && [[ -n "$DIRALTA" ]]; then
    cp "$DIRALTA/zabbix/scripts/docker.py" /etc/zabbix/
    chmod 755 /etc/zabbix/docker.py
    cp "$DIRALTA/zabbix/zabbix_agentd.d/linux_zabbix_agent.conf" /etc/zabbix/zabbix_agentd.d/
    usermod -a -G docker zabbix 2>/dev/null || true
  fi
}

# Install authorized_keys for a user (if a pubkey was provided)
setup_user_ssh_key() {
  local user="$1"
  [[ -z "$SSH_PUBKEY" ]] && return 0
  id -u "$user" >/dev/null 2>&1 || return 0

  local home_dir
  home_dir=$(getent passwd "$user" | cut -d: -f6)
  [[ -z "$home_dir" || ! -d "$home_dir" ]] && return 0

  mkdir -p "$home_dir/.ssh"
  chmod 700 "$home_dir/.ssh"
  touch "$home_dir/.ssh/authorized_keys"
  chmod 600 "$home_dir/.ssh/authorized_keys"
  if ! grep -qxF "$SSH_PUBKEY" "$home_dir/.ssh/authorized_keys" 2>/dev/null; then
    echo "$SSH_PUBKEY" >>"$home_dir/.ssh/authorized_keys"
  fi
  chown -R "$user:$user" "$home_dir/.ssh"
}

# Validate OpenSSH public key: non-empty, known type prefix, and parseable by ssh-keygen when available
validate_ssh_pubkey() {
  local key="$1"
  local tmp

  [[ -z "$key" ]] && return 1
  [[ "$key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)[[:space:]]+[^[:space:]]+ ]] || return 1

  # Structural check with ssh-keygen (catches truncated/corrupt base64)
  if command -v ssh-keygen >/dev/null 2>&1; then
    tmp=$(mktemp /tmp/altahost-pubkey.XXXXXX)
    printf '%s\n' "$key" >"$tmp"
    if ! ssh-keygen -l -f "$tmp" >/dev/null 2>&1; then
      rm -f "$tmp"
      return 1
    fi
    rm -f "$tmp"
  fi
  return 0
}

# Prompt for public key: paste the full content of the .pub file
prompt_ssh_pubkey() {
  local pubkey_raw
  pubkey_raw=$(whiptail --title "SSH key (${SUPPORT_USER})" --inputbox "Paste the full SSH public key (content of the .pub file, one line):\n\ne.g. ssh-ed25519 AAAAC3Nza... user@host" 12 78 "" 3>&1 1>&2 2>&3) || return 1
  pubkey_raw=$(echo "$pubkey_raw" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [[ -z "$pubkey_raw" ]]; then
    whiptail --msgbox "Public key is empty. Paste the full line of the .pub file." 9 70
    return 1
  fi
  if ! validate_ssh_pubkey "$pubkey_raw"; then
    whiptail --msgbox "Invalid or corrupt public key.\nMust be one OpenSSH line (ssh-ed25519 / ssh-rsa / ecdsa-...) and pass ssh-keygen -l." 10 72
    return 1
  fi
  SSH_PUBKEY="$pubkey_raw"
  return 0
}

# SSH options: on VMs password auth in sshd can be disabled.
# On PVE/PBS sshd is left untouched; a key can still be loaded for SUPPORT_USER.
configure_ssh_auth_options() {
  SSH_ALLOW_PASSWORD=1
  SSH_PUBKEY=""

  if [[ $PROXMOX_YES -eq 1 || $PROXMOX_BACKUP_YES -eq 1 ]]; then
    # Hypervisor: official sshd defaults; optional pubkey only for SUPPORT_USER
    if (whiptail --title "SSH key (${SUPPORT_USER})" --yesno "Add an SSH public key for user ${SUPPORT_USER}?\n\n(PVE/PBS sshd is not modified)" 11 70); then
      prompt_ssh_pubkey_until_valid || true
    fi
    return 0
  fi

  # Never aborts: without a valid key it falls back to Ubuntu defaults (password login, no root over SSH)
  if (whiptail --title "SSH authentication" --yesno "Allow SSH login with password for ${SUPPORT_USER}?\n\nYES = password (and optionally a key)\nNO  = public key only (if no key is loaded, password login is kept)\n\nroot can never log in over SSH (use sudo)." 15 74); then
    SSH_ALLOW_PASSWORD=1
    if (whiptail --title "SSH key" --yesno "Also add an SSH public key for ${SUPPORT_USER}?" 10 60); then
      prompt_ssh_pubkey_until_valid || true
    fi
  else
    SSH_ALLOW_PASSWORD=0
    if ! prompt_ssh_pubkey_until_valid; then
      SSH_ALLOW_PASSWORD=1
      whiptail --title "SSH authentication" --msgbox "No SSH key loaded: password login is kept for ${SUPPORT_USER} (Ubuntu default).\nroot still cannot log in over SSH." 10 74
      WARNINGS+="[WARN] No SSH key for ${SUPPORT_USER}: SSH password login kept enabled.\n"
    fi
  fi

  if [[ $SSH_ALLOW_PASSWORD -eq 1 && -z "$USER_PASSWORD" ]] && ! support_user_has_password; then
    whiptail --msgbox "${SUPPORT_USER} has no usable password yet.\nSet one now to be able to log in over SSH (empty = continue without it)." 10 74
    prompt_support_password || true
    if [[ -z "$USER_PASSWORD" && -z "$SSH_PUBKEY" ]]; then
      WARNINGS+="[WARN] ${SUPPORT_USER} has no password and no SSH key: SSH login will not work for that user.\n"
    fi
  fi
}

# Ask for the key until it is valid; returns 1 only if the user declines to retry
prompt_ssh_pubkey_until_valid() {
  while ! prompt_ssh_pubkey; do
    if ! (whiptail --title "SSH key" --yesno "No valid public key loaded.\n\nRetry?\n\nYES = paste it again\nNO  = continue without a key" 13 60); then
      return 1
    fi
  done
  return 0
}

# True if SUPPORT_USER exists and has a usable (not locked/empty) password
support_user_has_password() {
  [[ "$(passwd -S "$SUPPORT_USER" 2>/dev/null | awk '{print $2}')" == "P" ]]
}

# Ask the SUPPORT_USER password twice. Empty = keep current (existing user) or locked (new user).
# Returns 1 on cancel. Kept only in memory, never written to disk.
prompt_support_password() {
  local hint pass1 pass2
  if id -u "$SUPPORT_USER" >/dev/null 2>&1; then
    hint="empty = keep current password"
  else
    hint="new user; empty = locked, SSH key only"
  fi
  while true; do
    pass1=$(dialog --clear --insecure --passwordbox "Password for ${SUPPORT_USER}\n(${hint}):" 10 70 2>&1 >/dev/tty) || return 1
    pass1=${pass1//$'\r'/}
    if [[ -z "$pass1" ]]; then
      USER_PASSWORD=""
      return 0
    fi
    pass2=$(dialog --clear --insecure --passwordbox "Repeat password for ${SUPPORT_USER}:" 10 70 2>&1 >/dev/tty) || return 1
    pass2=${pass2//$'\r'/}
    if [[ "$pass1" == "$pass2" ]]; then
      USER_PASSWORD="$pass1"
      return 0
    fi
    whiptail --msgbox "Passwords do not match. Try again." 8 50
  done
}

ensure_support_user() {
  # Create SUPPORT_USER if missing; if it already exists (e.g. Ubuntu's first user), only apply needed changes.
  local created=0
  if ! id -u "$SUPPORT_USER" >/dev/null 2>&1; then
    useradd "$SUPPORT_USER" -m -d "/home/${SUPPORT_USER}" -s /bin/bash
    created=1
  else
    usermod -s /bin/bash "$SUPPORT_USER" 2>/dev/null || true
    # Ensure home directory exists for key/password management
    local home_dir
    home_dir=$(getent passwd "$SUPPORT_USER" | cut -d: -f6)
    if [[ -n "$home_dir" && ! -d "$home_dir" ]]; then
      mkdir -p "$home_dir"
      chown "$SUPPORT_USER":"$SUPPORT_USER" "$home_dir"
    fi
  fi

  if [[ -n "$USER_PASSWORD" ]]; then
    echo "${SUPPORT_USER}:$USER_PASSWORD" | chpasswd
  elif [[ $created -eq 1 ]]; then
    # New user with no password: lock password auth (SSH key-only still works if configured)
    passwd -l "$SUPPORT_USER" >/dev/null 2>&1 || true
  fi
  # Existing user + empty password field: leave their current password untouched

  if getent group sudo >/dev/null 2>&1; then
    usermod -aG sudo "$SUPPORT_USER" 2>/dev/null || true
  fi
  setup_user_ssh_key "$SUPPORT_USER"
}

install_ipinfo() {
  local ipinfo_script
  ipinfo_script=$(mktemp /tmp/ipinfo-deb.XXXXXX)
  if curl -fsSL "https://github.com/ipinfo/cli/releases/download/ipinfo-${IPINFO_VERSION}/deb.sh" -o "$ipinfo_script"; then
    bash "$ipinfo_script"
  else
    ERRORS+="[ERROR] Could not download ipinfo CLI (SSH geo filter).\n"
  fi
  rm -f "$ipinfo_script"
}

install_ssh() {
  install_ipinfo
  # Replace VMALTAHOST only in regular files (avoids errors on dirs like ssh_config.d)
  for f in /etc/ssh/*; do
    [ -f "$f" ] && sed -i s/VMALTAHOST/"$HOST"/g "$f"
  done
  cp hosts/hosts.allow /etc/hosts.allow
  cp hosts/hosts.deny /etc/hosts.deny
  sed -i "s/.*UseDNS\+.*/UseDNS no/" /etc/ssh/sshd_config
  sed -i "s/.*MaxAuthTries\+.*/MaxAuthTries 3/" /etc/ssh/sshd_config
  sed -i "s/.*MaxSessions\+.*/MaxSessions 5/" /etc/ssh/sshd_config
  sed -i "s/.*ClientAliveInterval\+.*/ClientAliveInterval 300/" /etc/ssh/sshd_config
  sed -i "s/.*ClientAliveCountMax\+.*/ClientAliveCountMax 0/" /etc/ssh/sshd_config
  sed -i "s/.*MaxStartups\+.*/MaxStartups 10:30:60/" /etc/ssh/sshd_config
  sed -i "s/.*LoginGraceTime\+.*/LoginGraceTime 2m/" /etc/ssh/sshd_config

  # Fail2ban SSH jail (dynamic port on VMs)
  mkdir -p /etc/fail2ban/jail.d
  if [[ -f "$DIRALTA/fail2ban/jail.d/sshd.conf" ]]; then
    cp "$DIRALTA/fail2ban/jail.d/sshd.conf" /etc/fail2ban/jail.d/sshd.conf
  fi

  # VMs: custom port, no root SSH, password yes/no per choice
  # PVE/PBS: do not touch PermitRootLogin / Port / PasswordAuthentication (official defaults)
  if [[ ($PROXMOX_YES != 1) && ($PROXMOX_BACKUP_YES != 1) ]]; then
    sed -ri 's/^#?PermitRootLogin\s+.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i "s/.*Port \+.*/Port $SSH_PORT/" /etc/ssh/sshd_config
    sed -ri 's/^#?PubkeyAuthentication\s+.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    if [[ "${SSH_ALLOW_PASSWORD:-1}" -eq 0 ]]; then
      sed -ri 's/^#?PasswordAuthentication\s+.*/PasswordAuthentication no/' /etc/ssh/sshd_config
      sed -ri 's/^#?KbdInteractiveAuthentication\s+.*/KbdInteractiveAuthentication no/' /etc/ssh/sshd_config
      sed -ri 's/^#?ChallengeResponseAuthentication\s+.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
    else
      sed -ri 's/^#?PasswordAuthentication\s+.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    fi
    # sshd keeps the first value seen and Include'd drop-ins (e.g. Ubuntu 50-cloud-init.conf) are read first
    local pass_value="yes"
    [[ "${SSH_ALLOW_PASSWORD:-1}" -eq 0 ]] && pass_value="no"
    for f in /etc/ssh/sshd_config.d/*.conf; do
      [ -f "$f" ] && sed -ri "s/^\s*PasswordAuthentication\s+.*/PasswordAuthentication ${pass_value}/I" "$f"
    done
    # Align fail2ban jail port with custom SSH port
    if [[ -f /etc/fail2ban/jail.d/sshd.conf ]]; then
      sed -i "s/^port = .*/port = $SSH_PORT/" /etc/fail2ban/jail.d/sshd.conf
    fi
  fi

  systemctl reload fail2ban.service 2>/dev/null || true
  if systemctl is-active --quiet ssh 2>/dev/null; then
    systemctl reload ssh
  elif systemctl is-active --quiet sshd 2>/dev/null; then
    systemctl reload sshd
  fi
}

install_proxmox_logo() {
  local logo_src="$DIRALTA/images/proxmox_logo_custom.png"
  local logo_dst="/usr/share/javascript/proxmox-widget-toolkit/images/proxmox-logo.png"
  if [[ -f "$logo_src" ]]; then
    if [[ -f "$logo_dst" ]]; then
      cp "$logo_dst" "${logo_dst}.bkp" 2>/dev/null || true
    fi
    cp "$logo_src" "$logo_dst"
  else
    WARNINGS+="[WARNING] images/proxmox_logo_custom.png not found; skipping custom logo.\n"
  fi
}

config_raid() {
  OPTIONS00=(1 "RAID controller"
    2 "ZFS RAID"
    3 "None of the above")
  CHOICE00=$(dialog --clear \
    --menu "Select RAID type: " \
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
  echo -e "\e[0;31m# NOTE: This script assumes a single disk, /dev/sda       #\e[0m"
  echo -e "\e[0;31m# Edit config_raid_megacli if needed                      #\e[0m"
  echo -e "\e[0;31m###########################################################\e[0m"
  echo ""
  sleep 3

  # GPG key in keyring (apt-key is deprecated; compatible with all supported releases)
  mkdir -p /etc/apt/keyrings
  wget -qO /etc/apt/keyrings/hwraid.le-vert.net.gpg https://hwraid.le-vert.net/debian/hwraid.le-vert.net.gpg.key

  # Repository with signed-by
  cp "$DIRALTA/apt/debian/sources.list.d/megaraid.list" /etc/apt/sources.list.d/

  # Install packages
  aptitude update
  aptitude install -y megaclisas-status

  # Configure SMART
  ensure_line_in_file /etc/default/smartmontools "start_smartd=yes"

  # Configure disk monitoring
  DISKS=($(megacli -pdlist -a0 | grep 'Device Id' | cut -d " " -f 3))

  # Add disks to monitoring (rewrite from template each run — idempotent)
  cp "$DIRALTA/smart/megaraid" /etc/smartd.conf

  for disk in "${DISKS[@]}"; do
    ensure_line_in_file /etc/smartd.conf "/dev/sda -d megaraid,$disk -S on -o on -a -I 194 -s (S/../.././01|L/../../7/02) -m $CORREO"
  done

  systemctl restart smartd.service
  systemctl status smartd.service
}

config_raid_zfs() {
  clear
  echo ""
  echo -e "\e[0;31m################################################\e[0m"
  echo -e "\e[0;31m# NOTE: This script assumes a single rpool     #\e[0m"
  echo -e "\e[0;31m# Edit config_raid_zfs if needed               #\e[0m"
  echo -e "\e[0;31m################################################\e[0m"
  echo ""
  sleep 3
  #zpool list | grep "rpool" | wc -l 2>/dev/null

  # Enable email alerts
  apt-get install -y zfs-zed
  ensure_line_in_file /etc/zfs/zed.d/zed.rc 'ZED_EMAIL_ADDR="root"'
  systemctl restart zfs-zed.service

  # Reserve space for the ROOT dataset
  zfs set reservation=20G rpool/ROOT

  # Disable deduplication
  zfs set dedup=off rpool

  # Set compression algorithm
  zfs set compression=lz4 rpool

  # Disable sync writes; greatly improves write speed and IOPS
  zfs set sync=disabled rpool

  # Change default blocksize
  pvesm set local-zfs --blocksize 128k

  # Ensure thin volumes are created
  # Kept mainly as a reference if a ZFS pool is added manually
  pvesm set local-zfs --sparse 1

  # Reduce SWAP usage
  sysctl -w vm.swappiness=1
  ensure_sysctl_kv "vm.swappiness" "1"

  # ZFS ARC sized from RAM (min 8GB guidance; avoid starving the system)
  RAM_BYTES=$(awk '/MemTotal/ {print $2*1024}' /proc/meminfo)
  ARC_MIN=$((2*1024*1024*1024))   # 2 GB minimum
  ARC_MAX=$((RAM_BYTES/2))        # 50% RAM
  ARC_MAX_CAP=$((16*1024*1024*1024))  # 16 GB cap
  [[ $ARC_MAX -gt $ARC_MAX_CAP ]] && ARC_MAX=$ARC_MAX_CAP
  [[ $ARC_MAX -lt $ARC_MIN ]] && ARC_MAX=$ARC_MIN
  cat >/etc/modprobe.d/zfs.conf << EOF
# Generated by script-altahost (detected RAM: $((RAM_BYTES/1024/1024)) MB)
options zfs zfs_arc_min=$ARC_MIN
options zfs zfs_arc_max=$ARC_MAX
EOF
  update-initramfs -u

  ###############################################

  # Install and configure smartmontools

  # Install packages
  aptitude update
  aptitude install -y smartmontools

  # Configure SMART
  ensure_line_in_file /etc/default/smartmontools "start_smartd=yes"

  # Add disks to monitoring
  cp "$DIRALTA/smart/smartmontools" /etc/smartd.conf
  sed -i "s/EMAILC/$CORREO/g" /etc/smartd.conf

  # Check whether SMART is enabled on each disk
  #smartctl -a /dev/sda | grep "SMART support is: "

  systemctl restart smartd.service
  systemctl status smartd.service

  ###############################################

  # Install ZFS check for Zabbix
  if [[ -f /etc/zabbix/zabbix_agentd.conf ]] && [[ -n "$DIRALTA" ]]; then
    cp "$DIRALTA/zabbix/zabbix_agentd.d/ZoL_without_sudo.conf" /etc/zabbix/zabbix_agentd.d/
    systemctl restart zabbix-agent.service
  fi

  ###############################################

  # Optional Sanoid (ZFS snapshot policies for VM datasets)
  install_sanoid
}

# Sanoid: policy-driven ZFS snapshots (optional; increases IO).
# Prefer distro package; fall back to upstream build without pinning libc.
install_sanoid() {
  if ! (whiptail --title "Sanoid" --yesno "Install Sanoid (automated ZFS snapshots)?\n\nApplies policies to rpool/data (see sanoid.conf).\nNote: snapshot churn can raise IO delay." 13 70); then
    return 0
  fi

  mkdir -p /etc/sanoid
  local sanoid_ok=0
  local build_dir tag prev_dir
  prev_dir=$(pwd)

  apt-get update
  if apt-get install -y sanoid; then
    sanoid_ok=1
    if [[ -f /usr/share/sanoid/sanoid.defaults.conf ]]; then
      cp /usr/share/sanoid/sanoid.defaults.conf /etc/sanoid/ 2>/dev/null || true
    elif [[ -f /usr/share/doc/sanoid/examples/sanoid.defaults.conf ]]; then
      cp /usr/share/doc/sanoid/examples/sanoid.defaults.conf /etc/sanoid/ 2>/dev/null || true
    fi
  else
    WARNINGS+="[WARNING] apt package 'sanoid' not available; building from upstream git (no libc pin).\n"
    if ! apt-get install -y debhelper libcapture-tiny-perl libconfig-inifiles-perl pv lzop mbuffer build-essential git; then
      ERRORS+="[ERROR] Sanoid dependencies failed to install.\n"
      return 1
    fi

    build_dir=$(mktemp -d /tmp/sanoid-build.XXXXXX)
    if git clone --depth 1 https://github.com/jimsalterjrs/sanoid.git "$build_dir/sanoid"; then
      cd "$build_dir/sanoid" || {
        ERRORS+="[ERROR] Could not enter Sanoid build directory.\n"
        rm -rf "$build_dir"
        cd "$prev_dir" || true
        return 1
      }
      git fetch --tags --depth 1 2>/dev/null || true
      tag=$(git tag | grep '^v' | sort -V | tail -n 1)
      if [[ -n "$tag" ]]; then
        git checkout "$tag" 2>/dev/null || true
      fi
      ln -sfn packages/debian .
      if dpkg-buildpackage -uc -us && apt-get install -y "$build_dir"/sanoid_*_all.deb; then
        sanoid_ok=1
      else
        # Last resort: install scripts without packaging
        cp -f sanoid syncoid findoid sleepymutex /usr/local/sbin/ 2>/dev/null || true
        chmod 755 /usr/local/sbin/sanoid /usr/local/sbin/syncoid /usr/local/sbin/findoid /usr/local/sbin/sleepymutex 2>/dev/null || true
        [[ -f sanoid.defaults.conf ]] && cp sanoid.defaults.conf /etc/sanoid/
        if command -v sanoid >/dev/null 2>&1 || [[ -x /usr/local/sbin/sanoid ]]; then
          sanoid_ok=1
          WARNINGS+="[WARNING] Sanoid installed from scripts to /usr/local/sbin (no systemd package timer).\n"
        else
          ERRORS+="[ERROR] Sanoid build/install failed.\n"
        fi
      fi
      cd "$prev_dir" || cd "$DIRALTA" || true
    else
      ERRORS+="[ERROR] Could not clone Sanoid upstream repository.\n"
    fi
    rm -rf "$build_dir"
  fi

  if [[ $sanoid_ok -eq 1 && -f "$DIRALTA/sanoidcfg/sanoid.conf_template" ]]; then
    cp "$DIRALTA/sanoidcfg/sanoid.conf_template" /etc/sanoid/sanoid.conf
  fi

  if [[ $sanoid_ok -eq 1 ]] && systemctl list-unit-files sanoid.timer >/dev/null 2>&1; then
    systemctl enable sanoid.timer
    systemctl start sanoid.timer
  elif [[ $sanoid_ok -eq 1 ]]; then
    WARNINGS+="[WARNING] sanoid.timer not found; enable snapshots manually or install the packaged unit.\n"
  fi
}

install_server_proxmox_backup_server() {
  # Package install and updates
  cp apt/debian/sources.list.d/pbs-enterprise.list /etc/apt/sources.list.d/
  cp apt/debian/sources.list.d/pbs-no-subscription.list /etc/apt/sources.list.d/
  aptitude install -y pigz ifupdown2

  # Configure fail2ban
  cp fail2ban/filter.d/proxmoxbackupserver.conf /etc/fail2ban/filter.d/
  cp fail2ban/jail.d/proxmoxbackupserver.conf /etc/fail2ban/jail.d/
  cp fail2ban/jail.local /etc/fail2ban/
  systemctl reload fail2ban.service
}

install_server_proxmox() {
  # Select package
  cmd=(dialog --separate-output --checklist "Select packages to install:" 22 76 16)
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

  # Package install and updates
  cp apt/debian/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/
  cp apt/debian/sources.list.d/pve-no-subscription.list /etc/apt/sources.list.d/
  aptitude install -y pigz ifupdown2

  # Configure fail2ban
  cp fail2ban/filter.d/proxmox.conf /etc/fail2ban/filter.d/
  cp fail2ban/jail.d/proxmox.conf /etc/fail2ban/jail.d/
  cp fail2ban/jail.local /etc/fail2ban/
  systemctl reload fail2ban.service

  # Enable pigz compression for gzip (once)
  touch /etc/vzdump.conf
  if ! grep -qE '^[[:space:]]*pigz:' /etc/vzdump.conf; then
    echo "pigz: 1" >>/etc/vzdump.conf
  fi

  # Copy PVE scripts
  cp scripts/proxmox/* /usr/local/sbin/
  chmod 755 /usr/local/sbin/*
}

install_vm() {
  # Select package
  cmd=(dialog --separate-output --checklist "Select packages to install:" 22 76 16)
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

  # Docker on Ubuntu
  INSTALLDOCKER=$(lsb_release -is | grep -ci "ubuntu" 2>/dev/null)
  if [[ $INSTALLDOCKER -eq 1 ]]; then
    if (whiptail --title "" --yesno "Install DOCKER?" 10 60); then
      install_docker
    fi
  fi
}

install_wireguard() {
  if [[ $WIREGUARDON -eq 1 ]]; then
    local wg_script
    wg_script=$(mktemp /tmp/wg-install.XXXXXX)
    if wget -q -O "$wg_script" https://raw.githubusercontent.com/avillalba96/mkt-wireguard_init/refs/heads/main/linux_install-client.sh; then
      chmod +x "$wg_script"
      bash "$wg_script"
    else
      ERRORS+="[ERROR] Could not download the WireGuard installer.\n"
    fi
    rm -f "$wg_script"
  fi
}

finish_script() {
  sysctl --system
  apt-get autoremove -y && apt-get autoclean -y

  # Keep the repo for post-install debugging.
  # Do not store secrets on disk: password lives only in memory during provisioning.
  REPO_ROOT=$(dirname "$DIRALTA")
  rm -f /root/.wget-hsts 2>/dev/null || true
  # Defensive cleanup in case old temp files remain
  rm -f /var/log/out.tmp /tmp/out.tmp /tmp/out2.tmp /tmp/out3.tmp 2>/dev/null || true

  # Provisioning summary without secrets (useful for debug)
  {
    echo "fecha=$(date -Is)"
    echo "host=${HOST}.${DOMINIO}"
    echo "so=$(lsb_release -ds 2>/dev/null)"
    echo "support_user=${SUPPORT_USER}"
    echo "ssh_port=${SSH_PORT}"
    echo "ssh_allow_password=${SSH_ALLOW_PASSWORD:-n/a}"
    echo "ssh_allow_countries=${SSH_ALLOW_COUNTRIES}"
    echo "ssh_pubkey_configured=$([ -n "$SSH_PUBKEY" ] && echo yes || echo no)"
    echo "proxmox=${PROXMOX_YES:-0}"
    echo "pbs=${PROXMOX_BACKUP_YES:-0}"
    echo "repo=${REPO_ROOT}"
    echo "log=/var/log/altahost/alta_altahost.log"
    echo "progress_log=/var/log/altahost/progress.log"
    echo "last_step=/var/log/altahost/last_step"
    echo "status=completed"
  } >/var/log/altahost/alta_summary.txt
  chmod 600 /var/log/altahost/alta_summary.txt

  alta_mark_completed

  clear
  echo ""
  echo -e "\e[1;32m++++++++++++++++++++++++++++++++++++++++++++++++\e[0m"

  if [[ -n "$ERRORS" ]]; then
    echo -e "\e[0;31mThe following errors were detected during execution:\e[0m"
    echo -e "$ERRORS"
    echo ""
  fi

  if [[ -n "$WARNINGS" ]]; then
    echo -e "\e[1;33mThe following warnings were detected:\e[0m"
    echo -e "$WARNINGS"
    echo ""
  fi

  echo -e "\e[0mCongratulations, the process has finished\e[0m"
  echo ""
  echo -e "\e[0;31mHOST: \e[1;33m$HOST.$DOMINIO\e[0m"
  echo -e "\e[0;31mSUPPORT USER: \e[1;33m${SUPPORT_USER}\e[0m"
  if [[ ($PROXMOX_YES != 1) && ($PROXMOX_BACKUP_YES != 1) ]]; then
    echo -e "\e[0;31mSSH: \e[0mport \e[1;33m$SSH_PORT\e[0m | password=\e[1;33m$([ "${SSH_ALLOW_PASSWORD:-1}" -eq 1 ] && echo yes || echo no)\e[0m | pubkey=\e[1;33m$([ -n "$SSH_PUBKEY" ] && echo yes || echo no)\e[0m | countries=\e[1;33m${SSH_ALLOW_COUNTRIES}\e[0m"
  fi
  echo ""
  echo -e "\e[0;31mDEBUG: \e[0mRepo kept at \e[1;33m$REPO_ROOT\e[0m"
  echo -e "\e[0m       Log: \e[1;33m/var/log/altahost/alta_altahost.log\e[0m"
  echo -e "\e[0m       Summary: \e[1;33m/var/log/altahost/alta_summary.txt\e[0m"
  echo -e "\e[0m       Progress: \e[1;33m/var/log/altahost/progress.log\e[0m"
  echo ""
  echo -e "\e[0;31mREMINDER: \e[0mAdd this host to the backup system \e[0m"
  echo -e "\e[0m[\e[1;31mBORG \e[0;0m/ \e[1;33mPROXMOX \e[0;0m/ \e[1;33mPBS \e[0;0m/ \e[1;32mVEEAM\e[0m]"
  echo ""
  echo -e "\e[0;31mIMPORTANT: \e[0mPlease reboot this host\e[0m"
  echo -e "\e[1;32m++++++++++++++++++++++++++++++++++++++++++++++++\e[0m"
  echo ""

  exit
}

init_script() {
  # Resolve script directory regardless of how it was invoked
  DIRALTA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Update apt sources for the corresponding distro version
  NAMEHOST=$(lsb_release -ds)
  VERSIONSO=$(lsb_release -cs)
  grep -rl SO_VERSION apt/. | xargs sed -i "s/SO_VERSION/${VERSIONSO}/g" 2>/dev/null

  # Collect host details
  HOST=$(hostname)
  local form_out
  local form_domain="example.com" form_user="$SUPPORT_USER" form_port="23242"
  local form_mail="alerts@example.com" form_relay="172.26.0.1"

  # Cancel or invalid input goes back to the form (keeping typed values) instead of aborting
  while true; do
    if ! form_out=$(dialog --clear \
      --form "Fill in client host details:" 16 60 5 \
      "Host domain: " 1 1 "$form_domain" 1 32 25 30 \
      "Support username: " 2 1 "$form_user" 2 32 25 30 \
      "SSH port: " 3 1 "$form_port" 3 32 25 30 \
      "Alert email (aliases): " 4 1 "$form_mail" 4 32 25 30 \
      "Relayhost (empty=direct MX): " 5 1 "$form_relay" 5 32 25 30 \
      2>&1 >/dev/tty); then
      if (whiptail --title "Cancel" --yesno "Exit the installer?\n\nNO = back to the form" 10 60); then
        install_abort "cancelled_form"
      fi
      continue
    fi

    form_out=$(tr -d '\r' <<<"$form_out")
    # Do not drop empty lines: an empty relayhost must keep line 5
    form_domain=$(sed -n '1p' <<<"$form_out" | tr -d ' \t')
    form_user=$(sed -n '2p' <<<"$form_out" | tr -d ' \t')
    form_port=$(sed -n '3p' <<<"$form_out" | tr -d ' \t')
    form_mail=$(sed -n '4p' <<<"$form_out" | tr -d ' \t')
    form_relay=$(sed -n '5p' <<<"$form_out" | tr -d ' \t')

    if [[ ! "$form_domain" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ || "$form_domain" == "example.com" ]]; then
      whiptail --msgbox "Invalid host domain: '${form_domain}'\nUse the real domain (e.g. frsf.utn.edu.ar)." 9 60
      continue
    fi
    if [[ -z "$form_user" || "$form_user" == "root" ]]; then
      whiptail --msgbox "Support username cannot be empty or 'root'." 8 50
      continue
    fi
    if [[ ! "$form_user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
      whiptail --msgbox "Invalid support username: ${form_user}\nUse lowercase letters, digits, _ or -." 9 60
      continue
    fi
    if [[ ! "$form_port" =~ ^[0-9]+$ ]] || ((form_port < 1 || form_port > 65535)); then
      whiptail --msgbox "Invalid SSH port: '${form_port}' (1-65535)." 8 50
      continue
    fi

    DOMINIO="$form_domain"
    SUPPORT_USER="$form_user"
    SSH_PORT="$form_port"
    CORREO="$form_mail"
    IPCORREO="$form_relay"

    prompt_support_password || continue
    break
  done

  FQDN="${HOST}.${DOMINIO}"
  MAIL_FROM="${HOST}@${DOMINIO}"

  # Configurable timezone (default America/Argentina/Buenos_Aires)
  TIMEZONE_DEFAULT="America/Argentina/Buenos_Aires"
  if (whiptail --title "" --yesno "Use default timezone (${TIMEZONE_DEFAULT})?\n\nSelect NO to specify another (e.g. Europe/Madrid)." 12 70); then
    TIMEZONE="$TIMEZONE_DEFAULT"
  else
    TIMEZONE=$(whiptail --inputbox "Enter timezone (e.g. Europe/Madrid):" 10 60 "$TIMEZONE_DEFAULT" 3>&1 1>&2 2>&3) || TIMEZONE="$TIMEZONE_DEFAULT"
  fi

  # SSH geo-allowlist (ISO country codes, comma-separated)
  SSH_ALLOW_COUNTRIES=$(whiptail --inputbox "SSH allow countries (ISO codes, e.g. US,DE,AR):" 10 60 "$SSH_ALLOW_COUNTRIES" 3>&1 1>&2 2>&3) || true
  SSH_ALLOW_COUNTRIES=$(echo "$SSH_ALLOW_COUNTRIES" | tr -d ' \t\r\n')
  [[ -z "$SSH_ALLOW_COUNTRIES" ]] && SSH_ALLOW_COUNTRIES="AR"

  # Try to detect the primary IP
  IP=$(ip a | grep inet | grep -v inet6 | grep -v 127.0.0.1 | head -n1 | awk -F'[/ ]+' '{print $3}')

  # Detect PVE/PBS before SSH options (PVE/PBS leave official SSH auth alone)
  PROXMOX_YES=$(pveversion 2>/dev/null | wc -l)
  PROXMOX_BACKUP_YES=$(proxmox-backup-manager versions 2>/dev/null | wc -l)
  configure_ssh_auth_options

  # Change hostname before installing packages
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

  # Package install and updates
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

  # Copy shared scripts
  cp scripts/all/* /usr/local/sbin/
  chmod 755 /usr/local/sbin/*
  # Apply deployment SSH allow-countries to installed ipfilter script
  if [[ -f /usr/local/sbin/ipfilter-whitelist.sh ]]; then
    sed -i "s/^ALLOW_COUNTRIES=.*/ALLOW_COUNTRIES=\"${SSH_ALLOW_COUNTRIES}\"/" /usr/local/sbin/ipfilter-whitelist.sh
  fi

  # Enable NTP client
  rm -f /etc/localtime
  ln -s "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
  cp systemd/timesyncd.conf /etc/systemd/timesyncd.conf
  timedatectl set-ntp true
  systemctl restart systemd-timesyncd.service
  timedatectl set-timezone "${TIMEZONE}"

  # Personalization
  cp vim/vimrc /root/.vimrc
  update-alternatives --set editor /usr/bin/vim.basic
  cp bash/bashrc /root/.bashrc

  # Use rsyslog for fail2ban
  aptitude install -y fail2ban
  sed '/logtarget =/c\logtarget = SYSLOG' -i /etc/fail2ban/fail2ban.conf
  sed -i "s/destemail = root@localhost/destemail = $CORREO/g" /etc/fail2ban/jail.conf
  sed -i "s/sender = root@<fq-hostname>/sender = $MAIL_FROM/g" /etc/fail2ban/jail.conf
  #  sed -i "s/action = %(action_)s/action = %(action_mw)s/g" /etc/fail2ban/jail.conf
  systemctl reload fail2ban.service

  # Configure Postfix (origin HOST@DOMINIO; optional relayhost)
  export DEBIAN_FRONTEND=noninteractive
  aptitude install -y postfix mailutils
  echo "$DOMINIO" >/etc/mailname
  cp others/aliases /etc/aliases
  sed -i "s/EMAILC/$CORREO/g" /etc/aliases
  sed -e "s/HOST/$HOST/g" -e "s/DOMINIO/$DOMINIO/g" -e "s/FQDN/$FQDN/g" \
    -e "s/MAIL_FROM/$MAIL_FROM/g" others/postfix-generic >/etc/postfix/generic
  sed -e "s/EMAILC/$CORREO/g" -e "s/DOMINIO/$DOMINIO/g" others/postfix-virtual >/etc/postfix/virtual
  sed -e "s/MAIL_FROM/$MAIL_FROM/g" others/postfix-header_checks >/etc/postfix/header_checks
  postmap /etc/postfix/generic
  postmap /etc/postfix/virtual
  postconf -e "myhostname = $FQDN"
  postconf -e "myorigin = $DOMINIO"
  postconf -e "smtp_generic_maps = hash:/etc/postfix/generic"
  postconf -e "smtp_header_checks = regexp:/etc/postfix/header_checks"
  postconf -e "virtual_alias_maps = hash:/etc/postfix/virtual"
  if [[ -n "$IPCORREO" ]]; then
    postconf -e "relayhost = $IPCORREO"
  else
    postconf -e "relayhost ="
  fi
  postfix check
  systemctl restart postfix.service
  newaliases

  # Configure Cron (once — marked block, no duplicates on retry)
  local cron_file="/var/spool/cron/crontabs/root"
  local cron_marker="### altahost-modelo_crontab ###"
  touch "$cron_file"
  if ! grep -qF "$cron_marker" "$cron_file" 2>/dev/null; then
    {
      echo "$cron_marker"
      cat "$DIRALTA/crontab/modelo_crontab"
    } >>"$cron_file"
  fi
  chmod 600 "$cron_file"
  systemctl restart cron.service

  # Reduce SWAP usage
  sysctl -w vm.swappiness=10
  ensure_sysctl_kv "vm.swappiness" "10"
}

select_package_init() {
  # Select package
  cmd=(dialog --separate-output --checklist "Select packages to install:" 22 76 16)
  Opcions=(1 "Client - VPN (pfSense)" off
    2 "Client - ZABBIX (${ZABBIX_VERSION} LTS)" off
    3 "Client - BORG (CUSTOM)" off
    4 "Client - WireGuard" off)
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
      WIREGUARDON=1
      ;;
    esac
  done
}

start_install() {
  run_step select_package_init select_package_init
  run_step init_script init_script
  run_step ensure_support_user ensure_support_user
  run_step install_zabbix_basic install_zabbix_basic
  if [[ $PROXMOX_YES -eq 1 ]]; then
    run_step install_server_proxmox install_server_proxmox
    run_step config_raid config_raid
    run_step install_amdfixes install_amdfixes
    run_step install_ksmtuned install_ksmtuned
  elif [[ $PROXMOX_BACKUP_YES -eq 1 ]]; then
    run_step install_server_proxmox_backup_server install_server_proxmox_backup_server
    run_step config_raid config_raid
  else
    run_step install_vm install_vm
    run_step install_qemu install_qemu
  fi
  run_step install_motd install_motd
  run_step install_ssh install_ssh
  run_step install_borg install_borg
  run_step install_client_vpn install_client_vpn
  run_step install_wireguard install_wireguard
  run_step finish_script finish_script
}

prepare_system() {
  alta_mark_in_progress
  step_start prepare_system

  # Disable IPv6
  echo -e "Acquire::ForceIPv4 \"true\";\\n" >/etc/apt/apt.conf.d/99-force-ipv4
  # Ensure /etc/sysctl.conf exists before using sed
  [ -f /etc/sysctl.conf ] || touch /etc/sysctl.conf
  ensure_sysctl_kv "net.ipv6.conf.all.disable_ipv6" "1"
  ensure_sysctl_kv "net.ipv6.conf.default.disable_ipv6" "1"
  ensure_sysctl_kv "net.ipv6.conf.lo.disable_ipv6" "1"
  sysctl --system

  # Install packages required for the installation menu
  apt-get update && apt-get upgrade -y
  apt-get install -y dialog wget curl lsb-release

  if (whiptail --title "" --yesno "Ensure unrestricted Internet access. Press YES to continue." 10 60); then
    DEBIANVERSION_YES=$(lsb_release -is | grep -ci "debian")
    UBUNTUVERSION_YES=$(lsb_release -is | grep -ci "ubuntu")

    if [[ ("$DEBIANVERSION_YES" == 0) && ("$UBUNTUVERSION_YES" == 0) ]]; then
      install_abort "unsupported_os"
    else
      step_ok prepare_system
      start_install
    fi
  else
    install_abort "cancelled_internet_check"
  fi
}

main() {
  WHO=$(whoami)
  if [[ ($WHO != root) ]]; then
    echo -e "\e[0;31m[ERROR]: \e[0mYou must run this script as \e[1;32m'root'\e[0m"
    exit
  else
    # Initialize variables
    VPNON=0
    ZABBIXON=0
    BORGON=0
    QEMUON=0
    AMDFIXES=0
    KSMTUNED=0
    WIREGUARDON=0
    SSH_ALLOW_PASSWORD=1
    SSH_PUBKEY=""
    ERRORS=""
    WARNINGS=""
    CURRENT_STEP=""
    LAST_OK_STEP=""
    ALTA_FINISHED=0

    # Start installation
    clear
    mkdir -p "$ALTA_LOG_DIR"
    chmod 700 "$ALTA_LOG_DIR"

    local prev_status
    prev_status=$(alta_previous_status)
    case "$prev_status" in
    completed)
      echo -e "\e[0;31m[ERROR]: \e[0mThis host has already been provisioned (status=completed)\e[0m"
      [[ -f "$ALTA_LOG_DIR/last_step" ]] && echo -e "See \e[1;33m${ALTA_LOG_DIR}/last_step\e[0m"
      exit 1
      ;;
    in_progress | interrupted)
      echo -e "\e[1;33m[INFO]: \e[0mIncomplete previous run detected (status=${prev_status})\e[0m"
      if [[ -f "$ALTA_LOG_DIR/last_step" ]]; then
        echo "---- last_step ----"
        cat "$ALTA_LOG_DIR/last_step"
        echo "-------------------"
      fi
      if [[ -f "$ALTA_LOG_DIR/HOW_TO_RESUME.txt" ]]; then
        echo "---- HOW_TO_RESUME ----"
        cat "$ALTA_LOG_DIR/HOW_TO_RESUME.txt"
        echo "----------------------"
      fi
      local retry=0
      if command -v whiptail >/dev/null 2>&1; then
        if (whiptail --title "Incomplete install" --yesno "A previous install did not finish.\n\nstatus=${prev_status}\n\nRetry now? (restarts from the beginning; check last_ok_step in the log)" 14 70); then
          retry=1
        fi
      else
        echo -n "Retry incomplete install now? [y/N]: "
        read -r ans || true
        [[ "$ans" =~ ^[Yy]$ ]] && retry=1
      fi
      if [[ $retry -ne 1 ]]; then
        echo -e "Aborted. Resume hints: \e[1;33m${ALTA_LOG_DIR}/HOW_TO_RESUME.txt\e[0m"
        exit 1
      fi
      progress_log "RETRY accepted after status=${prev_status}"
      ;;
    esac

    (
      (
        trap 'alta_mark_interrupted interrupted_signal' INT TERM
        trap '[[ ${ALTA_FINISHED:-0} -eq 1 ]] || alta_mark_interrupted unexpected_exit' EXIT
        prepare_system
      ) 2>&1
    ) | tee -a "$ALTA_LOG_DIR/alta_altahost.log"
    sanitize_alta_logs
    chmod 600 "$ALTA_LOG_DIR/alta_altahost.log" 2>/dev/null || true
  fi
}

main
