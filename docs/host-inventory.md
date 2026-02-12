# Host Inventory — Final

Last updated: 2026-02-12
Status: All blockers resolved (see ADR-002)

## Network Topology

```
┌──────────────────────────────────────────────────────────────┐
│  192.168.16.0/24 — Production Network                         │
│                                                              │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────┐ │
│  │ pve (GamingPC)   │  │ pve (ThinkPad)   │  │ ThinkPad   │ │
│  │ 192.168.16.2     │  │ 192.168.16.7     │  │ .16.10     │ │
│  │ PRODUCTION       │  │ DEV/TEST         │  │ CLIENT     │ │
│  │ RX 6800 XT       │  │ no GPU           │  │            │ │
│  └──────────────────┘  └──────────────────┘  └────────────┘ │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  192.168.17.0/24 — Secondary / Standby                        │
│                                                              │
│  ┌──────────────────┐                                        │
│  │ pve-ryzen        │                                        │
│  │ 192.168.17.1     │                                        │
│  │ STANDBY          │                                        │
│  │ GTX 1080 (CUDA)  │                                        │
│  │ 1 NIC            │                                        │
│  └──────────────────┘                                        │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  10.0.0.0/24 — WireGuard Tunnel (VPS ↔ 16.2)                 │
│                                                              │
│  VPS: 10.0.0.1    ←──WireGuard──→    16.2: 10.0.0.2         │
└──────────────────────────────────────────────────────────────┘
```

## Host Details

| Hostname | IP | GPU | Role | Status |
|----------|-----|-----|------|--------|
| pve (GamingPC) | 192.168.16.2 | RX 6800 XT (16GB, AMD) | **Production**: Docker, fitnaai, Ollama (CPU), Windows VM | Active |
| pve (ThinkPad) | 192.168.16.7 | — | **Dev/Test**: Staging, PVE node, no prod traffic | Active |
| pve-ryzen | 192.168.17.1 | GTX 1080 (8GB, CUDA) | **Standby**: Future compute with GPU inference | Standby |
| ThinkPad Admin | 192.168.16.10 | — | **Client**: SSH, RDP, browser, dev tools | Active |
| Hetzner VPS | (public IP) | — | **Edge**: Reverse proxy, TLS, WireGuard endpoint | Planned |

## Service Map (Production)

| Service | Host | Port | Access Method |
|---------|------|------|---------------|
| Proxmox Web UI | 16.2 | 8006 | https://192.168.16.2:8006 |
| Proxmox Web UI | 16.7 | 8006 | https://192.168.16.7:8006 |
| fitnaai API | 16.2 (Docker) | 8000 | Internal: http://192.168.16.2:8000 |
| fitnaai API | VPS (nginx) | 443 | Public: https://api.fitnaai.de |
| Ollama | 16.2 (Docker) | 11434 | Internal only |
| Windows RDP | VM 100 on 16.2 | 3389 | xfreerdp /v:192.168.20.10 |
| WireGuard | 16.2 ↔ VPS | 51820 | Tunnel: 10.0.0.0/24 |

## GPU Strategy

| GPU | Host | CUDA | Ollama Support | Current Use |
|-----|------|------|----------------|-------------|
| RX 6800 XT (16GB) | 16.2 | No (AMD) | CPU-only inference | Windows VM passthrough |
| GTX 1080 (8GB) | ryzen | Yes | Full GPU inference | Standby (not in production) |

**Decision**: Ollama runs CPU-only on 16.2 for Phase 1. When ryzen enters production (Phase 9), fitnaai+Ollama migrate there for CUDA-accelerated inference.
