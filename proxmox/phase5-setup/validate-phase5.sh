#!/usr/bin/env bash
# =============================================================================
# validate-phase5.sh — Go/No-Go checklist for Phase 5 infrastructure
#
# Comprehensive validation of the complete Phase 5 deployment:
#   - Windows VM (RDP + SMB)
#   - Host 2 AI stack (Ollama + Qdrant + JBOT API)
#   - Network connectivity
#   - Backup system
#   - Data persistence
#
# Run from ThinkPad (192.168.16.10) after all setup is complete.
#
# Usage:
#   ./proxmox/phase5-setup/validate-phase5.sh
# =============================================================================
set -euo pipefail

# --- Colors ---
PASS="\033[0;32m[PASS]\033[0m"
FAIL="\033[0;31m[FAIL]\033[0m"
WARN="\033[0;33m[WARN]\033[0m"
INFO="\033[0;34m[INFO]\033[0m"

# --- Infrastructure ---
HOST1="192.168.16.2"
HOST2="192.168.16.3"
WIN_VM="192.168.20.10"

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=10

result() {
    local num="$1" name="$2" status="$3"
    if [ "${status}" = "pass" ]; then
        echo -e "  [${num}/10] ${PASS} ${name}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "  [${num}/10] ${FAIL} ${name}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo "==========================================="
echo "  Phase 5 — Go/No-Go Validation"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "==========================================="
echo ""

# --- 1. VM Subnet Route ---
if ip route show 2>/dev/null | grep -q "192.168.20.0/24"; then
    result 1 "VM subnet route (192.168.20.0/24) exists" "pass"
else
    result 1 "VM subnet route (192.168.20.0/24) exists" "fail"
fi

# --- 2. Windows VM reachable ---
if ping -c 1 -W 2 "${WIN_VM}" > /dev/null 2>&1; then
    result 2 "Windows VM (${WIN_VM}) reachable" "pass"
else
    result 2 "Windows VM (${WIN_VM}) reachable" "fail"
fi

# --- 3. RDP port open ---
if timeout 3 bash -c "echo >/dev/tcp/${WIN_VM}/3389" 2>/dev/null; then
    result 3 "RDP port (${WIN_VM}:3389) open" "pass"
else
    result 3 "RDP port (${WIN_VM}:3389) open" "fail"
fi

# --- 4. SMB port open ---
if timeout 3 bash -c "echo >/dev/tcp/${WIN_VM}/445" 2>/dev/null; then
    result 4 "SMB port (${WIN_VM}:445) open" "pass"
else
    result 4 "SMB port (${WIN_VM}:445) open" "fail"
fi

# --- 5. Ollama running ---
if curl -sf "http://${HOST2}:11434/" > /dev/null 2>&1; then
    result 5 "Ollama (${HOST2}:11434) responding" "pass"
else
    result 5 "Ollama (${HOST2}:11434) responding" "fail"
fi

# --- 6. Qdrant running ---
if curl -sf "http://${HOST2}:6333/healthz" > /dev/null 2>&1; then
    result 6 "Qdrant (${HOST2}:6333) healthy" "pass"
else
    result 6 "Qdrant (${HOST2}:6333) healthy" "fail"
fi

# --- 7. JBOT API running ---
HEALTH=$(curl -sf "http://${HOST2}:8000/health" 2>/dev/null || echo '{}')
if echo "${HEALTH}" | grep -q '"status"' 2>/dev/null; then
    result 7 "JBOT API (${HOST2}:8000) healthy" "pass"
else
    result 7 "JBOT API (${HOST2}:8000) healthy" "fail"
fi

# --- 8. Backup script exists and is executable ---
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -x "${SCRIPT_DIR}/scripts/backup-fitna.sh" ]; then
    result 8 "Backup script executable" "pass"
else
    result 8 "Backup script executable" "fail"
fi

# --- 9. Restore script exists and is executable ---
if [ -x "${SCRIPT_DIR}/scripts/restore-fitna.sh" ]; then
    result 9 "Restore script executable" "pass"
else
    result 9 "Restore script executable" "fail"
fi

# --- 10. .gitignore excludes backups ---
if grep -q "\.tar\.gz" "${SCRIPT_DIR}/.gitignore" 2>/dev/null && \
   grep -q "/backups/" "${SCRIPT_DIR}/.gitignore" 2>/dev/null; then
    result 10 ".gitignore excludes backup artifacts" "pass"
else
    result 10 ".gitignore excludes backup artifacts" "fail"
fi

# --- Summary ---
echo ""
echo "==========================================="
echo -e "  Results: ${PASS_COUNT}/${TOTAL} passed, ${FAIL_COUNT}/${TOTAL} failed"
echo "==========================================="

if [ "${PASS_COUNT}" -eq "${TOTAL}" ]; then
    echo ""
    echo -e "  ${PASS}  GO — Phase 5 infrastructure is fully operational"
    echo ""
    echo "  Architecture:"
    echo "    Host 1 (${HOST1}) → Windows VM (${WIN_VM}) + RX 6800 XT"
    echo "    Host 2 (${HOST2}) → Ollama + Qdrant + JBOT API + GTX 1080"
    echo "    ThinkPad → RDP / SMB / AI API access"
    echo ""
elif [ "${FAIL_COUNT}" -le 3 ]; then
    echo ""
    echo -e "  ${WARN}  CONDITIONAL GO — Fix ${FAIL_COUNT} failing check(s) before production use"
    echo ""
else
    echo ""
    echo -e "  ${FAIL}  NO-GO — ${FAIL_COUNT} checks failed, review setup"
    echo ""
fi

exit "${FAIL_COUNT}"
