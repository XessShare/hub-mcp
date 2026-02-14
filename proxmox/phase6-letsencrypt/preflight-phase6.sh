#!/usr/bin/env bash
# =============================================================================
# preflight-phase6.sh — Pre-flight checks before LE Production switch
#
# Validates system health, resource availability, and Traefik readiness
# before switching from Let's Encrypt Staging to Production certificates.
#
# Run on the host where Traefik is deployed (e.g., 192.168.16.2 or .3).
#
# Resource Gates:
#   - RAM: > 8GB free
#   - CPU Load: < 2.0 (5-min avg)
#   - Disk: > 5GB free on /
#   - Docker: daemon healthy, no restart loops
#
# Usage:
#   ./proxmox/phase6-letsencrypt/preflight-phase6.sh
#   ./proxmox/phase6-letsencrypt/preflight-phase6.sh --traefik-dir /opt/traefik
# =============================================================================
set -euo pipefail

# --- Colors ---
PASS="\033[0;32m[PASS]\033[0m"
FAIL="\033[0;31m[FAIL]\033[0m"
WARN="\033[0;33m[WARN]\033[0m"
INFO="\033[0;34m[INFO]\033[0m"
BOLD="\033[1m"
RESET="\033[0m"

# --- Configuration ---
MIN_FREE_RAM_GB=8
MAX_CPU_LOAD=2.0
MIN_FREE_DISK_GB=5
TRAEFIK_DIR="${1:-/opt/traefik}"  # Override with --traefik-dir or first arg

# Parse named args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --traefik-dir) TRAEFIK_DIR="$2"; shift 2 ;;
        *) shift ;;
    esac
done

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
TOTAL=0

result() {
    local status="$1" name="$2"
    TOTAL=$((TOTAL + 1))
    case "${status}" in
        pass)
            echo -e "  ${PASS} ${name}"
            PASS_COUNT=$((PASS_COUNT + 1))
            ;;
        fail)
            echo -e "  ${FAIL} ${name}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            ;;
        warn)
            echo -e "  ${WARN} ${name}"
            WARN_COUNT=$((WARN_COUNT + 1))
            ;;
    esac
}

echo "============================================================"
echo "  Phase 6 Pre-Flight — Let's Encrypt Production Readiness"
echo "  Host: $(hostname)"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ==========================================================================
# SECTION 1: System Information (display only)
# ==========================================================================
echo -e "${INFO} --- System Information ---"

# Proxmox version (if available)
if command -v pveversion &>/dev/null; then
    echo "  Proxmox: $(pveversion 2>/dev/null || echo 'N/A')"
fi

# Uptime
echo "  Uptime:  $(uptime -p 2>/dev/null || uptime)"

# Kernel
echo "  Kernel:  $(uname -r)"
echo ""

# ==========================================================================
# SECTION 2: Resource Gates
# ==========================================================================
echo -e "${INFO} --- Resource Gates ---"

# Gate 1: RAM
FREE_RAM_KB=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
if [ -n "${FREE_RAM_KB}" ]; then
    FREE_RAM_GB=$((FREE_RAM_KB / 1024 / 1024))
    FREE_RAM_MB=$((FREE_RAM_KB / 1024))
    if [ "${FREE_RAM_GB}" -ge "${MIN_FREE_RAM_GB}" ]; then
        result "pass" "RAM: ${FREE_RAM_MB}MB free (>= ${MIN_FREE_RAM_GB}GB required)"
    else
        result "fail" "RAM: ${FREE_RAM_MB}MB free (< ${MIN_FREE_RAM_GB}GB required)"
    fi
else
    result "warn" "RAM: Could not read /proc/meminfo"
fi

# Full memory breakdown
echo ""
echo "  Memory details:"
free -h 2>/dev/null | sed 's/^/    /'
echo ""

# Gate 2: CPU Load
LOAD_5MIN=$(awk '{print $2}' /proc/loadavg 2>/dev/null || echo "0")
LOAD_INT=$(echo "${LOAD_5MIN}" | awk '{printf "%d", $1 * 10}')
MAX_INT=$(echo "${MAX_CPU_LOAD}" | awk '{printf "%d", $1 * 10}')
if [ "${LOAD_INT}" -le "${MAX_INT}" ]; then
    result "pass" "CPU Load: ${LOAD_5MIN} (5-min avg, <= ${MAX_CPU_LOAD} required)"
else
    result "fail" "CPU Load: ${LOAD_5MIN} (5-min avg, > ${MAX_CPU_LOAD} limit)"
fi

# Gate 3: Disk space
ROOT_FREE_KB=$(df / 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "${ROOT_FREE_KB}" ]; then
    ROOT_FREE_GB=$((ROOT_FREE_KB / 1024 / 1024))
    if [ "${ROOT_FREE_GB}" -ge "${MIN_FREE_DISK_GB}" ]; then
        result "pass" "Disk: ${ROOT_FREE_GB}GB free on / (>= ${MIN_FREE_DISK_GB}GB required)"
    else
        result "fail" "Disk: ${ROOT_FREE_GB}GB free on / (< ${MIN_FREE_DISK_GB}GB required)"
    fi
else
    result "warn" "Disk: Could not read disk space"
fi

# Disk breakdown
echo ""
echo "  Disk details:"
df -h / /var /opt 2>/dev/null | sed 's/^/    /' || df -h / 2>/dev/null | sed 's/^/    /'
echo ""

# ==========================================================================
# SECTION 3: Docker Health
# ==========================================================================
echo -e "${INFO} --- Docker Health ---"

# Docker daemon
if systemctl is-active --quiet docker 2>/dev/null; then
    result "pass" "Docker daemon: active"
else
    result "fail" "Docker daemon: not running"
fi

# Docker info
if docker info &>/dev/null; then
    CONTAINERS_RUNNING=$(docker info --format '{{.ContainersRunning}}' 2>/dev/null || echo "?")
    result "pass" "Docker responding: ${CONTAINERS_RUNNING} container(s) running"
else
    result "fail" "Docker not responding (docker info failed)"
fi

# Check for restart loops (containers restarting in last 5 min)
RESTART_LOOPS=$(docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -c "Restarting" || echo "0")
if [ "${RESTART_LOOPS}" -eq 0 ]; then
    result "pass" "No containers in restart loop"
else
    result "fail" "${RESTART_LOOPS} container(s) in restart loop"
fi

# Running containers
echo ""
echo "  Running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | sed 's/^/    /' || echo "    (docker ps failed)"
echo ""

# ==========================================================================
# SECTION 4: GPU Status
# ==========================================================================
echo -e "${INFO} --- GPU Status ---"

if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo "unknown")
    GPU_VRAM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>/dev/null || echo "?")
    GPU_VRAM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null || echo "?")
    GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null || echo "?")

    result "pass" "GPU: ${GPU_NAME} — ${GPU_VRAM_USED} / ${GPU_VRAM_TOTAL} — ${GPU_TEMP}°C"

    echo ""
    echo "  GPU details:"
    nvidia-smi 2>/dev/null | head -20 | sed 's/^/    /'
    echo ""
else
    result "warn" "nvidia-smi not found (no NVIDIA GPU or driver not installed)"
fi

# ==========================================================================
# SECTION 5: Traefik Readiness
# ==========================================================================
echo -e "${INFO} --- Traefik Readiness ---"

# Check Traefik directory
if [ -d "${TRAEFIK_DIR}" ]; then
    result "pass" "Traefik directory exists: ${TRAEFIK_DIR}"
else
    result "fail" "Traefik directory not found: ${TRAEFIK_DIR}"
    echo -e "  ${WARN} Set with: $0 --traefik-dir /path/to/traefik"
fi

# Check for Traefik config files
TRAEFIK_YML=""
for f in "${TRAEFIK_DIR}/traefik.yml" "${TRAEFIK_DIR}/traefik.yaml" "${TRAEFIK_DIR}/traefik.toml"; do
    if [ -f "${f}" ]; then
        TRAEFIK_YML="${f}"
        break
    fi
done

if [ -n "${TRAEFIK_YML}" ]; then
    result "pass" "Traefik config found: ${TRAEFIK_YML}"

    # Check current caServer setting
    if grep -q "staging" "${TRAEFIK_YML}" 2>/dev/null; then
        CURRENT_CA=$(grep -o 'https://[^ "]*' "${TRAEFIK_YML}" | grep -i "acme\|letsencrypt" | head -1 || echo "unknown")
        result "pass" "Currently using STAGING: ${CURRENT_CA}"
    elif grep -q "acme-v02.api.letsencrypt.org" "${TRAEFIK_YML}" 2>/dev/null; then
        result "warn" "Already on PRODUCTION — are you sure you want to re-run?"
    else
        result "warn" "Could not determine current caServer"
    fi
else
    result "fail" "No traefik.yml/yaml/toml found in ${TRAEFIK_DIR}"
fi

# Check acme.json
ACME_JSON="${TRAEFIK_DIR}/acme.json"
if [ -f "${ACME_JSON}" ]; then
    ACME_SIZE=$(stat -c%s "${ACME_JSON}" 2>/dev/null || echo "0")
    ACME_PERMS=$(stat -c%a "${ACME_JSON}" 2>/dev/null || echo "unknown")
    if [ "${ACME_PERMS}" = "600" ]; then
        result "pass" "acme.json exists (${ACME_SIZE} bytes, perms: ${ACME_PERMS})"
    else
        result "warn" "acme.json perms are ${ACME_PERMS} (should be 600)"
    fi
else
    result "warn" "acme.json not found (will be created on Traefik start)"
fi

# Check Traefik container
TRAEFIK_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i traefik | head -1 || echo "")
if [ -n "${TRAEFIK_CONTAINER}" ]; then
    TRAEFIK_STATUS=$(docker inspect --format '{{.State.Status}}' "${TRAEFIK_CONTAINER}" 2>/dev/null || echo "unknown")
    result "pass" "Traefik container '${TRAEFIK_CONTAINER}' is ${TRAEFIK_STATUS}"
else
    result "warn" "No running Traefik container found"
fi

echo ""

# ==========================================================================
# SECTION 6: DNS & Network
# ==========================================================================
echo -e "${INFO} --- DNS & Certificate Readiness ---"

# Check if domains resolve (read from traefik config if available)
DOMAINS=()
if [ -n "${TRAEFIK_YML}" ]; then
    while IFS= read -r domain; do
        DOMAINS+=("${domain}")
    done < <(grep -oP '(?:Host\(`|main:\s*"|sans:\s*-\s*")[^`"]+' "${TRAEFIK_YML}" 2>/dev/null | sort -u || true)
fi

if [ ${#DOMAINS[@]} -gt 0 ]; then
    for domain in "${DOMAINS[@]}"; do
        if host "${domain}" &>/dev/null || dig +short "${domain}" 2>/dev/null | grep -q '.'; then
            result "pass" "DNS resolves: ${domain}"
        else
            result "fail" "DNS not resolving: ${domain}"
        fi
    done
else
    echo -e "  ${WARN} No domains found in config — DNS check skipped"
    echo "  Verify manually: host yourdomain.com"
fi

# Check Let's Encrypt reachability
if curl -sf --connect-timeout 5 "https://acme-v02.api.letsencrypt.org/directory" > /dev/null 2>&1; then
    result "pass" "Let's Encrypt Production API reachable"
else
    result "fail" "Let's Encrypt Production API unreachable"
fi

echo ""

# ==========================================================================
# SECTION 7: Snapshot Reminder
# ==========================================================================
echo -e "${BOLD}============================================================${RESET}"
echo -e "${BOLD}  MANDATORY BEFORE PROCEEDING:${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""
echo "  Before running switch-to-production.sh, create a Proxmox snapshot:"
echo ""
echo "    # Via Proxmox CLI:"
echo "    qm snapshot <VMID> pre-phase6 --description 'Before LE Production'"
echo "    # or for LXC:"
echo "    pct snapshot <CTID> pre-phase6 --description 'Before LE Production'"
echo ""
echo "    # Via Proxmox WebUI:"
echo "    Datacenter → Node → VM/CT → Snapshots → Take Snapshot"
echo ""

# ==========================================================================
# Summary
# ==========================================================================
echo "============================================================"
echo -e "  Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${WARN_COUNT} warnings (${TOTAL} checks)"
echo "============================================================"

if [ "${FAIL_COUNT}" -eq 0 ] && [ "${WARN_COUNT}" -eq 0 ]; then
    echo ""
    echo -e "  ${PASS} ${BOLD}GO${RESET} — All checks passed. Ready for Phase 6."
    echo ""
    echo "  Next step:"
    echo "    ./proxmox/phase6-letsencrypt/switch-to-production.sh"
    echo ""
elif [ "${FAIL_COUNT}" -eq 0 ]; then
    echo ""
    echo -e "  ${WARN} ${BOLD}CONDITIONAL GO${RESET} — ${WARN_COUNT} warning(s). Review before proceeding."
    echo ""
else
    echo ""
    echo -e "  ${FAIL} ${BOLD}NO-GO${RESET} — ${FAIL_COUNT} check(s) failed. Fix before proceeding."
    echo ""
fi

exit "${FAIL_COUNT}"
