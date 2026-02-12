# Host Inventory

Actual infrastructure as observed from Proxmox management.

## Network Layout

```
┌─────────────────────────────────────────────────────────┐
│  Subnet 192.168.16.0/24 — Production / VM Network       │
│                                                         │
│  ┌─────────────────┐  ┌─────────────────┐               │
│  │ pve             │  │ pve             │               │
│  │ 192.168.16.2    │  │ 192.168.16.7    │               │
│  │ RX 6800 XT 16GB │  │ (role TBD)      │               │
│  └─────────────────┘  └─────────────────┘               │
│                                                         │
│  ┌─────────────────┐                                    │
│  │ ThinkPad        │                                    │
│  │ 192.168.16.10   │                                    │
│  │ Client / Dev    │                                    │
│  └─────────────────┘                                    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  Subnet 192.168.17.0/24 — Management / Secondary        │
│                                                         │
│  ┌─────────────────┐  ┌─────────────────┐               │
│  │ pve-ryzen       │  │ pve             │               │
│  │ 192.168.17.1    │  │ 192.168.17.2    │               │
│  │ (+ .17.16)      │  │                 │               │
│  │ GTX 1080 8GB    │  │                 │               │
│  └─────────────────┘  └─────────────────┘               │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  VM-Netz: 192.168.20.0/24 (vmbr1 — internal, NAT)       │
│                                                         │
│  ┌─────────────────┐  ┌─────────────────┐               │
│  │ Windows VM      │  │ Linux Desktop   │               │
│  │ 192.168.20.10   │  │ 192.168.20.20   │               │
│  │ RX 6800 XT GPU  │  │ SPICE / Samba   │               │
│  └─────────────────┘  └─────────────────┘               │
└─────────────────────────────────────────────────────────┘
```

## Host Details

| Hostname | IP (Primary) | IP (Secondary) | GPU | Role |
|----------|-------------|----------------|-----|------|
| pve | 192.168.16.2 | — | RX 6800 XT (16GB) | Windows Workstation VM, GPU passthrough |
| pve | 192.168.16.7 | 192.168.17.2 | (TBD) | Additional PVE node |
| pve-ryzen | 192.168.17.1 | 192.168.17.16 | GTX 1080 (8GB) | Docker, Ollama, AI services (24/7) |
| ThinkPad | 192.168.16.10 | — | — | Client, development, RDP/SPICE access |

## VM Assignments

| VMID | Name | Host | IP | Purpose |
|------|------|------|----|---------|
| 100 | win11-workstation | pve (16.2) | 192.168.20.10 | Windows desktop, GPU passthrough |
| 200 | linux-desktop | pve (16.2) | 192.168.20.20 | Linux GUI, Samba file server |
| — | debian-docker | pve-ryzen (17.1) | (DHCP/static) | Docker containers, Ollama |

## Service Mapping

| Service | Runs On | Port | Access |
|---------|---------|------|--------|
| Proxmox Web UI | all hosts | 8006 | https://192.168.16.2:8006 |
| Proxmox Web UI | pve-ryzen | 8006 | https://192.168.17.1:8006 |
| Windows RDP | VM 100 | 3389 | xfreerdp /v:192.168.20.10 |
| Linux SPICE | VM 200 | 5900+ | via PVE API |
| Samba shares | VM 200 | 445 | \\\\192.168.20.20\\projects |
| fitnaai API | pve-ryzen | 8000 | http://192.168.17.1:8000 |
| Ollama API | pve-ryzen | 11434 | http://192.168.17.1:11434 |

## Notes

- **Dual-homed hosts**: pve-ryzen appears on both 192.168.17.1 and 192.168.17.16 (possibly two NICs or VLAN)
- **pve at 192.168.16.7**: Additional node visible in Proxmox — role to be determined
- **Debian 13 container**: Visible on tty1 login, running on pve-ryzen (Docker host)
