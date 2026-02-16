# CLAUDE.md

> Project init file — gives Claude and developers immediate orientation when entering this repo.

## What This Repo Is

This repository has two purposes:

1. **Docker Hub MCP Server** — A Node.js/TypeScript Model Context Protocol server for Docker Hub API access (image discovery, repository management via LLMs).
2. **FitnaAI Proxmox Infrastructure-as-Code** — Multi-host Proxmox VE cluster with GPU passthrough, VM management, AI stack deployment, and systemd-based automation.

## Architecture at a Glance

```
Hosts:
  pve (192.168.16.2)        Primary — RX 6800 XT, Omarchy SSD, Samba, VMs 100/110
  pve-ryzen (192.168.17.1)  Services — GTX 1080, Docker, Ollama, 24/7 APIs
  ThinkPad (192.168.16.7)   Client — admin workstation, CIFS mounts

Network: 192.168.0.0/16 flat LAN (all hosts on vmbr0, no vmbr1 active)

AI Stack (Docker on pve-ryzen):
  jbot-api (FastAPI) -> Ollama (ROCm/GPU) + Qdrant (vectors) + Redis (cache)
  Traefik (reverse proxy, TLS) | Prometheus + Grafana (monitoring)
  Docker networks: jbot-internal (isolated), jbot-proxy (external via Traefik)

Deployment (on target hosts):
  /home/admin/projects/FItnaai/
    scripts/fitna_auto_setup.sh    Hardened auto-setup
    scripts/fitna_watchdog.sh      Mount/disk/GPU/Docker/git-lock checks (minutely)
    scripts/fitna_deploy.sh        Idempotent installer (sudo)
    deploy/fitna-setup.service     systemd oneshot (After=network-online.target)
    deploy/fitna-watchdog.service  systemd oneshot for timer
    deploy/fitna-watchdog.timer    Minutely, OnBootSec=2min
    deploy/fitna-logrotate         Daily, 14 days, compress, copytruncate
```

## Critical Rules

**Host-level scripts (Proxmox VE):**
- NO sudo — all infrastructure scripts run as root directly
- Deterministic, idempotent deployments
- Always snapshot before infrastructure changes

**VM-level:** sudo allowed with hardening recommendations.
**Client-level:** sudo allowed for admin tasks with logging.

## Key Files

| Path | What |
|------|------|
| `PROJECT_OVERVIEW.md` | Full infrastructure inventory, host details, network topology, maturity scores |
| `docs/proxmox-setup.md` | Proxmox cluster setup guide (phases 1-6) |
| `docs/infrastructure-analysis.md` | Strategic analysis: maturity 2.5/5, risk register, 12-month roadmap |
| `docs/security-compliance.md` | Zero Trust gaps, DSGVO/AI Act requirements, encryption plan |
| `docs/roadmap-90day.md` | 25-step tactical plan for pilot-customer readiness |
| `proxmox/validate-phase4.sh` | Validation gate: SSD mount + Samba check with auto-retry |
| `proxmox/network/` | NAT, firewall, SSH hardening, Fail2Ban scripts |
| `proxmox/vm-windows/` | GPU passthrough + Windows VM creation |
| `proxmox/vm-templates/` | Cloud-Init template (VMID 9000) |
| `proxmox/fileserver/` | Samba setup (fitna-shared on Omarchy SSD) |
| `proxmox/backup/` | vzdump + cron-based backup + user data rsync to pve-ryzen |
| `docs/backup-runbook.md` | Backup runbook: Omarchy SSD → pve-ryzen 2TB HDD, restore procedures |
| `src/` | MCP server TypeScript source |

## Current Maturity

| Dimension | Score |
|-----------|-------|
| Infrastructure | 2.5/5 |
| Security | 2/5 |
| AI-Readiness (tech) | 6/10 |
| AI-Readiness (commercial) | 2/10 |
| Automation | ~3.5/5 (improved with systemd units + watchdog) |

## Top Risks (act on these)

1. **Backup partially addressed** — rsync script created (→ pve-ryzen 2TB HDD), restore drill still pending
2. **No DSGVO docs** — VVT, TOMs, AV contracts missing (blocks customer ops)
3. **Proxmox Web-UI** — no MFA
4. **jbot-api** — no authentication
5. **Bus factor = 1** — no runbooks, no password safe

## Build & Run (MCP Server)

```bash
npm install && npm run build
npm start -- [--transport=http|stdio] [--port=3000]

# With Docker Hub auth:
HUB_PAT_TOKEN=<token> npm start -- --username=<user>
```

## Deploy (Infrastructure)

```bash
# On target host (pve or pve-ryzen):
cd /home/admin/projects/FItnaai
sudo bash scripts/fitna_deploy.sh

# Validation gate (pve only):
bash proxmox/validate-phase4.sh
```

## Conventions

- Commit messages: imperative, short first line, detail in body
- Infrastructure scripts: bash, no sudo on host, idempotent
- Branch naming: `claude/<description>-<id>` for Claude sessions
- PRs: use `.github/pull_request_template.md`
