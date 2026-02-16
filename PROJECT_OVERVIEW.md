# PROJECT OVERVIEW — Infrastructure Master Summary

> Auto-generated synthesis of all documentation and infrastructure scripts in this repository.
> Source: recursive scan of all markdown files and shell scripts.
> No `claude.md` files were found; all data extracted from `docs/*.md`, `README.md`, and `proxmox/**/*.sh`.

---

## A) GLOBAL PROJECT STATUS

This repository serves a dual purpose:

1. **Docker Hub MCP Server** — A Node.js/TypeScript Model Context Protocol server that interfaces with Docker Hub APIs for LLM-powered container image discovery and repository management.
2. **Proxmox Infrastructure-as-Code** — A complete 2-host Proxmox VE cluster with GPU passthrough, VM management, remote access, and file sharing.

### Host Inventory

#### Workstation Host — Host 1 (192.168.16.2)

| Attribute | Value |
|-----------|-------|
| IP Address | `192.168.16.2` |
| Role | Windows Workstation + large AI models |
| GPU | AMD RX 6800 XT (16 GB, Navi 21) |
| Bridges | `vmbr0` (LAN, 192.168.16.2/24), `vmbr1` (VM-Netz, 192.168.20.1/24) |
| Primary VM | `win11-workstation` (VMID 100, IP 192.168.20.10) |
| Access | RDP from ThinkPad |
| OS | Proxmox VE 7.x / 8.x |
| Status | Scripts provisioned; GPU passthrough requires reboot after `setup-gpu-passthrough.sh` |

#### Workstation Host — Host 2 (192.168.16.3)

| Attribute | Value |
|-----------|-------|
| IP Address | `192.168.16.3` |
| Role | Docker + Ollama + 24/7 services |
| GPU | NVIDIA GTX 1080 (8 GB) |
| Bridges | `vmbr0` (LAN, 192.168.16.3/24), `vmbr1` (VM-Netz, 192.168.20.1/24) |
| Primary VMs | Docker host, Linux services |
| Access | SSH + Portainer |
| OS | Proxmox VE 7.x / 8.x |
| Status | Scripts provisioned; designated for always-on services |

#### ThinkPad Client (192.168.16.10)

| Attribute | Value |
|-----------|-------|
| IP Address | `192.168.16.10` |
| Role | Client workstation (RDP/SPICE access to VMs) |
| Routing | Requires `ip route add 192.168.20.0/24 via 192.168.16.2` |
| Mounts | `/mnt/projects`, `/mnt/documents`, `/mnt/backups` via CIFS from 192.168.20.20 |

### Virtual Machines

| VMID | Name | Host | IP | Type | Display | Notes |
|------|------|------|----|------|---------|-------|
| 100 | win11-workstation | Host 1 | 192.168.20.10 | Windows 11 | GPU (RX 6800 XT passthrough) | 16 GB RAM, 8 cores, 100 GB disk, UEFI + TPM 2.0 |
| 200 | linux-desktop | Host 1/2 | 192.168.20.20 | Ubuntu 22.04 | SPICE/QXL | 4 GB RAM, 4 cores, 50 GB disk, Cloud-Init |
| 9000 | ubuntu-2204-cloud | Any | DHCP | Template | Serial console | Cloud-Init base template, 2 GB RAM, 2 cores, 32 GB disk |

### Network Topology

```
LAN: 192.168.16.0/24
├── Host 1:    192.168.16.2  (RX 6800 XT)
├── Host 2:    192.168.16.3  (GTX 1080)
├── ThinkPad:  192.168.16.10 (Client)
└── Gateway:   192.168.16.1

VM-Netz: 192.168.20.0/24 (NAT via vmbr1 → vmbr0)
├── Windows VM:  192.168.20.10 (VMID 100)
├── Linux VM:    192.168.20.20 (VMID 200)
└── Gateway:     192.168.20.1  (vmbr1 on hosts)
```

---

## B) CENTRALIZED INFRASTRUCTURE

### Scripts

| Path | Purpose | Target Host |
|------|---------|-------------|
| `proxmox/network/setup-nat.sh` | NAT/MASQUERADE for 192.168.20.0/24 → WAN | Both hosts |
| `proxmox/network/setup-firewall.sh` | PVE cluster + host firewall rules | Both hosts |
| `proxmox/network/harden-ssh.sh` | SSH hardening (key-only, no root password) | Both hosts |
| `proxmox/network/setup-fail2ban.sh` | Fail2Ban for SSH + PVE Web GUI | Both hosts |
| `proxmox/network/interfaces-host1.example` | `/etc/network/interfaces` template for Host 1 | Host 1 |
| `proxmox/network/interfaces-host2.example` | `/etc/network/interfaces` template for Host 2 | Host 2 |
| `proxmox/vm-windows/setup-gpu-passthrough.sh` | IOMMU + vfio-pci for RX 6800 XT | Host 1 |
| `proxmox/vm-windows/create-windows-vm.sh` | Windows 11 VM with GPU passthrough | Host 1 |
| `proxmox/vm-linux-desktop/create-linux-desktop-vm.sh` | Linux Desktop VM (SPICE/QXL) | Host 1 or 2 |
| `proxmox/vm-templates/setup-storage.sh` | Storage backends (local-lvm, NFS, ZFS) | Both hosts |
| `proxmox/vm-templates/create-cloud-init-template.sh` | Cloud-Init base template (VMID 9000) | Both hosts |
| `proxmox/remote-access/connect-rdp.sh` | RDP to Windows VM | ThinkPad |
| `proxmox/remote-access/connect-spice.sh` | SPICE to Linux VM via Proxmox API | ThinkPad |
| `proxmox/remote-access/setup-thinkpad-routes.sh` | Route 192.168.20.0/24 on ThinkPad | ThinkPad |
| `proxmox/fileserver/setup-samba.sh` | Samba server in Linux VM | Linux VM (200) |
| `proxmox/fileserver/mount-share-thinkpad.sh` | Mount CIFS shares on ThinkPad | ThinkPad |
| `proxmox/backup/vzdump-backup.sh` | vzdump backup for all VMs/CTs | Both hosts |
| `proxmox/backup/install-backup-cronjob.sh` | Cron job for automated backups | Both hosts |
| `proxmox/gpu/gpu-check.sh` | GPU passthrough readiness diagnostics | Host 1 |

### Systemd Services and Daemons

| Service | Configured By | Host/VM | Action |
|---------|--------------|---------|--------|
| `sshd` | `harden-ssh.sh` | Both hosts | Restart after hardening |
| `fail2ban` | `setup-fail2ban.sh` | Both hosts | Enable + start |
| `smbd` | `setup-samba.sh` | Linux VM (200) | Enable + restart |
| `nmbd` | `setup-samba.sh` | Linux VM (200) | Enable + restart |
| `pvedaemon` | `setup-fail2ban.sh` (monitored) | Both hosts | Monitored by Fail2Ban |
| `netfilter-persistent` | `setup-nat.sh` | Both hosts | Save iptables rules |

### Timers and Cron Jobs

| Schedule | Script | Description | Log File |
|----------|--------|-------------|----------|
| `0 2 * * *` (daily 02:00) | `vzdump-backup.sh` | Full VE backup of all VMs/CTs | `/var/log/proxmox-backup-cron.log` |
| `0 3 * * 0` (weekly Sunday 03:00) | `vzdump-backup.sh` | Alternative weekly schedule | `/var/log/proxmox-backup-cron.log` |
| Cron file: `/etc/cron.d/proxmox-backup` | `install-backup-cronjob.sh` | Installer for above schedules | — |

### Deploy Scripts / CI/CD

| Workflow | File | Trigger | Purpose |
|----------|------|---------|---------|
| Lint | `.github/workflows/lint.yml` | PR to any branch | Run `npm run lint` + `npm run format:check` |
| Release Docker Image | `.github/workflows/release.yml` | Push to `main` or manual dispatch | Build and push `docker/dockerhub-mcp:{version}` to Docker Hub |
| Scorecard | `.github/workflows/scorecard.yml` | Push to `main`, weekly schedule | OSSF supply-chain security analysis |
| Tools List | `.github/workflows/tools-list.yml` | PR to any branch | Verify tools list is up to date |

**Docker image**: `docker/dockerhub-mcp` — multi-platform (`linux/amd64`, `linux/arm64`), built with SBOM and provenance attestation.

### Logging Strategy

| Component | Log Target | Details |
|-----------|-----------|---------|
| vzdump backups | `/var/log/vzdump-backup-YYYYMMDD-HHMMSS.log` | Per-run timestamped logs, auto-cleaned after 30 days |
| Backup cron | `/var/log/proxmox-backup-cron.log` | Cron job output |
| Fail2Ban SSH | systemd journal (`sshd.service`) | Monitored for brute-force attempts |
| Fail2Ban PVE | systemd journal (`pvedaemon.service`) | Monitored for web GUI auth failures |
| MCP Server | Winston logger (stdout) | Application-level logging via `winston` |

### Storage Backends

| Storage ID | Type | Content Types | Volume Group / Path |
|------------|------|---------------|---------------------|
| `local-lvm` | LVM thin pool | `rootdir`, `images` | VG: `pve`, pool: `data` |
| `local` | Directory | `iso`, `vztmpl`, `backup`, `snippets` | `/var/lib/vz/template/iso` |
| `nfs-shared` (optional) | NFS | `images`, `iso`, `backup`, `vztmpl` | Server: `192.168.1.100:/export/pve-storage` |
| `local-zfs` (optional) | ZFS | `rootdir`, `images` | Pool: `rpool/data` |

### Firewall Rules (Cluster-Level)

| Direction | Protocol | Port(s) | Source | Action |
|-----------|----------|---------|--------|--------|
| IN | ICMP | — | any | ACCEPT |
| IN | TCP | 22 | any | ACCEPT (SSH) |
| IN | TCP | 8006 | any | ACCEPT (PVE GUI) |
| IN | TCP | 3128 | any | ACCEPT (SPICE) |
| IN | TCP | 5900-5999 | any | ACCEPT (VNC) |
| IN | UDP | 5405-5412 | any | ACCEPT (Corosync) |
| IN | TCP | 60000-60050 | any | ACCEPT (Live migration) |
| IN | * | * | any | DROP (default policy) |

### Samba Shares (Linux VM 192.168.20.20)

| Share Name | Local Path | Permissions |
|------------|-----------|-------------|
| `projects` | `/srv/projects/projects` | Read/write |
| `documents` | `/srv/projects/documents` | Read/write |
| `backups` | `/srv/projects/backups` | Read/write |

### Mount Points (ThinkPad)

| Mount Point | Remote Source | Type | Credentials |
|-------------|-------------|------|-------------|
| `/mnt/projects` | `//192.168.20.20/projects` | CIFS | `/root/.smbcredentials` |
| `/mnt/documents` | `//192.168.20.20/documents` | CIFS | `/root/.smbcredentials` |
| `/mnt/backups` | `//192.168.20.20/backups` | CIFS | `/root/.smbcredentials` |

---

## C) DOCUMENT MAP

| Document Path | Describes | Related Services | Related Host |
|---------------|-----------|-----------------|--------------|
| `README.md` | Docker Hub MCP Server: setup, authentication, usage with Claude Desktop, VS Code, Gordon | MCP Server (Node.js), Docker | Application-level (any) |
| `docs/proxmox-setup.md` | Full Proxmox cluster IaC: network, GPU, VMs, access, backups | All Proxmox services, vzdump, Samba, SPICE, RDP | Host 1, Host 2, ThinkPad |
| `CONTRIBUTING.md` | Contribution guidelines, code style, PR process | GitHub Actions CI | Application-level |
| `SECURITY.md` | Vulnerability disclosure policy | — | Application-level |
| `CODE_OF_CONDUCT.md` | Community conduct standards | — | Application-level |
| `.github/pull_request_template.md` | PR template for contributors | GitHub Actions | Application-level |
| `proxmox/network/interfaces-host1.example` | Network interface config for Host 1 | vmbr0, vmbr1, iptables NAT | Host 1 (192.168.16.2) |
| `proxmox/network/interfaces-host2.example` | Network interface config for Host 2 | vmbr0, vmbr1, iptables NAT | Host 2 (192.168.16.3) |

---

## D) NEXT ACTIONS

### Unresolved Setup Tasks

- [ ] **GPU passthrough reboot**: `setup-gpu-passthrough.sh` requires a reboot of Host 1 after execution — no automation exists for post-reboot verification
- [ ] **Windows VM post-install**: VirtIO guest tools, AMD GPU drivers, Remote Desktop enablement, and static IP configuration (`192.168.20.10/24`) are manual steps inside the VM
- [ ] **Linux VM post-install**: `ubuntu-desktop` and `spice-vdagent` installation requires SSH into VM after first boot — not automated
- [ ] **Samba password**: `smbpasswd -a smbuser` is interactive — no unattended provisioning exists
- [ ] **ThinkPad route persistence**: Route to `192.168.20.0/24` must be manually persisted via `/etc/network/interfaces` or NetworkManager — no single-command persistent setup
- [ ] **CIFS credentials file**: `/root/.smbcredentials` must be manually created with username/password on ThinkPad
- [ ] **Cloud-Init template default credentials**: Template uses `admin`/`changeme` — needs post-deployment credential rotation
- [ ] **Host 2 GPU passthrough**: No script exists for GTX 1080 passthrough on Host 2 (only RX 6800 XT on Host 1 is scripted)

### Missing Automation Pieces

- [ ] **No systemd service for MCP server**: The Docker Hub MCP server has no systemd unit file or process manager configuration for production deployment on the hosts
- [ ] **No systemd timer for backups**: Backups use raw cron (`/etc/cron.d/proxmox-backup`) instead of systemd timers — no structured logging integration
- [ ] **No Ansible/Terraform orchestration**: All scripts are standalone bash — no orchestration layer to run the full 6-phase deployment end-to-end
- [ ] **No monitoring/alerting**: No Prometheus, Grafana, or alerting stack for host health, VM status, or backup success verification
- [ ] **No automated testing**: Infrastructure scripts have no validation suite or dry-run mode
- [ ] **No NFS/ZFS storage automation**: NFS and ZFS backends are commented out in `setup-storage.sh` — not deployed
- [ ] **No Docker Compose for MCP server**: Only a `Dockerfile` exists; no `docker-compose.yml` for local development or multi-service deployment
- [ ] **No SSL/TLS certificate management**: No Let's Encrypt or certificate provisioning for Proxmox Web GUI or MCP server

### Potential Infrastructure Risks

- [ ] **Default credentials in scripts**: Cloud-Init templates use `admin`/`changeme`; Samba user created with no password policy enforcement
- [ ] **Shared vmbr1 gateway IP**: Both hosts configure `vmbr1` as `192.168.20.1/24` — if both are active simultaneously, IP conflict will occur on the VM network
- [ ] **No HA/failover**: VMs are pinned to specific hosts; no Proxmox HA group or automatic failover configured
- [ ] **Firewall allows SSH from any source**: Cluster firewall accepts SSH (port 22) from any IP — should be restricted to management subnet
- [ ] **Backup retention is minimal**: Default `keep-last=3` with no offsite replication or backup verification
- [ ] **No disk encryption**: No LUKS or ZFS encryption configured for VM storage or host disks
- [ ] **Single-point network gateway**: All VM traffic NATs through the host's `vmbr0` — no redundant path
- [ ] **Proxmox GUI exposed broadly**: Port 8006 is open to all sources in cluster firewall rules

---

## E) APPENDIX — MCP Server Summary

| Attribute | Value |
|-----------|-------|
| Name | `dockerhub-mcp-server` |
| Version | `1.0.0` |
| Runtime | Node.js >= 22 |
| Language | TypeScript |
| Transport | `stdio` (default) or `http` |
| Default Port | `3000` |
| Auth | `HUB_PAT_TOKEN` env var + `--username` flag |
| Docker Image | `docker/dockerhub-mcp:{version}` |
| Entry Point | `dist/index.js` |
| Key Dependencies | `@modelcontextprotocol/sdk`, `express`, `winston`, `zod`, `jwt-decode` |
| Build | `npm install && npm run build` (TypeScript → `dist/`) |
| Lint | `npm run lint` (ESLint) |
| Format | `npm run format:check` / `npm run format:fix` (Prettier) |
| License | Apache 2.0 |
