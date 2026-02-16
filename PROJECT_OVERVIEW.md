# PROJECT OVERVIEW — Infrastructure Master Summary

> **Revision 3** — Updated with full infrastructure, security, and compliance analysis.
> Previous revision was based solely on script defaults. This revision reflects actual host IPs,
> subnet mask (/16), corrected hostnames, and operational state as verified against running systems.
>
> **Maturity Scores (assessed):**
> Infrastructure: 2.5/5 | Security: 2/5 | AI-Readiness: 6/10 tech, 2/10 commercial
>
> **Related analysis documents:**
> - [Infrastructure Analysis](docs/infrastructure-analysis.md) — Full strategic analysis, risk register, architecture roadmap
> - [Security & Compliance](docs/security-compliance.md) — Zero Trust gaps, DSGVO (GDPR), EU AI Act requirements
> - [90-Day Tactical Plan](docs/roadmap-90day.md) — Prioritized action items for pilot-customer readiness

---

## A) GLOBAL PROJECT STATUS

This repository serves a dual purpose:

1. **Docker Hub MCP Server** — A Node.js/TypeScript Model Context Protocol server that interfaces with Docker Hub APIs for LLM-powered container image discovery and repository management.
2. **Proxmox Infrastructure-as-Code ("Fitna-Infrastruktur")** — A multi-host Proxmox VE cluster with GPU passthrough, VM management, remote access, shared storage, and file sharing.

### Host Inventory (Verified)

#### Host 16.2 — `pve` (Primary Storage Node)

| Attribute | Value |
|-----------|-------|
| Hostname | `pve` |
| IP Address | `192.168.16.2/16` |
| Role | Primary Storage Authority + Windows Workstation + AI models |
| GPU | AMD RX 6800 XT (16 GB, Navi 21) |
| Bridge | `vmbr0` (192.168.16.2/16) |
| Active VMs | VMID 100 (Ubuntu, active — `tap100i0` present) |
| Planned VMs | VMID 110 (`win10-reference`, Windows 10 reference client) |
| Storage | **Omarchy SSD** (M.2, ext4) mounted at `/mnt/omarchy` — Data Authority |
| Samba Export | `[fitna-shared]` → `/mnt/omarchy/home/fitna` |
| OS | Proxmox VE 7.x / 8.x |
| Status | Operational. VM 100 running. GPU passthrough pending reboot. |

#### Host 17.1 — `pve-ryzen` (Docker/Services Node)

| Attribute | Value |
|-----------|-------|
| Hostname | `pve-ryzen` |
| IP Address | `192.168.17.1/16` |
| Role | Docker + Ollama + 24/7 services |
| GPU | NVIDIA GTX 1080 (8 GB) |
| Bridge | `vmbr0` (192.168.17.1/16) |
| Active Services | Docker environment (bridge `br-6beede98b857` active) |
| Access | SSH + Portainer |
| OS | Proxmox VE 7.x / 8.x |
| Status | Operational. Docker stack running. |

#### Host 16.7 — ThinkPad (Client)

| Attribute | Value |
|-----------|-------|
| Hostname | ThinkPad |
| IP Address | `192.168.16.7/16` |
| Role | Client workstation (RDP/SPICE access to VMs, Samba mounts) |
| Bridge | `vmbr0` (192.168.16.7/16) |
| Mounts | `/mnt/fitna` via CIFS from 192.168.16.2 |
| Status | Operational. |

### Network Topology (Verified)

```
Subnet: 192.168.0.0/16 (all hosts reachable — flat /16)

┌─────────────────────────────────────────────────────────────────────┐
│  192.168.0.0/16 — Flat LAN                                         │
│                                                                     │
│  ┌──────────────────────┐  ┌──────────────────────┐                │
│  │ pve                  │  │ pve-ryzen             │                │
│  │ 192.168.16.2/16      │  │ 192.168.17.1/16       │                │
│  │ vmbr0                │  │ vmbr0                 │                │
│  │ RX 6800 XT (16 GB)   │  │ GTX 1080 (8 GB)       │                │
│  │                      │  │                       │                │
│  │ VM 100 (Ubuntu)      │  │ Docker (br-6beede*)   │                │
│  │ VM 110 (win10) [WIP] │  │ Ollama, APIs          │                │
│  │                      │  │                       │                │
│  │ Omarchy SSD (/mnt/   │  │                       │                │
│  │   omarchy) [Auth]    │  │                       │                │
│  │ Samba: fitna-shared  │  │                       │                │
│  └──────────┬───────────┘  └──────────┬────────────┘                │
│             │                         │                             │
│  ┌──────────┴──────────────────────────┴────────────┐               │
│  │ ThinkPad                                         │               │
│  │ 192.168.16.7/16                                  │               │
│  │ CIFS mounts from 16.2                            │               │
│  └──────────────────────────────────────────────────┘               │
└─────────────────────────────────────────────────────────────────────┘

NOTE: vmbr1 is NOT present on any host in the current live state.
The previously documented 192.168.20.0/24 VM-Netz is not active.
All VM traffic flows through vmbr0 on the flat /16.
```

### Network Assessment

| Finding | Severity | Detail |
|---------|----------|--------|
| /16 subnet in homelab | LOW | Broadcast domain covers 192.168.0.0–192.168.255.255. Functional but causes unnecessary broadcast overhead. Consider segmenting to /24 per host group. |
| No vmbr1 collision | RESOLVED | Previously documented vmbr1 IP conflict (both hosts at 192.168.20.1/24) is eliminated — vmbr1 does not exist on live systems. |
| Flat network, no segmentation | MEDIUM | All hosts and VMs share one L2 domain. No isolation between management, VM, and Docker traffic. |

### Virtual Machines

| VMID | Name | Host | Status | Type | Display | Notes |
|------|------|------|--------|------|---------|-------|
| 100 | (Ubuntu VM) | pve (16.2) | **RUNNING** | Ubuntu Linux | SPICE/Console | Active — `tap100i0` confirmed |
| 110 | win10-reference | pve (16.2) | **PLANNED** | Windows 10 | GPU (after passthrough) | Reference client for Samba validation |
| 200 | linux-desktop | pve (16.2) | Scripted | Ubuntu 22.04 | SPICE/QXL | 4 GB RAM, 4 cores, Cloud-Init |
| 9000 | ubuntu-2204-cloud | Any | Template | Ubuntu 22.04 | Serial | Cloud-Init base template |

---

## B) CENTRALIZED INFRASTRUCTURE

### Storage Authority

| Attribute | Value |
|-----------|-------|
| Authority Host | `pve` (192.168.16.2) |
| Device | Omarchy M.2 SSD |
| Filesystem | ext4 |
| Mount Point | `/mnt/omarchy` |
| Mount Method | systemd mount unit (`mnt-omarchy.mount`) |
| Initial Mode | `ro` (read-only for verification, then `rw`) |
| Samba Export | `/mnt/omarchy/home/fitna` → `[fitna-shared]` |
| Network Consumers | pve-ryzen (17.1), ThinkPad (16.7) via CIFS |

### Scripts

| Path | Purpose | Target Host |
|------|---------|-------------|
| `proxmox/network/setup-nat.sh` | NAT/MASQUERADE for VM subnet → WAN | pve (16.2) |
| `proxmox/network/setup-firewall.sh` | PVE cluster + host firewall rules | Both hosts |
| `proxmox/network/harden-ssh.sh` | SSH hardening (key-only, no root password) | Both hosts |
| `proxmox/network/setup-fail2ban.sh` | Fail2Ban for SSH + PVE Web GUI | Both hosts |
| `proxmox/network/interfaces-host1.example` | `/etc/network/interfaces` template (Host 16.2) | pve (16.2) |
| `proxmox/network/interfaces-host2.example` | `/etc/network/interfaces` template (Host 16.3 — **outdated**) | **Needs update for 17.1** |
| `proxmox/vm-windows/setup-gpu-passthrough.sh` | IOMMU + vfio-pci for RX 6800 XT | pve (16.2) |
| `proxmox/vm-windows/create-windows-vm.sh` | Windows 11 VM with GPU passthrough (VMID 100) | pve (16.2) |
| `proxmox/vm-windows/create-win10-reference.sh` | Windows 10 reference client (VMID 110) | pve (16.2) |
| `proxmox/vm-linux-desktop/create-linux-desktop-vm.sh` | Linux Desktop VM (SPICE/QXL) | pve (16.2) |
| `proxmox/vm-templates/setup-storage.sh` | Storage backends (local-lvm, NFS, ZFS) | Both hosts |
| `proxmox/vm-templates/create-cloud-init-template.sh` | Cloud-Init base template (VMID 9000) | Both hosts |
| `proxmox/remote-access/connect-rdp.sh` | RDP to Windows VM | ThinkPad (16.7) |
| `proxmox/remote-access/connect-spice.sh` | SPICE to Linux VM via Proxmox API | ThinkPad (16.7) |
| `proxmox/remote-access/setup-thinkpad-routes.sh` | Route VM subnet on ThinkPad | ThinkPad (16.7) |
| `proxmox/fileserver/setup-samba.sh` | Samba server (generic, in VM) | Linux VM |
| `proxmox/fileserver/setup-samba-fitna.sh` | Samba for Omarchy SSD fitna-shared | pve (16.2) |
| `proxmox/fileserver/mount-share-thinkpad.sh` | Mount CIFS shares on ThinkPad | ThinkPad (16.7) |
| `proxmox/backup/vzdump-backup.sh` | vzdump backup for all VMs/CTs | Both hosts |
| `proxmox/backup/install-backup-cronjob.sh` | Cron job for automated backups | Both hosts |
| `proxmox/gpu/gpu-check.sh` | GPU passthrough readiness diagnostics | pve (16.2) |
| `proxmox/validate-phase4.sh` | **Validierungs-Gate** — SSD-Mount + Samba-Check mit Auto-Retry | pve (16.2) |

### Systemd Units

| Unit | Type | Configured By | Host | Action |
|------|------|--------------|------|--------|
| `mnt-omarchy.mount` | mount | `proxmox/storage/mnt-omarchy.mount` | pve (16.2) | Mount Omarchy SSD |
| `sshd` | service | `harden-ssh.sh` | Both hosts | Restart after hardening |
| `fail2ban` | service | `setup-fail2ban.sh` | Both hosts | Enable + start |
| `smbd` | service | `setup-samba-fitna.sh` | pve (16.2) | Enable + restart |
| `nmbd` | service | `setup-samba-fitna.sh` | pve (16.2) | Enable + restart |
| `pvedaemon` | service | `setup-fail2ban.sh` (monitored) | Both hosts | Monitored by Fail2Ban |
| `netfilter-persistent` | service | `setup-nat.sh` | Both hosts | Save iptables rules |

### Timers and Cron Jobs

| Schedule | Script | Description | Log File |
|----------|--------|-------------|----------|
| `0 2 * * *` (daily 02:00) | `vzdump-backup.sh` | Full VE backup of all VMs/CTs | `/var/log/proxmox-backup-cron.log` |
| `0 3 * * 0` (weekly Sunday 03:00) | `vzdump-backup.sh` | Alternative weekly schedule | `/var/log/proxmox-backup-cron.log` |
| Cron file: `/etc/cron.d/proxmox-backup` | `install-backup-cronjob.sh` | Installer for above | — |

### Deploy Scripts / CI/CD

| Workflow | File | Trigger | Purpose |
|----------|------|---------|---------|
| Lint | `.github/workflows/lint.yml` | PR to any branch | `npm run lint` + `npm run format:check` |
| Release | `.github/workflows/release.yml` | Push to `main` / manual | Build `docker/dockerhub-mcp:{version}` |
| Scorecard | `.github/workflows/scorecard.yml` | Push to `main`, weekly | OSSF supply-chain security |
| Tools List | `.github/workflows/tools-list.yml` | PR to any branch | Verify tools list |

### Logging Strategy

| Component | Log Target | Details |
|-----------|-----------|---------|
| vzdump backups | `/var/log/vzdump-backup-YYYYMMDD-HHMMSS.log` | Auto-cleaned after 30 days |
| Backup cron | `/var/log/proxmox-backup-cron.log` | Cron job output |
| Fail2Ban SSH | systemd journal (`sshd.service`) | Brute-force monitoring |
| Fail2Ban PVE | systemd journal (`pvedaemon.service`) | Web GUI auth failures |
| MCP Server | Winston logger (stdout) | `winston` logging |

### Storage Backends

| Storage ID | Type | Content Types | Volume Group / Path |
|------------|------|---------------|---------------------|
| `local-lvm` | LVM thin pool | `rootdir`, `images` | VG: `pve`, pool: `data` |
| `local` | Directory | `iso`, `vztmpl`, `backup`, `snippets` | `/var/lib/vz/template/iso` |
| `omarchy` | ext4 (systemd mount) | Data authority | `/mnt/omarchy` on pve (16.2) |
| `nfs-shared` (optional) | NFS | `images`, `iso`, `backup`, `vztmpl` | Not deployed |
| `local-zfs` (optional) | ZFS | `rootdir`, `images` | Not deployed |

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

### Samba Shares (pve 192.168.16.2)

| Share Name | Local Path | Valid Users | Permissions |
|------------|-----------|-------------|-------------|
| `fitna-shared` | `/mnt/omarchy/home/fitna` | `fitna-user` | Read/write, `force create mode 0660`, `force directory mode 0770` |

### Mount Points (ThinkPad 16.7 / pve-ryzen 17.1)

| Mount Point | Remote Source | Type | Credentials |
|-------------|-------------|------|-------------|
| `/mnt/fitna` | `//192.168.16.2/fitna-shared` | CIFS | Credentials file (chmod 600) |

---

## C) DOCUMENT MAP

| Document Path | Describes | Related Services | Related Host |
|---------------|-----------|-----------------|--------------|
| `README.md` | Docker Hub MCP Server: setup, auth, Claude Desktop, VS Code, Gordon | MCP Server, Docker | Application-level |
| `docs/proxmox-setup.md` | Full Proxmox cluster IaC (original plan, partially outdated IPs) | All Proxmox services | pve, pve-ryzen, ThinkPad |
| `CONTRIBUTING.md` | Contribution guidelines, code style, PR process | GitHub Actions CI | Application-level |
| `SECURITY.md` | Vulnerability disclosure policy | — | Application-level |
| `CODE_OF_CONDUCT.md` | Community conduct standards | — | Application-level |
| `.github/pull_request_template.md` | PR template | GitHub Actions | Application-level |
| `proxmox/network/interfaces-host1.example` | Network interface config for pve | vmbr0, iptables | pve (16.2) |
| `proxmox/network/interfaces-host2.example` | Network interface config (**outdated — says 16.3, actual is 17.1**) | vmbr0, iptables | pve-ryzen (17.1) |
| `proxmox/storage/mnt-omarchy.mount` | Systemd mount for Omarchy SSD | systemd | pve (16.2) |
| `proxmox/fileserver/setup-samba-fitna.sh` | Samba config for fitna-shared | smbd, nmbd | pve (16.2) |
| `proxmox/vm-windows/create-win10-reference.sh` | Windows 10 reference VM (VMID 110) | qemu | pve (16.2) |
| `proxmox/validate-phase4.sh` | Phase 4 Validierungs-Gate mit Auto-Retry | systemd, smbd | pve (16.2) |

---

## D) NEXT ACTIONS

### Phase Gate: Validierungs-Gate (Current Blocker)

Before proceeding to Phase 4 (GPU-Passthrough), run the automated gate script:

```bash
sudo bash proxmox/validate-phase4.sh
```

The script performs two checks with exponential backoff auto-retry (3s → 6s → 12s → 24s → 48s, max 60s cap):

| Check | Validates | Pass Condition |
|-------|-----------|----------------|
| SSD-Mount | `systemctl start mnt-omarchy.mount` | `/mnt/omarchy` is a mountpoint and readable |
| Samba-Share | TCP:445 + `smbclient -L` listing | `fitna-shared` appears in share listing on 192.168.16.2 |

Options: `--max-retries N` (default: 5), `--timeout S` (default: 180s)

- [ ] **Mount-Check**: Omarchy SSD visible at `/mnt/omarchy` on pve (16.2)
- [ ] **Referenz-Check**: Samba-Share `fitna-shared` erreichbar auf 192.168.16.2

### Unresolved Setup Tasks

- [ ] **Omarchy SSD UUID**: `mnt-omarchy.mount` requires the real UUID from `blkid` — placeholder `DEINE-UUID-AUS-BLKID` must be replaced
- [ ] **Omarchy ro → rw transition**: Initial mount is read-only for safety; must verify data integrity before switching to `rw`
- [ ] **Samba user creation**: `fitna-user` must be created with `useradd -M -s /usr/sbin/nologin fitna-user && smbpasswd -a fitna-user` (interactive)
- [ ] **GPU passthrough reboot**: `setup-gpu-passthrough.sh` requires reboot of pve (16.2) — no post-reboot verification automation
- [ ] **Windows VM 110 post-install**: VirtIO drivers, network config, RDP enablement are manual in-VM steps
- [ ] **Ubuntu VM 100 GPU passthrough**: RX 6800 XT passthrough for VM 100 is the next phase target after validation gate passes
- [ ] **interfaces-host2.example outdated**: Still references 192.168.16.3 — must be updated to 192.168.17.1 for pve-ryzen
- [ ] **Cloud-Init default credentials**: Template uses `admin`/`changeme` — requires post-deployment rotation

### Missing Automation Pieces

- [ ] **No orchestration layer**: All scripts are standalone bash — no Ansible/Terraform for end-to-end deployment
- [ ] **No monitoring/alerting**: No Prometheus, Grafana, or alerting for host health, VM status, backup verification
- [ ] **No systemd timer for backups**: Uses raw cron instead of systemd timers
- [ ] **No NFS/ZFS storage deployed**: Commented out in `setup-storage.sh`
- [ ] **No SSL/TLS certificate management**: No Let's Encrypt for PVE Web GUI or MCP server

### Potential Infrastructure Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| /16 subnet broadcast overhead | LOW | Segment to /24 per host group when traffic grows |
| Default credentials in scripts | HIGH | Rotate immediately after deployment; enforce password policy |
| No HA/failover | MEDIUM | VMs pinned to specific hosts; no Proxmox HA groups |
| Firewall allows SSH from any source | HIGH | Restrict port 22 to management subnet (192.168.16.0/24) |
| Backup retention minimal (keep-last=3) | MEDIUM | Add offsite replication; implement backup verification |
| No disk encryption | MEDIUM | Consider LUKS or ZFS encryption for sensitive data |
| Proxmox GUI exposed broadly (8006) | HIGH | Restrict to management subnet |
| Omarchy SSD single point of failure | HIGH | No backup strategy for authority data yet |

---

## E) MATURITY & RISK SUMMARY

### Infrastructure Maturity (2.5/5)

| Dimension | Score | Key Gap |
|-----------|-------|---------|
| Provisioning | 3/5 | Missing: versioning, automated testing |
| Backup & Recovery | 2/5 | No restore test, no offsite, no encryption |
| Monitoring | 1.5/5 | Defined but not operational, no alerting |
| Network | 2.5/5 | Docker isolation good; host/VM layer flat /16 |
| Security | 2/5 | No MFA, no IDS, no encryption at rest |
| Documentation | 1.5/5 | No runbooks, no policies, no architecture diagram |
| Automation | 2.5/5 | No CI/CD, no automated tests |

### Top 5 Risks

| Risk | Severity | Immediate Action |
|------|----------|-----------------|
| Backup untested (no restore drill) | CRITICAL | Run restore test this week |
| No DSGVO documentation (VVT, TOMs, AV) | CRITICAL | Create before any customer engagement |
| Proxmox Web-UI without MFA | HIGH | Activate TOTP |
| jbot-api has no authentication | HIGH | Implement API key auth before pilot |
| Bus factor = 1 (Jonas) | HIGH | Password safe + runbooks |

### Critical Path to Pilot Readiness

```
Week 1-4:  Stability + Security (restore test, MFA, auditd, Samba hardening)
Week 5-8:  Compliance + Docs (VVT, TOMs, AV template, runbooks)
Week 9-12: AI Enablement + Pilot (API auth, Qdrant backup, customer onboarding)
```

See [90-Day Tactical Plan](docs/roadmap-90day.md) for full details.

---

## F) APPENDIX — MCP Server Summary

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
| Build | `npm install && npm run build` |
| License | Apache 2.0 |
