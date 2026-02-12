#!/usr/bin/env bash
# deploy-phase6.sh — Phase 6: Production deployment of fitnaai on 192.168.16.2
#
# This script:
#   1. Installs Docker (if needed)
#   2. Clones/updates the repo to /srv/fitnaai
#   3. Builds and starts containers
#   4. Installs systemd service
#   5. Configures firewall (port 8000 internal only)
#   6. Pulls initial Ollama model
#
# Run on: pve GamingPC (192.168.16.2) as root
# Usage:  sudo bash deploy-phase6.sh [REPO_URL]

set -euo pipefail

REPO_URL="${1:-https://github.com/XessShare/hub-mcp.git}"
DEPLOY_DIR="/srv/fitnaai"
PROJECT_DIR="$DEPLOY_DIR/projects/fitnaai"
SYSTEMD_UNIT="/etc/systemd/system/fitnaai.service"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "  Phase 6: fitnaai Production Deployment"
echo "  Host: 192.168.16.2 (GamingPC)"
echo "============================================"
echo ""

# --- Step 1: Docker ---
echo "==> Step 1: Ensuring Docker is installed..."
if ! command -v docker &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq docker.io docker-compose-plugin
    systemctl enable docker
    systemctl start docker
    echo "    Docker installed and started."
else
    echo "    Docker already installed: $(docker --version)"
fi

# Verify docker compose
if ! docker compose version &>/dev/null; then
    echo "ERROR: docker compose plugin not available."
    echo "Install with: apt install docker-compose-plugin"
    exit 1
fi

# --- Step 2: Clone/update repo ---
echo "==> Step 2: Setting up project in $DEPLOY_DIR..."
mkdir -p /srv

if [[ -d "$DEPLOY_DIR/.git" ]]; then
    echo "    Updating existing repo..."
    git -C "$DEPLOY_DIR" pull --ff-only
else
    echo "    Cloning repo..."
    git clone "$REPO_URL" "$DEPLOY_DIR"
fi

# Ensure .env exists
if [[ ! -f "$PROJECT_DIR/.env" ]]; then
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env" 2>/dev/null || \
    cat > "$PROJECT_DIR/.env" <<'EOF'
FITNAAI_DEBUG=false
FITNAAI_HOST=0.0.0.0
FITNAAI_PORT=8000
FITNAAI_OLLAMA_BASE_URL=http://ollama:11434
FITNAAI_OLLAMA_MODEL=llama3.2
FITNAAI_DATA_DIR=/data
EOF
    echo "    Created .env from defaults."
fi

# --- Step 3: Build and start ---
echo "==> Step 3: Building and starting containers..."
cd "$PROJECT_DIR"
docker compose build --quiet
docker compose up -d

echo "    Waiting for services to become healthy..."
sleep 10

# Check health
if curl -sf http://127.0.0.1:8000/health &>/dev/null; then
    echo "    fitnaai API: HEALTHY"
else
    echo "    WARNING: fitnaai API not yet responding. Check: docker compose logs fitnaai"
fi

if curl -sf http://127.0.0.1:11434/api/tags &>/dev/null; then
    echo "    Ollama:      HEALTHY"
else
    echo "    WARNING: Ollama not yet responding. Check: docker compose logs ollama"
fi

# --- Step 4: Systemd service ---
echo "==> Step 4: Installing systemd service..."
cp "$SCRIPT_DIR/fitnaai.service" "$SYSTEMD_UNIT"
# Update WorkingDirectory to actual project path
sed -i "s|WorkingDirectory=.*|WorkingDirectory=$PROJECT_DIR|" "$SYSTEMD_UNIT"
systemctl daemon-reload
systemctl enable fitnaai
echo "    fitnaai.service installed and enabled."

# --- Step 5: Firewall ---
echo "==> Step 5: Configuring firewall..."
# Port 8000 should only be accessible from localhost and WireGuard tunnel
# The docker-compose already binds to 127.0.0.1:8000, so no external access.
# Add explicit iptables rule for WireGuard access (10.0.0.0/24)
iptables -C INPUT -s 10.0.0.0/24 -p tcp --dport 8000 -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -s 10.0.0.0/24 -p tcp --dport 8000 -j ACCEPT

# Block external access to 8000 (redundant with 127.0.0.1 bind, but defense-in-depth)
iptables -C INPUT -p tcp --dport 8000 -j DROP 2>/dev/null || \
    iptables -A INPUT -p tcp --dport 8000 -j DROP

echo "    Port 8000: localhost + WireGuard (10.0.0.0/24) only."

# Persist if possible
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
fi

# --- Step 6: Pull Ollama model ---
echo "==> Step 6: Pulling Ollama model..."
echo "    This may take several minutes (CPU-only download + conversion)..."
docker exec ollama ollama pull llama3.2 || \
    echo "    WARNING: Model pull failed. Run manually: docker exec ollama ollama pull llama3.2"

echo ""
echo "============================================"
echo "  Phase 6 Deployment Complete"
echo "============================================"
echo ""
echo "  fitnaai API:  http://127.0.0.1:8000"
echo "  Health check: curl http://127.0.0.1:8000/health"
echo "  Ollama:       http://127.0.0.1:11434"
echo "  Systemd:      systemctl status fitnaai"
echo "  Logs:         docker compose -f $PROJECT_DIR/docker-compose.yml logs -f"
echo ""
echo "  Next: Phase 7 — WireGuard + Hetzner VPS"
echo "  Run:  bash proxmox/wireguard/setup-wireguard-server.sh"
echo ""
