# ADR-003: Final Production Architecture

**Status:** Accepted
**Date:** 2026-02-12
**Decision makers:** Projektleitung

## Architecture

```
┌─────────────────────── INTERNET ───────────────────────┐
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Hetzner VPS (Public Entry Point)                │    │
│  │  Role: Reverse Proxy + TLS Termination           │    │
│  │                                                  │    │
│  │  Nginx → https://api.fitnaai.de                  │    │
│  │  Let's Encrypt TLS                               │    │
│  │  WireGuard Client → 10.0.0.1                     │    │
│  │                                                  │    │
│  │  proxy_pass → http://10.0.0.2:8000               │    │
│  └──────────────────────┬──────────────────────────┘    │
│                         │ WireGuard Tunnel               │
└─────────────────────────┼───────────────────────────────┘
                          │
┌─────────────────────────┼───────────────────────────────┐
│  LAN: 192.168.16.0/24  │                                │
│                         │                                │
│  ┌──────────────────────┴──────────────────────────┐    │
│  │  pve — GamingPC (192.168.16.2)                   │    │
│  │  PRODUCTION HOST                                 │    │
│  │  GPU: RX 6800 XT (16GB) — not used by Ollama     │    │
│  │  WireGuard Server → 10.0.0.2                     │    │
│  │                                                  │    │
│  │  ┌──────────────────────────────────────────┐    │    │
│  │  │ Docker (host network / bridge)            │    │    │
│  │  │  ├── fitnaai API         :8000            │    │    │
│  │  │  └── ollama (CPU-only)   :11434           │    │    │
│  │  └──────────────────────────────────────────┘    │    │
│  │                                                  │    │
│  │  ┌──────────────────────────────────────────┐    │    │
│  │  │ VM 100: win11-workstation                 │    │    │
│  │  │ GPU: RX 6800 XT (passthrough)             │    │    │
│  │  │ Access: RDP                               │    │    │
│  │  └──────────────────────────────────────────┘    │    │
│  └──────────────────────────────────────────────────┘    │
│                                                         │
│  ┌──────────────────────────────────────────────────┐    │
│  │  pve — ThinkPad (192.168.16.7)                    │    │
│  │  DEV / TEST NODE                                  │    │
│  │  No GPU, no prod traffic                          │    │
│  │  Use: staging, testing, admin client               │    │
│  └──────────────────────────────────────────────────┘    │
│                                                         │
│  ┌──────────────────────────────────────────────────┐    │
│  │  ThinkPad Admin (192.168.16.10)                   │    │
│  │  CLIENT                                           │    │
│  │  ssh, xfreerdp, curl, browser                     │    │
│  └──────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  Subnet 192.168.17.0/24 — Ryzen (standby)               │
│                                                         │
│  ┌──────────────────────────────────────────────────┐    │
│  │  pve-ryzen (192.168.17.1) — 1 NIC                 │    │
│  │  GPU: GTX 1080 (8GB, CUDA-capable)                │    │
│  │  Role: STANDBY / FUTURE COMPUTE                    │    │
│  │  Scaling: Migrate fitnaai+ollama here when ready   │    │
│  │           Then GPU inference becomes available      │    │
│  └──────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

## Key Decisions

1. **192.168.16.2 = Production Host**: Docker + fitnaai + Ollama (CPU-only)
2. **RX 6800 XT NOT used by Ollama**: AMD GPU, no CUDA. GPU dedicated to Windows VM passthrough.
3. **Public access via Hetzner VPS only**: WireGuard tunnel, nginx reverse proxy, TLS
4. **192.168.16.7 = Dev/Test only**: ThinkPad PVE node, no production role
5. **pve-ryzen = Standby**: Future compute node. When fitnaai migrates here, GPU inference (CUDA) becomes available.

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| 16.2 runs Proxmox + Windows VM + Docker Prod | Single point of failure | Systemd restart, vzdump backups, scaling path to ryzen |
| Ollama CPU-only on 16.2 | Slow inference for large models | Use small models (llama3.2 7B), scale to ryzen+GTX1080 later |
| 1 NIC on ryzen | No network redundancy | Acceptable for non-prod standby role |
| Windows VM + Docker on same host | Resource contention | Pin CPU cores, memory limits in compose |

## Scaling Path

| Phase | Action | Trigger |
|-------|--------|---------|
| 6 | fitnaai prod deployment on 16.2 | Now |
| 7 | Hetzner VPS + WireGuard + nginx | After Phase 6 stable |
| 8 | Monitoring (Prometheus + Grafana) | After Phase 7 |
| 9 | Migrate fitnaai to ryzen (GPU inference) | When ryzen is production-ready |
| 10 | Cluster formation (16.2 + ryzen + 16.7) | When 3-node quorum justified |
