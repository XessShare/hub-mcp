# 07 — Phase 6: Let's Encrypt Staging → Production

## Overview

Phase 6 switches Traefik from Let's Encrypt **Staging** certificates (untrusted, for testing) to **Production** certificates (trusted, browser-accepted).

This is a **low-resource but high-risk** operation:
- No significant CPU/RAM/GPU impact
- **LE Production rate limits apply** once switched
- Rollback requires config restore or Proxmox snapshot

## Rate Limits (Let's Encrypt Production)

| Limit | Value |
|-------|-------|
| Certificates per registered domain | 50 per week |
| Duplicate certificates | 5 per week |
| New orders per account | 300 per 3 hours |
| Failed validations | 5 per hour per domain |

**Best practice:** Get everything right on Staging first. You get one clean shot at Production per domain per week.

---

## Pre-Flight Checklist

Run on the host where Traefik is deployed:

```bash
./proxmox/phase6-letsencrypt/preflight-phase6.sh
# or with custom Traefik directory:
./proxmox/phase6-letsencrypt/preflight-phase6.sh --traefik-dir /opt/traefik
```

### What it checks:

| # | Check | Gate |
|---|-------|------|
| 1 | RAM available | >= 8GB free |
| 2 | CPU load (5-min) | <= 2.0 |
| 3 | Disk space on / | >= 5GB free |
| 4 | Docker daemon | Active + responding |
| 5 | Container health | No restart loops |
| 6 | GPU status | nvidia-smi output (informational) |
| 7 | Traefik config | Exists + currently on staging |
| 8 | acme.json | Exists + permissions 600 |
| 9 | Traefik container | Running |
| 10 | DNS resolution | Domains resolve |
| 11 | LE Production API | Reachable |

### Additional display:
- `pveversion` — Proxmox version
- `free -h` — Full memory breakdown
- `df -h` — Disk usage
- `nvidia-smi` — GPU VRAM and temperature
- `docker ps` — Running containers

---

## Execution

### Step 0: Proxmox Snapshot (MANDATORY)

```bash
# VM
qm snapshot <VMID> pre-phase6 --description "Before LE Production switch"

# LXC Container
pct snapshot <CTID> pre-phase6 --description "Before LE Production switch"
```

### Step 1: Run Pre-Flight

```bash
./proxmox/phase6-letsencrypt/preflight-phase6.sh --traefik-dir /opt/traefik
```

Must show **GO** or **CONDITIONAL GO** before proceeding.

### Step 2: Switch to Production

```bash
./proxmox/phase6-letsencrypt/switch-to-production.sh /opt/traefik
```

The script will:
1. Verify Traefik is on staging
2. Back up `traefik.yml` + `acme.json` to `backups/phase6-<timestamp>/`
3. Stop Traefik
4. Change `caServer` from staging to production URL
5. Delete staging `acme.json` (staging certs are worthless)
6. Create fresh `acme.json` with `chmod 600`
7. Start Traefik
8. Wait up to 60s for certificate issuance
9. Report status

### Step 3: Verify

```bash
# Check certificate in browser — padlock should show "Let's Encrypt" (not "STAGING")

# Or via CLI:
echo | openssl s_client -connect yourdomain.com:443 -servername yourdomain.com 2>/dev/null \
  | openssl x509 -noout -issuer -dates

# Expected issuer:
#   issuer= /C=US/O=Let's Encrypt/CN=R3
# NOT:
#   issuer= /CN=FAKE LE Intermediate X1
```

---

## Rollback

### Option A: Script Rollback (restores config + acme.json)

```bash
./proxmox/phase6-letsencrypt/switch-to-production.sh --rollback /opt/traefik
```

This restores the most recent backup from `backups/phase6-*/`.

### Option B: Proxmox Snapshot (full system restore)

```bash
# VM
qm rollback <VMID> pre-phase6

# LXC
pct rollback <CTID> pre-phase6
```

---

## Troubleshooting

### Certificate not issued after 60 seconds

```bash
# Check Traefik logs
docker logs traefik --tail 50

# Common causes:
# 1. Port 80 not reachable from internet (HTTP-01 challenge)
# 2. DNS not pointing to this server
# 3. Rate limit reached
```

### Rate limit hit

```
too many certificates already issued for exact set of domains
```

**Wait 7 days** or use a different (sub)domain. Check current limits at:
https://crt.sh/?q=yourdomain.com

### acme.json permission error

```bash
chmod 600 /opt/traefik/acme.json
# Traefik refuses to start if acme.json is world-readable
```

### Traefik won't start after switch

```bash
# Check config syntax
docker run --rm -v /opt/traefik/traefik.yml:/traefik.yml traefik:latest traefik --configFile=/traefik.yml --api.dashboard=false 2>&1 | head -20

# Or rollback
./proxmox/phase6-letsencrypt/switch-to-production.sh --rollback /opt/traefik
```

---

## Resource Management Note

If the Windows VM on Host 1 is active during Phase 6, consider:

```bash
# Reduce Ollama loaded models on Host 2 (if sharing resources)
# In ai-host2.yml or .env:
OLLAMA_MAX_LOADED_MODELS=1
```

Phase 6 itself is lightweight (config swap + API call to LE), but if Traefik runs on the same host as other services, ensure Docker has enough headroom.

---

## Architecture After Phase 6

```
Internet
    │
    └── DNS → Your Server (Port 80/443)
              │
              └── Traefik (reverse proxy)
                    │
                    ├── acme.json (PRODUCTION certificates)
                    │     └── caServer: acme-v02.api.letsencrypt.org
                    │
                    ├── *.yourdomain.com → Services
                    │     ├── Ollama API
                    │     ├── JBOT API
                    │     ├── Qdrant
                    │     └── Other services
                    │
                    └── Automatic renewal (every 60-90 days)
```

---

## File Inventory

| File | Location | Purpose |
|------|----------|---------|
| `preflight-phase6.sh` | `proxmox/phase6-letsencrypt/` | Resource gates + readiness checks |
| `switch-to-production.sh` | `proxmox/phase6-letsencrypt/` | Staging → Production switch + rollback |
| This document | `docs/07-phase6-letsencrypt.md` | Phase 6 documentation |
