# ADR-002: Infrastructure Topology — Resolved

**Status:** Accepted
**Date:** 2026-02-12
**Decision makers:** Projektleitung + Operator

## Context

Screenshots from the Proxmox mobile app revealed a more complex topology than originally assumed. Four blockers were identified. All have been resolved.

## Blocker Resolutions

| Blocker | Question | Answer |
|---------|----------|--------|
| B1 | Is 192.168.16.7 a Proxmox node? | **Yes** — Lenovo ThinkPad running PVE. Role: Dev/Test node. No production traffic. |
| B2 | pve-ryzen NIC topology? | **1 physical NIC.** Dual IP is artifact, not VLAN separation. |
| B3 | Production compute host? | **192.168.16.2** (GamingPC). Docker + fitnaai run here. |
| B4 | Public API? | **Yes** — via Hetzner VPS only. WireGuard tunnel to 16.2. No direct exposure. |

## Consequences

### Production on 192.168.16.2 (GamingPC)
- This host runs: Proxmox + Windows VM + Docker + fitnaai + Ollama
- **Risk acknowledged**: Single point of failure for all workloads
- **Mitigation**: Systemd service wrapper, automated restarts, vzdump backups
- **Scaling path**: Migrate prod services to ryzen or dedicated node later

### GPU Reality
- RX 6800 XT = AMD = **no CUDA** = Ollama runs CPU-only on this host
- GTX 1080 on ryzen could provide GPU inference later (when ryzen becomes prod)
- CPU inference is acceptable for Phase 1 (Startup)

### Public Access Architecture
- 192.168.16.2 is NEVER directly exposed to the internet
- Hetzner VPS acts as public entry point
- WireGuard tunnel connects VPS to 16.2
- Nginx on VPS reverse-proxies to fitnaai via tunnel

### 192.168.16.7 (ThinkPad PVE)
- Dev/test environment only
- Not part of production cluster
- Can be used for staging/testing fitnaai before deploying to 16.2

## Feature Freeze: LIFTED

All blockers resolved. Phase 6 (Production Deployment) and Phase 7 (VPS + Public Access) are now unblocked.
