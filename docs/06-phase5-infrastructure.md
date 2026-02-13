# 06 — Phase 5: VM Setup, RDP, SMB, AI Docker Stack

## Architecture Overview

```
ThinkPad (192.168.16.10)
    │
    ├── RDP ──────→ Windows VM (192.168.20.10)
    │                 ├── RX 6800 XT (GPU passthrough)
    │                 ├── SMB shares: Projects, Documents, FitnaAI, Backups
    │                 └── Runs on Host 1 (192.168.16.2)
    │
    ├── SMB Mount ─→ \\192.168.20.10\Projects  → /mnt/projects
    │                \\192.168.20.10\FitnaAI   → /mnt/fitnaai
    │
    └── API ──────→ Host 2 (192.168.16.3)
                      ├── GTX 1080 (8GB VRAM)
                      ├── Ollama    → :11434 (LLM inference)
                      ├── Qdrant    → :6333  (vector memory)
                      └── JBOT API  → :8000  (OpenAI gateway)
```

## Strategic Decision

| Host | GPU | Role |
|------|-----|------|
| Host 1 (192.168.16.2) | RX 6800 XT (16GB) | Windows VM — gaming, business, desktop work |
| Host 2 (192.168.16.3) | GTX 1080 (8GB) | AI stack — Ollama, Qdrant, JBOT API (24/7) |
| ThinkPad (192.168.16.10) | — | Client — RDP, SMB, API access |

**Separation = Stability.** AI workloads don't interfere with desktop usage.

---

## Setup Scripts

### 1. Windows VM (run inside VM as Administrator)

```powershell
# Enable RDP
Set-ExecutionPolicy Bypass -Scope Process -Force
.\proxmox\phase5-setup\setup-windows-rdp.ps1

# Create SMB shares
.\proxmox\phase5-setup\setup-windows-smb.ps1
```

### 2. Host 2 — AI Stack (run on 192.168.16.3 as root)

```bash
./proxmox/phase5-setup/setup-host2-ai.sh
```

This will:
- Verify GPU (GTX 1080) and NVIDIA driver
- Install Docker + NVIDIA Container Toolkit (if needed)
- Deploy Ollama + Qdrant + JBOT API via Docker Compose
- Pull AI models sized for 8GB VRAM

### 3. ThinkPad — Client Setup

```bash
# Setup routes to VM subnet
./proxmox/phase5-setup/connect-thinkpad.sh routes

# Connect via RDP
./proxmox/phase5-setup/connect-thinkpad.sh rdp

# Mount SMB shares
./proxmox/phase5-setup/connect-thinkpad.sh mount

# Test AI services
./proxmox/phase5-setup/connect-thinkpad.sh ai-test
```

---

## Network Configuration

### Routing (ThinkPad → VMs)

```bash
# Temporary
sudo ip route add 192.168.20.0/24 via 192.168.16.2

# Persistent (NetworkManager)
nmcli connection modify <conn> +ipv4.routes "192.168.20.0/24 192.168.16.2"

# Persistent (/etc/network/interfaces)
up ip route add 192.168.20.0/24 via 192.168.16.2
```

### Port Map

| Service | Host | Port | Protocol |
|---------|------|------|----------|
| Proxmox WebUI | 192.168.16.2 | 8006 | HTTPS |
| Proxmox WebUI | 192.168.16.3 | 8006 | HTTPS |
| Windows RDP | 192.168.20.10 | 3389 | TCP |
| Windows SMB | 192.168.20.10 | 445 | TCP |
| Ollama | 192.168.16.3 | 11434 | HTTP |
| Qdrant REST | 192.168.16.3 | 6333 | HTTP |
| Qdrant gRPC | 192.168.16.3 | 6334 | gRPC |
| JBOT API | 192.168.16.3 | 8000 | HTTP |

---

## AI Stack Details

### Docker Compose (`docker/stacks/ai-host2.yml`)

```bash
# Start
docker compose -f docker/stacks/ai-host2.yml up -d

# Stop
docker compose -f docker/stacks/ai-host2.yml down

# Logs
docker compose -f docker/stacks/ai-host2.yml logs -f

# Status
docker compose -f docker/stacks/ai-host2.yml ps
```

### Recommended Models (GTX 1080, 8GB VRAM)

```bash
docker exec ollama ollama pull llama3.1:8b        # General chat
docker exec ollama ollama pull codellama:7b        # Code generation
docker exec ollama ollama pull nomic-embed-text    # Embeddings
docker exec ollama ollama pull mistral:7b          # Alternative chat
```

### API Usage

```bash
# Health check
curl http://192.168.16.3:8000/health

# Chat completion
curl -X POST http://192.168.16.3:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.1:8b",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# Embeddings
curl -X POST http://192.168.16.3:8000/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nomic-embed-text",
    "input": "Search query text"
  }'
```

---

## Validation

### Quick Test

```bash
./proxmox/phase5-setup/validate-network.sh
```

### Full Go/No-Go Checklist

```bash
./proxmox/phase5-setup/validate-phase5.sh
```

10-point checklist:
1. VM subnet route exists
2. Windows VM reachable
3. RDP port open
4. SMB port open
5. Ollama responding
6. Qdrant healthy
7. JBOT API healthy
8. Backup script executable
9. Restore script executable
10. .gitignore excludes backups

---

## Execution Order

```
1.  Host 1: Windows VM exists + RX 6800 XT passthrough    ✓ (already done)
2.  Windows VM: Run setup-windows-rdp.ps1
3.  Windows VM: Run setup-windows-smb.ps1
4.  Host 2: Run setup-host2-ai.sh
5.  ThinkPad: connect-thinkpad.sh routes
6.  ThinkPad: connect-thinkpad.sh rdp          (test RDP)
7.  ThinkPad: connect-thinkpad.sh mount        (test SMB)
8.  ThinkPad: connect-thinkpad.sh ai-test      (test AI)
9.  ThinkPad: validate-phase5.sh               (Go/No-Go)
10. Optional: scripts/backup-fitna.sh           (test backup)
```
