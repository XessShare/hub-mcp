#!/usr/bin/env bash
# =============================================================================
# setup-host2-ai.sh — Bootstrap AI stack on Host 2 (192.168.16.3, GTX 1080)
#
# Installs Docker, NVIDIA Container Toolkit, pulls models, and starts
# the AI stack (Ollama + Qdrant + JBOT API).
#
# Run on Host 2 (192.168.16.3) as root.
#
# Usage:
#   ./proxmox/phase5-setup/setup-host2-ai.sh
#   SKIP_DOCKER=1 ./proxmox/phase5-setup/setup-host2-ai.sh  # Skip Docker install
# =============================================================================
set -euo pipefail

# --- Colors ---
PASS="\033[0;32m[PASS]\033[0m"
FAIL="\033[0;31m[FAIL]\033[0m"
WARN="\033[0;33m[WARN]\033[0m"
INFO="\033[0;34m[INFO]\033[0m"

# --- Configuration ---
HOST2_IP="192.168.16.3"
SKIP_DOCKER="${SKIP_DOCKER:-0}"
STACK_DIR="${STACK_DIR:-/opt/hub-mcp}"
DATA_DIR="/mnt/data/fitnaai/home/fitna"
BACKUP_DIR="/mnt/data/backups/fitnaai"

# --- Models to pre-pull (sized for GTX 1080 8GB VRAM) ---
MODELS=(
    "llama3.1:8b"
    "nomic-embed-text"
)

echo -e "${INFO} === Host 2 AI Stack Setup ==="
echo -e "${INFO} Host: ${HOST2_IP} (GTX 1080, 8GB VRAM)"

# --- 1. Verify GPU ---
echo -e "\n${INFO} [1/6] Checking GPU..."

if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)
    echo -e "${PASS} GPU detected: ${GPU_NAME} (${GPU_MEM})"
else
    echo -e "${WARN} nvidia-smi not found — NVIDIA driver may not be installed"
    echo -e "${INFO} Install: apt install nvidia-driver-535 nvidia-utils-535"
fi

# --- 2. Install Docker (if needed) ---
echo -e "\n${INFO} [2/6] Docker setup..."

if [ "${SKIP_DOCKER}" = "1" ]; then
    echo -e "${INFO} Skipping Docker install (SKIP_DOCKER=1)"
elif command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
    echo -e "${PASS} Docker already installed: v${DOCKER_VER}"
else
    echo -e "${INFO} Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    echo -e "${PASS} Docker installed"
fi

# --- 3. Install NVIDIA Container Toolkit ---
echo -e "\n${INFO} [3/6] NVIDIA Container Toolkit..."

if dpkg -l nvidia-container-toolkit &>/dev/null 2>&1; then
    echo -e "${PASS} nvidia-container-toolkit already installed"
else
    echo -e "${INFO} Installing NVIDIA Container Toolkit..."
    # Add NVIDIA repo
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null || true
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
    apt-get update -qq
    apt-get install -y nvidia-container-toolkit
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
    echo -e "${PASS} NVIDIA Container Toolkit installed and configured"
fi

# Test GPU in Docker
if docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
    echo -e "${PASS} GPU accessible from Docker containers"
else
    echo -e "${WARN} GPU not accessible from Docker — check nvidia-container-toolkit config"
fi

# --- 4. Prepare data directories ---
echo -e "\n${INFO} [4/6] Preparing data directories..."

for dir in "${DATA_DIR}" "${BACKUP_DIR}"; do
    if [ ! -d "${dir}" ]; then
        mkdir -p "${dir}"
        echo -e "${PASS} Created: ${dir}"
    else
        echo -e "${INFO} Exists: ${dir}"
    fi
done

# --- 5. Deploy AI stack ---
echo -e "\n${INFO} [5/6] Deploying AI stack..."

if [ ! -d "${STACK_DIR}" ]; then
    echo -e "${WARN} Project directory not found at ${STACK_DIR}"
    echo -e "${INFO} Clone the repo first: git clone <repo-url> ${STACK_DIR}"
    echo -e "${INFO} Then run: docker compose -f ${STACK_DIR}/docker/stacks/ai-host2.yml up -d"
else
    cd "${STACK_DIR}"
    docker compose -f docker/stacks/ai-host2.yml pull
    docker compose -f docker/stacks/ai-host2.yml up -d
    echo -e "${PASS} AI stack started"

    # Wait for Ollama to be ready
    echo -e "${INFO} Waiting for Ollama to be ready..."
    for i in $(seq 1 30); do
        if curl -sf http://localhost:11434/ > /dev/null 2>&1; then
            echo -e "${PASS} Ollama is ready"
            break
        fi
        sleep 2
    done
fi

# --- 6. Pull models ---
echo -e "\n${INFO} [6/6] Pulling AI models (sized for 8GB VRAM)..."

if curl -sf http://localhost:11434/ > /dev/null 2>&1; then
    for model in "${MODELS[@]}"; do
        echo -e "${INFO} Pulling: ${model}..."
        if docker exec ollama ollama pull "${model}" 2>&1; then
            echo -e "${PASS} Model ready: ${model}"
        else
            echo -e "${WARN} Failed to pull: ${model} (can retry later)"
        fi
    done
else
    echo -e "${WARN} Ollama not reachable — models will need to be pulled manually"
    echo -e "${INFO} Run: docker exec ollama ollama pull llama3.1:8b"
fi

# --- Summary ---
echo ""
echo -e "${INFO} === Setup Complete ==="
echo ""
echo -e "${INFO} Services:"
echo "  Ollama:    http://${HOST2_IP}:11434"
echo "  Qdrant:    http://${HOST2_IP}:6333"
echo "  JBOT API:  http://${HOST2_IP}:8000"
echo ""
echo -e "${INFO} NEXT STEPS:"
echo "  1. Verify: curl http://${HOST2_IP}:8000/health"
echo "  2. Test chat: curl -X POST http://${HOST2_IP}:8000/v1/chat/completions \\"
echo "       -H 'Content-Type: application/json' \\"
echo "       -d '{\"model\":\"llama3.1:8b\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
echo "  3. From ThinkPad: same URLs via 192.168.16.3"
echo ""
echo "  Models for GTX 1080 (8GB VRAM — use Q4/Q5 quantized):"
echo "    docker exec ollama ollama pull llama3.1:8b"
echo "    docker exec ollama ollama pull codellama:7b"
echo "    docker exec ollama ollama pull nomic-embed-text"
echo "    docker exec ollama ollama pull mistral:7b"
echo ""
