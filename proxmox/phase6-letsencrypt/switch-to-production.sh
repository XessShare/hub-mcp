#!/usr/bin/env bash
# =============================================================================
# switch-to-production.sh — Let's Encrypt Staging → Production
#
# Switches Traefik from LE Staging to Production certificates.
# This is a critical operation — LE Production has rate limits:
#   - 50 certificates per registered domain per week
#   - 5 duplicate certificates per week
#   - 300 new orders per account per 3 hours
#
# Prerequisites:
#   - Run preflight-phase6.sh first (all checks must pass)
#   - Proxmox snapshot created
#   - DNS records pointing to your server
#
# What this script does:
#   1. Verifies Traefik is running with staging certs
#   2. Creates backup of current state (acme.json + traefik config)
#   3. Stops Traefik
#   4. Switches caServer from staging to production
#   5. Removes staging acme.json (staging certs are untrusted)
#   6. Creates fresh acme.json with correct permissions
#   7. Starts Traefik
#   8. Verifies new production certificates
#
# Usage:
#   ./proxmox/phase6-letsencrypt/switch-to-production.sh [traefik-dir]
#
# Rollback:
#   ./proxmox/phase6-letsencrypt/switch-to-production.sh --rollback [traefik-dir]
# =============================================================================
set -euo pipefail

# --- Colors ---
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
BOLD="\033[1m"
RESET="\033[0m"

log_info()  { echo -e "${BLUE}[INFO]${RESET}  $*"; }
log_pass()  { echo -e "${GREEN}[PASS]${RESET}  $*"; }
log_fail()  { echo -e "${RED}[FAIL]${RESET}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_step()  { echo -e "\n${BOLD}>>> $*${RESET}"; }

# --- Configuration ---
ROLLBACK=false
TRAEFIK_DIR=""

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rollback) ROLLBACK=true; shift ;;
        *) TRAEFIK_DIR="$1"; shift ;;
    esac
done

TRAEFIK_DIR="${TRAEFIK_DIR:-/opt/traefik}"
BACKUP_DIR="${TRAEFIK_DIR}/backups/phase6-$(date +%Y%m%d-%H%M%S)"

# LE URLs
LE_STAGING="https://acme-staging-v02.api.letsencrypt.org/directory"
LE_PRODUCTION="https://acme-v02.api.letsencrypt.org/directory"

# Detect config file
TRAEFIK_YML=""
for f in "${TRAEFIK_DIR}/traefik.yml" "${TRAEFIK_DIR}/traefik.yaml" "${TRAEFIK_DIR}/traefik.toml"; do
    if [ -f "${f}" ]; then
        TRAEFIK_YML="${f}"
        break
    fi
done

# Detect compose file
COMPOSE_FILE=""
for f in "${TRAEFIK_DIR}/docker-compose.yml" "${TRAEFIK_DIR}/docker-compose.yaml" "${TRAEFIK_DIR}/compose.yml" "${TRAEFIK_DIR}/compose.yaml"; do
    if [ -f "${f}" ]; then
        COMPOSE_FILE="${f}"
        break
    fi
done

# ==========================================================================
# ROLLBACK MODE
# ==========================================================================
if [ "${ROLLBACK}" = true ]; then
    log_step "ROLLBACK MODE"

    # Find most recent backup
    LATEST_BACKUP=$(ls -td "${TRAEFIK_DIR}/backups/phase6-"* 2>/dev/null | head -1 || echo "")

    if [ -z "${LATEST_BACKUP}" ]; then
        log_fail "No Phase 6 backup found in ${TRAEFIK_DIR}/backups/"
        echo ""
        echo "Manual rollback options:"
        echo "  1. Restore Proxmox snapshot: qm rollback <VMID> pre-phase6"
        echo "  2. Manually restore config from backup"
        exit 1
    fi

    echo "  Found backup: ${LATEST_BACKUP}"
    echo ""
    echo "  Files to restore:"
    ls -la "${LATEST_BACKUP}/" 2>/dev/null | sed 's/^/    /'
    echo ""

    read -rp "  Restore from this backup? [y/N] " confirm
    if [[ "${confirm}" != [yY] ]]; then
        echo "  Rollback cancelled."
        exit 0
    fi

    # Stop Traefik
    log_info "Stopping Traefik..."
    if [ -n "${COMPOSE_FILE}" ]; then
        docker compose -f "${COMPOSE_FILE}" down 2>/dev/null || true
    else
        docker stop traefik 2>/dev/null || true
    fi

    # Restore files
    if [ -f "${LATEST_BACKUP}/traefik-config.bak" ] && [ -n "${TRAEFIK_YML}" ]; then
        cp "${LATEST_BACKUP}/traefik-config.bak" "${TRAEFIK_YML}"
        log_pass "Restored: ${TRAEFIK_YML}"
    fi

    if [ -f "${LATEST_BACKUP}/acme.json.bak" ]; then
        cp "${LATEST_BACKUP}/acme.json.bak" "${TRAEFIK_DIR}/acme.json"
        chmod 600 "${TRAEFIK_DIR}/acme.json"
        log_pass "Restored: ${TRAEFIK_DIR}/acme.json"
    fi

    # Start Traefik
    log_info "Starting Traefik..."
    if [ -n "${COMPOSE_FILE}" ]; then
        docker compose -f "${COMPOSE_FILE}" up -d
    else
        docker start traefik 2>/dev/null || log_warn "Could not auto-start — start Traefik manually"
    fi

    echo ""
    log_pass "Rollback complete. Traefik restored to staging configuration."
    echo ""
    echo "  Alternative: Restore Proxmox snapshot for full system rollback:"
    echo "    qm rollback <VMID> pre-phase6"
    exit 0
fi

# ==========================================================================
# FORWARD MODE — Staging → Production
# ==========================================================================
echo "============================================================"
echo "  Phase 6 — Let's Encrypt: Staging → Production"
echo "  Host: $(hostname)"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Traefik dir: ${TRAEFIK_DIR}"
echo "============================================================"
echo ""

# --- Preflight Checks ---
log_step "Step 0: Preflight Validation"

if [ -z "${TRAEFIK_YML}" ]; then
    log_fail "No Traefik config found in ${TRAEFIK_DIR}"
    echo "  Expected: traefik.yml, traefik.yaml, or traefik.toml"
    exit 1
fi
log_pass "Config: ${TRAEFIK_YML}"

if [ -n "${COMPOSE_FILE}" ]; then
    log_pass "Compose: ${COMPOSE_FILE}"
else
    log_warn "No compose file found — will use docker stop/start"
fi

# Verify staging is current
if grep -q "staging" "${TRAEFIK_YML}" 2>/dev/null; then
    CURRENT_CA=$(grep -o 'https://[^ "]*' "${TRAEFIK_YML}" | grep -i "acme\|letsencrypt" | head -1 || echo "unknown")
    log_pass "Current CA: ${CURRENT_CA} (staging)"
elif grep -q "acme-v02.api.letsencrypt.org" "${TRAEFIK_YML}" 2>/dev/null; then
    log_warn "Config already points to PRODUCTION"
    read -rp "  Continue anyway? [y/N] " confirm
    if [[ "${confirm}" != [yY] ]]; then
        echo "  Aborted."
        exit 0
    fi
else
    log_warn "Could not detect current caServer — proceeding with caution"
fi

# Verify LE Production is reachable
if curl -sf --connect-timeout 5 "${LE_PRODUCTION}" > /dev/null 2>&1; then
    log_pass "LE Production API reachable"
else
    log_fail "LE Production API unreachable — check network"
    exit 1
fi

# --- Confirm ---
echo ""
echo -e "${BOLD}  This will:${RESET}"
echo "    1. Stop Traefik"
echo "    2. Switch caServer from Staging → Production"
echo "    3. Delete staging acme.json (staging certs are untrusted)"
echo "    4. Create fresh acme.json"
echo "    5. Start Traefik (new production certs will be issued)"
echo ""
echo -e "${YELLOW}  LE Rate Limits apply after this switch.${RESET}"
echo -e "${YELLOW}  Ensure you have a Proxmox snapshot before proceeding.${RESET}"
echo ""
read -rp "  Proceed? [y/N] " confirm
if [[ "${confirm}" != [yY] ]]; then
    echo "  Aborted."
    exit 0
fi

# --- Step 1: Backup ---
log_step "Step 1: Backup current state"

mkdir -p "${BACKUP_DIR}"

cp "${TRAEFIK_YML}" "${BACKUP_DIR}/traefik-config.bak"
log_pass "Backed up: ${TRAEFIK_YML}"

if [ -f "${TRAEFIK_DIR}/acme.json" ]; then
    cp "${TRAEFIK_DIR}/acme.json" "${BACKUP_DIR}/acme.json.bak"
    ACME_SIZE=$(stat -c%s "${TRAEFIK_DIR}/acme.json" 2>/dev/null || echo "0")
    log_pass "Backed up: acme.json (${ACME_SIZE} bytes)"
else
    log_warn "No acme.json to back up"
fi

# Back up compose file too
if [ -n "${COMPOSE_FILE}" ]; then
    cp "${COMPOSE_FILE}" "${BACKUP_DIR}/docker-compose.bak"
    log_pass "Backed up: ${COMPOSE_FILE}"
fi

log_pass "Backup stored in: ${BACKUP_DIR}"

# --- Step 2: Stop Traefik ---
log_step "Step 2: Stop Traefik"

if [ -n "${COMPOSE_FILE}" ]; then
    docker compose -f "${COMPOSE_FILE}" down
else
    docker stop traefik 2>/dev/null || true
fi

# Verify stopped
sleep 2
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi traefik; then
    log_fail "Traefik still running — stop manually before proceeding"
    exit 1
fi
log_pass "Traefik stopped"

# --- Step 3: Switch caServer ---
log_step "Step 3: Switch caServer to Production"

# Handle both YAML and TOML formats
if [[ "${TRAEFIK_YML}" == *.toml ]]; then
    # TOML format
    sed -i "s|${LE_STAGING}|${LE_PRODUCTION}|g" "${TRAEFIK_YML}"
    # Also handle without full URL
    sed -i 's|acme-staging-v02\.api\.letsencrypt\.org|acme-v02.api.letsencrypt.org|g' "${TRAEFIK_YML}"
else
    # YAML format
    sed -i "s|${LE_STAGING}|${LE_PRODUCTION}|g" "${TRAEFIK_YML}"
    # Also handle without full URL
    sed -i 's|acme-staging-v02\.api\.letsencrypt\.org|acme-v02.api.letsencrypt.org|g' "${TRAEFIK_YML}"
fi

# Verify the change
if grep -q "acme-v02.api.letsencrypt.org" "${TRAEFIK_YML}" && \
   ! grep -q "staging" "${TRAEFIK_YML}"; then
    log_pass "caServer switched to Production"
else
    log_warn "Verify the switch manually: grep -i acme ${TRAEFIK_YML}"
fi

# Show the relevant section
echo ""
echo "  Config diff (caServer lines):"
grep -n -i "caserver\|acme.*letsencrypt\|certificatesresolvers" "${TRAEFIK_YML}" 2>/dev/null | sed 's/^/    /'
echo ""

# --- Step 4: Reset acme.json ---
log_step "Step 4: Reset acme.json"

rm -f "${TRAEFIK_DIR}/acme.json"
touch "${TRAEFIK_DIR}/acme.json"
chmod 600 "${TRAEFIK_DIR}/acme.json"
log_pass "Fresh acme.json created with permissions 600"

# --- Step 5: Start Traefik ---
log_step "Step 5: Start Traefik"

if [ -n "${COMPOSE_FILE}" ]; then
    docker compose -f "${COMPOSE_FILE}" up -d
else
    docker start traefik 2>/dev/null || {
        log_fail "Could not auto-start Traefik — start manually"
        exit 1
    }
fi

# Wait for Traefik to initialize
echo "  Waiting for Traefik to start..."
sleep 5

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi traefik; then
    log_pass "Traefik started"
else
    log_fail "Traefik failed to start — check logs:"
    echo "    docker logs traefik --tail 20"
    echo ""
    echo "  To rollback:"
    echo "    $0 --rollback ${TRAEFIK_DIR}"
    exit 1
fi

# --- Step 6: Verify Certificates ---
log_step "Step 6: Verify Production Certificates"

echo "  Waiting for certificate issuance (up to 60 seconds)..."
echo ""

# Wait for acme.json to populate
CERT_OK=false
for i in $(seq 1 12); do
    sleep 5
    ACME_SIZE=$(stat -c%s "${TRAEFIK_DIR}/acme.json" 2>/dev/null || echo "0")
    if [ "${ACME_SIZE}" -gt 100 ]; then
        log_pass "acme.json populated (${ACME_SIZE} bytes) after $((i * 5))s"
        CERT_OK=true
        break
    fi
    echo "  ... waiting (${ACME_SIZE} bytes after $((i * 5))s)"
done

if [ "${CERT_OK}" = false ]; then
    log_warn "acme.json still empty after 60s — certificate issuance may be pending"
    echo ""
    echo "  Check Traefik logs for details:"
    echo "    docker logs traefik --tail 30"
    echo ""
    echo "  Common issues:"
    echo "    - DNS not pointing to this server"
    echo "    - Port 80/443 not reachable from internet"
    echo "    - LE rate limit reached"
fi

# Check Traefik logs for errors
echo ""
echo "  Recent Traefik logs:"
docker logs traefik --tail 15 2>&1 | sed 's/^/    /' || echo "    (could not read logs)"

# ==========================================================================
# Summary
# ==========================================================================
echo ""
echo "============================================================"
echo "  Phase 6 — Summary"
echo "============================================================"
echo ""
echo "  Config:     ${TRAEFIK_YML}"
echo "  caServer:   ${LE_PRODUCTION}"
echo "  acme.json:  ${TRAEFIK_DIR}/acme.json"
echo "  Backup:     ${BACKUP_DIR}"
echo ""

if [ "${CERT_OK}" = true ]; then
    echo -e "  ${GREEN}${BOLD}PRODUCTION CERTIFICATES ACTIVE${RESET}"
    echo ""
    echo "  Verify in browser: check the padlock icon — should show"
    echo "  'Let's Encrypt' as issuer (not 'STAGING')."
else
    echo -e "  ${YELLOW}${BOLD}CERTIFICATES PENDING — Monitor logs${RESET}"
fi

echo ""
echo "  Rollback command:"
echo "    $0 --rollback ${TRAEFIK_DIR}"
echo ""
echo "  Proxmox snapshot rollback:"
echo "    qm rollback <VMID> pre-phase6"
echo ""
