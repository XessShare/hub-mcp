# ADR-003: Recommended Target Architecture

**Status:** Proposed (pending blocker resolution, see ADR-002)
**Date:** 2026-02-12
**Decision makers:** Projektleitung

## Context

Based on the known hardware and the API-first decision (ADR-001), this is the recommended production architecture once blockers are resolved.

## Proposed Architecture

```
┌─────────────────────────────────────────────────────────┐
│  pve (192.168.16.2) — Workstation Node                   │
│  GPU: RX 6800 XT (16GB VRAM)                            │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │ VM 100: win11-workstation                        │    │
│  │ Purpose: Windows Desktop, Business, Dev          │    │
│  │ GPU: RX 6800 XT (passthrough)                    │    │
│  │ Access: RDP from ThinkPad                        │    │
│  └─────────────────────────────────────────────────┘    │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │ VM 200: linux-desktop (optional)                 │    │
│  │ Purpose: Linux GUI, Samba file server            │    │
│  │ Display: SPICE                                   │    │
│  │ Access: SPICE from ThinkPad                      │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  pve-ryzen (192.168.17.1) — Compute / Services Node     │
│  GPU: GTX 1080 (8GB VRAM)                               │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │ CT/VM: debian-docker                             │    │
│  │ Services:                                        │    │
│  │   ├── fitnaai API        :8000                   │    │
│  │   ├── ollama             :11434 (GPU)            │    │
│  │   ├── (future services)                          │    │
│  │   └── monitoring stack                           │    │
│  │ Orchestration: docker compose                    │    │
│  │ Restart policy: unless-stopped                   │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  pve (192.168.16.7) — Backup / Cluster Node (TBD)       │
│  Role: pending BLOCKER-1 resolution                      │
│  Options:                                               │
│    A) Third cluster node (quorum)                       │
│    B) Backup target (vzdump, replication)               │
│    C) Dev/staging environment                           │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  ThinkPad (192.168.16.10) — Admin Client                 │
│  Access: RDP → Windows VM, SPICE → Linux VM             │
│  Tools: ssh, xfreerdp, virt-viewer, curl                │
│  Routes: 192.168.20.0/24 via 192.168.16.2              │
└─────────────────────────────────────────────────────────┘
```

## Key Principles

1. **Separation of concerns**: Workstation node (16.2) never runs 24/7 services
2. **GPU dedication**: RX 6800 XT for interactive work, GTX 1080 for inference
3. **Docker-first services**: All services on pve-ryzen, managed via compose
4. **No single point of failure**: Backups on separate node (16.7 if available)

## Scaling Path

- **Phase 6**: fitnaai production deployment on pve-ryzen
- **Phase 7**: Monitoring (Prometheus + Grafana on pve-ryzen)
- **Phase 8**: Public API exposure (reverse proxy + TLS, requires VPS or Cloudflare Tunnel)
- **Phase 9**: Cluster formation (if 16.7 confirmed as PVE node)
