# script-altahost

Post-install bootstrap for **Debian**, **Ubuntu**, **Proxmox VE** and **Proxmox Backup Server**.

One public script for VMs and hypervisors. Targets **currently supported** releases (`+` = from that baseline up to whatever is current when you run it). MIT licensed — use and adapt freely.

## Compatibility

Same entrypoint for all platforms: `install/altahost-start.sh`

| Platform | Supported line |
|----------|----------------|
| **Debian** | 11 **+** (11, 12, 13, … current in support) |
| **Ubuntu** | 20.04 **+** (20.04, 22.04, 24.04, … current LTS in support) |
| **Proxmox VE** | **7 +** (7, 8, 9, … current) |
| **Proxmox Backup** | **2 +** (2, 3, … current) |
| **Docker** (optional) | Ubuntu only |

The script detects the host type and applies the matching branch.

## Quick start

```bash
apt-get update; apt-get install -y git screen
screen
git clone https://github.com/avillalba96/script-altahost && cd script-altahost/install && ./altahost-start.sh
```

Run as **root** on a freshly installed system when possible.

## Defaults you may want to change

At the top of `install/altahost-start.sh` (fallbacks only — the install UI asks again):

| Variable | Default | Meaning |
|----------|---------|---------|
| `SUPPORT_USER` | `support` | Default shown in the form for the day-to-day sudo account |
| `SSH_ALLOW_COUNTRIES` | `AR` | Default shown when prompting for SSH geo-allowlist |

### Support username (create or reuse)

In the main form you type the **support username** (e.g. `support`, `soportecc`, or an existing Ubuntu user like `usuariopepe`):

- **Does not exist** → created (`sudo`, home, shell, optional password/SSH key)
- **Already exists** → reused; script only applies what is needed (`sudo`, password if you typed one, SSH key if provided). Empty password field leaves the existing password unchanged.

The password is asked in its own prompt after the form, showing the username you typed (asked twice to avoid typos). Invalid form values or Cancel/Esc go back to the form instead of aborting.

### SSH authentication (VMs)

- **Password login: YES** → password kept; optionally paste an SSH public key.
- **Password login: NO** → paste the full `.pub` content (one line). If it is empty/invalid you are asked to retry; answering **NO** to retry continues with password login (Ubuntu default) and a warning at the end — the install is never cancelled for a missing key.
- `root` can never log in over SSH (`PermitRootLogin no`); use `sudo`.
- `PasswordAuthentication` is also applied to `/etc/ssh/sshd_config.d/*.conf` (Ubuntu's `50-cloud-init.conf` would otherwise override it).
- On Ubuntu with socket-activated SSH (`ssh.socket`), the new port is active after a reboot (or `systemctl daemon-reload && systemctl restart ssh.socket`).

### SSH countries

During install a **whiptail prompt** asks for ISO country codes (e.g. `US,DE,AR`), pre-filled with `SSH_ALLOW_COUNTRIES`. That value is written into `/usr/local/sbin/ipfilter-whitelist.sh`. You can also edit that file later and/or change the default constant in the script.

## Main features

- Baseline packages, SSH hardening helpers, MOTD banners, Postfix alerts
- Creates or reuses the **support username** from the form (sudo + optional SSH key)
- **VMs:** choose password SSH or key-only (falls back to password if no key); custom SSH port; `PermitRootLogin no`
- **PVE/PBS:** official `sshd` defaults left alone; you can still attach a key to `SUPPORT_USER`
- SSH country filter via **ipinfo** + tcp_wrappers
- Fail2ban: PVE/PBS UI jails + `sshd` jail
- Optional: Zabbix 7.4 LTS, WireGuard, Docker + Compose plugin, Borg, QEMU guest agent
- ZFS helpers (ARC from RAM); optional **Sanoid** snapshots; MegaRAID SMART path
- Timezone menu (default `America/Argentina/Buenos_Aires`)
- Install repo and logs kept for debug under `/var/log/altahost/` (form password is not written to disk)
- **Resume-friendly progress:** each phase is logged; on cancel/SSH drop/crash see `last_step`, `progress.log`, and `HOW_TO_RESUME.txt`. Re-running offers a retry. Risky steps are **idempotent** (no duplicate cron/sysctl/vzdump, safe banner/user reuse). Logs are mode `600` and scrubbed so passwords/SSH key material are not kept.

## Sanoid (optional)

Asked only on the **ZFS** RAID path. Sanoid applies snapshot policies (template ships for `rpool/data`).

Install order:

1. Try **`apt install sanoid`** (Debian/Proxmox repos — preferred)
2. If missing, **build from upstream git** (no forced old `libc6`)
3. Copy `install/sanoidcfg/sanoid.conf_template` → `/etc/sanoid/sanoid.conf`
4. Enable `sanoid.timer` when the package provides it

Snapshot schedules add IO; skip Sanoid if you do not need host-side ZFS snaps.

## Banners and logo

- `install/systemd/pvebanner-service_custom`
- `install/systemd/pbsbanner-service_custom`
- `install/systemd/vmbanner-service_custom`
- Optional Proxmox UI logo: `install/images/proxmox_logo_custom.png`

## ZFS cheatsheet (applied on ZFS path)

```bash
zfs set reservation=20G rpool/ROOT
zfs set dedup=off rpool
zfs set compression=lz4 rpool
zfs set sync=disabled rpool
pvesm set local-zfs --blocksize 128k
pvesm set local-zfs --sparse 1
```

`sync=disabled` trades durability on power loss for write performance — use deliberately.

## TO-DO

1. Make Borg path fully generic — <https://github.com/avillalba96/borg_config>
2. Cloud-init companion — <https://github.com/avillalba96/script-pve_cloudinit>

## License

MIT — see [LICENSE](LICENSE).

## Authors

- Maxi - [Maximiliano Baez](https://github.com/MaximilianoBz)
- Pablito - [Pablo Ramos](https://github.com/avillalba96)
- Alejandro - [Alejandro Villalba](https://github.com/avillalba96)
- Matias - [Matias Yaccuzzi](https://github.com/matiassy)
