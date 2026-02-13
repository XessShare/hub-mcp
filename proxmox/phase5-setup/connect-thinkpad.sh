#!/usr/bin/env bash
# =============================================================================
# connect-thinkpad.sh — ThinkPad connection utility for Phase 5 infrastructure
#
# Interactive menu to connect to VMs and services from the ThinkPad.
# Handles routing, RDP, SMB mounts, and AI service access.
#
# Run on ThinkPad (192.168.16.10).
#
# Usage:
#   ./proxmox/phase5-setup/connect-thinkpad.sh          # Interactive menu
#   ./proxmox/phase5-setup/connect-thinkpad.sh rdp       # Direct RDP
#   ./proxmox/phase5-setup/connect-thinkpad.sh mount      # Mount SMB shares
#   ./proxmox/phase5-setup/connect-thinkpad.sh routes     # Setup routes
#   ./proxmox/phase5-setup/connect-thinkpad.sh ai-test    # Test AI services
# =============================================================================
set -euo pipefail

# --- Colors ---
PASS="\033[0;32m[PASS]\033[0m"
FAIL="\033[0;31m[FAIL]\033[0m"
WARN="\033[0;33m[WARN]\033[0m"
INFO="\033[0;34m[INFO]\033[0m"

# --- Configuration ---
HOST1="192.168.16.2"
HOST2="192.168.16.3"
WIN_VM="192.168.20.10"
RDP_USER="${RDP_USER:-Administrator}"
RDP_RESOLUTION="${RDP_RESOLUTION:-1920x1080}"
SMB_MOUNT_BASE="/mnt"
SMB_SHARES=("Projects" "Documents" "FitnaAI" "Backups")
CRED_FILE="/root/.smbcredentials"

ACTION="${1:-menu}"

# --- Functions ---

setup_routes() {
    echo -e "${INFO} Setting up routes to VM subnet..."

    if ip route show | grep -q "192.168.20.0/24"; then
        echo -e "${PASS} Route already exists"
    else
        sudo ip route add 192.168.20.0/24 via "${HOST1}"
        echo -e "${PASS} Route added: 192.168.20.0/24 via ${HOST1}"
    fi

    # Test
    if ping -c 1 -W 2 "${WIN_VM}" > /dev/null 2>&1; then
        echo -e "${PASS} Windows VM (${WIN_VM}) reachable"
    else
        echo -e "${WARN} Windows VM not responding to ping (may be firewall)"
    fi

    echo ""
    echo -e "${INFO} For persistent route, add to /etc/network/interfaces:"
    echo "  up ip route add 192.168.20.0/24 via ${HOST1}"
    echo ""
    echo -e "${INFO} Or for NetworkManager:"
    echo "  nmcli connection modify <connection-name> +ipv4.routes '192.168.20.0/24 ${HOST1}'"
}

connect_rdp() {
    echo -e "${INFO} Connecting to Windows VM via RDP..."
    echo -e "${INFO} Target: ${WIN_VM}:3389, User: ${RDP_USER}, Resolution: ${RDP_RESOLUTION}"

    # Check xfreerdp
    if ! command -v xfreerdp &>/dev/null; then
        echo -e "${FAIL} xfreerdp not installed"
        echo "  Install: sudo apt install freerdp2-x11"
        exit 1
    fi

    # Ensure route exists
    if ! ip route show | grep -q "192.168.20.0/24"; then
        echo -e "${WARN} No route to VM subnet — adding..."
        sudo ip route add 192.168.20.0/24 via "${HOST1}"
    fi

    xfreerdp /v:"${WIN_VM}" \
        /u:"${RDP_USER}" \
        /size:"${RDP_RESOLUTION}" \
        /dynamic-resolution \
        /gfx:AVC444 \
        /sound:sys:pulse \
        /microphone:sys:pulse \
        /drive:shared,"${HOME}/Shared" \
        /clipboard \
        +auto-reconnect \
        /auto-reconnect-max-retries:5 \
        /cert:ignore
}

mount_smb() {
    echo -e "${INFO} Mounting Windows VM SMB shares..."

    # Check cifs-utils
    if ! command -v mount.cifs &>/dev/null; then
        echo -e "${INFO} Installing cifs-utils..."
        sudo apt-get install -y cifs-utils
    fi

    # Create credentials file if needed
    if [ ! -f "${CRED_FILE}" ]; then
        echo -e "${INFO} Creating SMB credentials file..."
        read -rp "  SMB Username [Administrator]: " smb_user
        smb_user="${smb_user:-Administrator}"
        read -rsp "  SMB Password: " smb_pass
        echo ""

        echo "username=${smb_user}" | sudo tee "${CRED_FILE}" > /dev/null
        echo "password=${smb_pass}" | sudo tee -a "${CRED_FILE}" > /dev/null
        sudo chmod 600 "${CRED_FILE}"
        echo -e "${PASS} Credentials saved to ${CRED_FILE}"
    fi

    # Mount each share
    CURRENT_UID=$(id -u)
    CURRENT_GID=$(id -g)

    for share in "${SMB_SHARES[@]}"; do
        local_mount="${SMB_MOUNT_BASE}/${share,,}"  # lowercase

        if mountpoint -q "${local_mount}" 2>/dev/null; then
            echo -e "${INFO} Already mounted: ${local_mount}"
            continue
        fi

        sudo mkdir -p "${local_mount}"
        if sudo mount -t cifs "//${WIN_VM}/${share}" "${local_mount}" \
            -o "credentials=${CRED_FILE},uid=${CURRENT_UID},gid=${CURRENT_GID},iocharset=utf8"; then
            echo -e "${PASS} Mounted: //${WIN_VM}/${share} -> ${local_mount}"
        else
            echo -e "${FAIL} Failed to mount: ${share}"
        fi
    done

    echo ""
    echo -e "${INFO} To make mounts persistent, add to /etc/fstab:"
    for share in "${SMB_SHARES[@]}"; do
        echo "  //${WIN_VM}/${share}  ${SMB_MOUNT_BASE}/${share,,}  cifs  credentials=${CRED_FILE},uid=${CURRENT_UID},gid=${CURRENT_GID},iocharset=utf8,_netdev  0  0"
    done
}

umount_smb() {
    echo -e "${INFO} Unmounting SMB shares..."
    for share in "${SMB_SHARES[@]}"; do
        local_mount="${SMB_MOUNT_BASE}/${share,,}"
        if mountpoint -q "${local_mount}" 2>/dev/null; then
            sudo umount "${local_mount}"
            echo -e "${PASS} Unmounted: ${local_mount}"
        fi
    done
}

test_ai() {
    echo -e "${INFO} Testing AI services on Host 2 (${HOST2})..."
    echo ""

    # Ollama
    echo -n "  Ollama (${HOST2}:11434): "
    if curl -sf "http://${HOST2}:11434/" > /dev/null 2>&1; then
        echo -e "${PASS}"
        echo "    Models:"
        curl -sf "http://${HOST2}:11434/api/tags" 2>/dev/null \
            | python3 -c "import sys,json; [print(f'      - {m[\"name\"]}') for m in json.load(sys.stdin).get('models',[])]" \
            2>/dev/null || echo "      (could not list)"
    else
        echo -e "${FAIL}"
    fi

    # Qdrant
    echo -n "  Qdrant (${HOST2}:6333): "
    if curl -sf "http://${HOST2}:6333/healthz" > /dev/null 2>&1; then
        echo -e "${PASS}"
    else
        echo -e "${FAIL}"
    fi

    # JBOT API
    echo -n "  JBOT API (${HOST2}:8000): "
    local health
    health=$(curl -sf "http://${HOST2}:8000/health" 2>/dev/null || echo '{}')
    if echo "${health}" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('status')=='ok' else 1)" 2>/dev/null; then
        echo -e "${PASS}"
        echo "    $(echo "${health}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Ollama: {d.get(\"ollama\",\"?\")}, Qdrant: {d.get(\"qdrant\",\"?\")}')" 2>/dev/null)"
    else
        echo -e "${FAIL}"
    fi

    echo ""
    echo -e "${INFO} Quick test — send a chat message:"
    echo "  curl -X POST http://${HOST2}:8000/v1/chat/completions \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"model\":\"llama3.1:8b\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}]}'"
}

show_menu() {
    echo "=== ThinkPad Connection Utility ==="
    echo ""
    echo "  Infrastructure:"
    echo "    Host 1: ${HOST1} (Proxmox, RX 6800 XT → Windows VM)"
    echo "    Host 2: ${HOST2} (Docker, GTX 1080 → AI Stack)"
    echo "    Win VM: ${WIN_VM} (RDP + SMB shares)"
    echo ""
    echo "  Commands:"
    echo "    routes   — Set up routes to VM subnet"
    echo "    rdp      — Connect to Windows VM via RDP"
    echo "    mount    — Mount Windows VM SMB shares"
    echo "    umount   — Unmount SMB shares"
    echo "    ai-test  — Test AI services on Host 2"
    echo ""
    echo "  Usage: $0 <command>"
    echo ""
}

# --- Main ---
case "${ACTION}" in
    routes)   setup_routes ;;
    rdp)      connect_rdp ;;
    mount)    mount_smb ;;
    umount)   umount_smb ;;
    ai-test)  test_ai ;;
    menu|*)   show_menu ;;
esac
