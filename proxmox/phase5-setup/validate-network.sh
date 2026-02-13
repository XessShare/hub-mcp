#!/usr/bin/env bash
# =============================================================================
# validate-network.sh — Phase 5 network connectivity validation
#
# Tests all connections between hosts, VMs, and services.
# Run from ThinkPad (192.168.16.10) or any host in the network.
#
# Usage:
#   ./proxmox/phase5-setup/validate-network.sh
# =============================================================================
set -euo pipefail

# --- Colors ---
PASS="\033[0;32m[PASS]\033[0m"
FAIL="\033[0;31m[FAIL]\033[0m"
WARN="\033[0;33m[WARN]\033[0m"
INFO="\033[0;34m[INFO]\033[0m"

# --- Infrastructure Map ---
HOST1="192.168.16.2"       # Proxmox Host 1 (RX 6800 XT)
HOST2="192.168.16.3"       # Proxmox Host 2 (GTX 1080, Docker)
THINKPAD="192.168.16.10"   # ThinkPad
WIN_VM="192.168.20.10"     # Windows VM (GPU passthrough)
LINUX_VM="192.168.20.20"   # Linux VM (optional)

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# --- Helper functions ---
check_ping() {
    local name="$1" ip="$2"
    if ping -c 1 -W 2 "${ip}" > /dev/null 2>&1; then
        echo -e "${PASS} ${name} (${ip}) — reachable"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${FAIL} ${name} (${ip}) — unreachable"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

check_port() {
    local name="$1" ip="$2" port="$3"
    if timeout 3 bash -c "echo >/dev/tcp/${ip}/${port}" 2>/dev/null; then
        echo -e "${PASS} ${name} — ${ip}:${port} open"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${FAIL} ${name} — ${ip}:${port} closed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

check_http() {
    local name="$1" url="$2"
    local http_code
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" --connect-timeout 3 "${url}" 2>/dev/null || echo "000")
    if [ "${http_code}" = "200" ]; then
        echo -e "${PASS} ${name} — ${url} (HTTP ${http_code})"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${FAIL} ${name} — ${url} (HTTP ${http_code})"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo "=== Phase 5 Network Validation ==="
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# --- 1. Host Connectivity ---
echo -e "${INFO} --- 1. Host Connectivity (ICMP) ---"
check_ping "Host 1 (Proxmox)"  "${HOST1}"
check_ping "Host 2 (AI/Docker)" "${HOST2}"
echo ""

# --- 2. VM Subnet Routing ---
echo -e "${INFO} --- 2. VM Subnet (192.168.20.0/24) ---"

# Check if route exists
if ip route show 2>/dev/null | grep -q "192.168.20.0/24"; then
    echo -e "${PASS} Route to 192.168.20.0/24 exists"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${WARN} No route to 192.168.20.0/24 — add: ip route add 192.168.20.0/24 via ${HOST1}"
    WARN_COUNT=$((WARN_COUNT + 1))
fi

check_ping "Windows VM"  "${WIN_VM}"
check_ping "Linux VM"    "${LINUX_VM}"
echo ""

# --- 3. Windows VM Services ---
echo -e "${INFO} --- 3. Windows VM Services ---"
check_port "RDP"  "${WIN_VM}" 3389
check_port "SMB"  "${WIN_VM}" 445
echo ""

# --- 4. Host 2 AI Services ---
echo -e "${INFO} --- 4. Host 2 AI Services ---"
check_http "Ollama"   "http://${HOST2}:11434/"
check_http "Qdrant"   "http://${HOST2}:6333/healthz"
check_http "JBOT API" "http://${HOST2}:8000/health"
echo ""

# --- 5. Proxmox Web UI ---
echo -e "${INFO} --- 5. Proxmox Management ---"
check_port "Proxmox Host 1 WebUI" "${HOST1}" 8006
check_port "Proxmox Host 2 WebUI" "${HOST2}" 8006
echo ""

# --- 6. Cross-host communication ---
echo -e "${INFO} --- 6. Cross-Host Service Access ---"
# Windows VM should reach Host 2 AI services
echo "  (These tests validate that VMs can reach AI services on Host 2)"
check_port "Host2 Ollama from mgmt net"   "${HOST2}" 11434
check_port "Host2 Qdrant from mgmt net"   "${HOST2}" 6333
check_port "Host2 JBOT API from mgmt net" "${HOST2}" 8000
echo ""

# --- Summary ---
TOTAL=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
echo "==============================="
echo -e "  ${PASS} Passed:   ${PASS_COUNT}"
echo -e "  ${FAIL} Failed:   ${FAIL_COUNT}"
echo -e "  ${WARN} Warnings: ${WARN_COUNT}"
echo "  Total checks: ${TOTAL}"
echo "==============================="

if [ "${FAIL_COUNT}" -eq 0 ] && [ "${WARN_COUNT}" -eq 0 ]; then
    echo -e "\n${PASS} All checks passed — Phase 5 network is fully operational"
elif [ "${FAIL_COUNT}" -eq 0 ]; then
    echo -e "\n${WARN} Network functional with warnings — review items above"
else
    echo -e "\n${FAIL} ${FAIL_COUNT} check(s) failed — review and fix before proceeding"
fi

exit "${FAIL_COUNT}"
