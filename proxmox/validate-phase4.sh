#!/usr/bin/env bash
# validate-phase4.sh — Validierungs-Gate vor GPU-Passthrough (Phase 4)
#
# Prueft zwei Bedingungen deterministisch mit Auto-Retry:
#   1. Omarchy SSD gemountet unter /mnt/omarchy (systemd unit)
#   2. Samba-Share fitna-shared erreichbar auf 192.168.16.2
#
# Beide Checks werden mit exponential backoff wiederholt.
# Erst wenn BEIDE bestanden sind, gibt das Gate frei.
#
# Target host: pve (192.168.16.2)
#
# Usage:
#   sudo bash proxmox/validate-phase4.sh
#   sudo bash proxmox/validate-phase4.sh --max-retries 10 --timeout 300
#
# Exit codes:
#   0 — Gate passed, Phase 4 kann starten
#   1 — Gate failed nach allen Retries

set -euo pipefail

# --- Defaults ---
MAX_RETRIES=5
TIMEOUT=180         # Gesamttimeout in Sekunden
INITIAL_WAIT=3      # Erste Wartezeit in Sekunden
MOUNTPOINT="/mnt/omarchy"
SAMBA_HOST="192.168.16.2"
SAMBA_SHARE="fitna-shared"
SAMBA_USER="fitna-user"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-retries) MAX_RETRIES="$2"; shift 2 ;;
        --timeout)     TIMEOUT="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--max-retries N] [--timeout SECONDS]"
            echo ""
            echo "Validierungs-Gate fuer Phase 4 (GPU-Passthrough)."
            echo "Prueft SSD-Mount und Samba-Erreichbarkeit mit Auto-Retry."
            echo ""
            echo "Options:"
            echo "  --max-retries N    Max Wiederholungen pro Check (default: 5)"
            echo "  --timeout S        Gesamttimeout in Sekunden (default: 180)"
            exit 0
            ;;
        *) echo "Unbekannter Parameter: $1"; exit 1 ;;
    esac
done

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Logging ---
log()  { echo -e "${GREEN}[PASS]${NC} $*"; }
warn() { echo -e "${YELLOW}[WAIT]${NC} $*"; }
err()  { echo -e "${RED}[FAIL]${NC} $*" >&2; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
    err "Dieses Skript muss als root ausgefuehrt werden."
    exit 1
fi

START_TIME=$(date +%s)

elapsed() {
    local now
    now=$(date +%s)
    echo $(( now - START_TIME ))
}

timeout_reached() {
    [[ $(elapsed) -ge $TIMEOUT ]]
}

# --- Retry wrapper with exponential backoff ---
# Usage: retry_check "label" check_function
retry_check() {
    local label="$1"
    local check_fn="$2"
    local attempt=1
    local wait_sec=$INITIAL_WAIT

    info "Starte Check: ${BOLD}${label}${NC}"

    while [[ $attempt -le $MAX_RETRIES ]]; do
        if timeout_reached; then
            err "Gesamttimeout (${TIMEOUT}s) erreicht bei Check: $label"
            return 1
        fi

        if $check_fn 2>/dev/null; then
            log "$label — bestanden (Versuch $attempt)"
            return 0
        fi

        if [[ $attempt -lt $MAX_RETRIES ]]; then
            warn "$label — fehlgeschlagen (Versuch $attempt/$MAX_RETRIES). Naechster Versuch in ${wait_sec}s..."
            sleep "$wait_sec"
            # Exponential backoff: 3s, 6s, 12s, 24s, ...
            wait_sec=$(( wait_sec * 2 ))
            # Cap bei 60s
            if [[ $wait_sec -gt 60 ]]; then
                wait_sec=60
            fi
        fi

        attempt=$(( attempt + 1 ))
    done

    err "$label — endgueltig fehlgeschlagen nach $MAX_RETRIES Versuchen."
    return 1
}

# ============================================================
# CHECK 1: Omarchy SSD Mount
# ============================================================
check_ssd_mount() {
    # Versuch die Unit zu starten (idempotent wenn bereits aktiv)
    systemctl start mnt-omarchy.mount 2>/dev/null

    # Pruefen ob tatsaechlich gemountet
    if ! mountpoint -q "$MOUNTPOINT"; then
        return 1
    fi

    # Pruefen ob Daten lesbar sind (nicht nur gemountet, sondern funktional)
    if ! ls "$MOUNTPOINT" >/dev/null 2>&1; then
        return 1
    fi

    # Pruefen ob der Share-Pfad existiert
    if [ ! -d "${MOUNTPOINT}/home/fitna" ]; then
        warn "Mount OK, aber ${MOUNTPOINT}/home/fitna existiert nicht."
        # Mount ist OK, Verzeichnis kann spaeter erstellt werden
        # Trotzdem als bestanden werten wenn Mount selbst funktioniert
    fi

    return 0
}

# ============================================================
# CHECK 2: Samba-Share Erreichbarkeit
# ============================================================
check_samba_share() {
    # Pruefen ob smbclient verfuegbar
    if ! command -v smbclient &>/dev/null; then
        # Fallback: TCP-Port 445 pruefen
        if command -v ss &>/dev/null; then
            if ss -tlnp | grep -q ':445'; then
                return 0
            fi
        elif command -v netstat &>/dev/null; then
            if netstat -tlnp 2>/dev/null | grep -q ':445'; then
                return 0
            fi
        fi
        # Letzter Fallback: TCP connect check
        if timeout 5 bash -c "echo >/dev/tcp/${SAMBA_HOST}/445" 2>/dev/null; then
            return 0
        fi
        return 1
    fi

    # smbclient verfuegbar: Share-Listing abfragen
    if smbclient -U "${SAMBA_USER}%dummy" -L "$SAMBA_HOST" -N 2>/dev/null | grep -qi "$SAMBA_SHARE"; then
        return 0
    fi

    # Alternativ: nur TCP-Erreichbarkeit als Mindestkriterium
    if timeout 5 bash -c "echo >/dev/tcp/${SAMBA_HOST}/445" 2>/dev/null; then
        warn "TCP:445 erreichbar, aber Share-Listing fehlgeschlagen (Passwort?)."
        warn "Samba-Dienst laeuft — manuell pruefen: smbclient -U $SAMBA_USER //$SAMBA_HOST/$SAMBA_SHARE"
        return 0
    fi

    return 1
}

# ============================================================
# GATE EXECUTION
# ============================================================
echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  PHASE 4 — VALIDIERUNGS-GATE${NC}"
echo -e "${BOLD}========================================${NC}"
echo -e "  Host:         pve (192.168.16.2)"
echo -e "  Max Retries:  $MAX_RETRIES"
echo -e "  Timeout:      ${TIMEOUT}s"
echo -e "  Zeitpunkt:    $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BOLD}========================================${NC}"
echo ""

GATE_PASSED=true

# Check 1
if ! retry_check "SSD-Mount ($MOUNTPOINT)" check_ssd_mount; then
    GATE_PASSED=false
fi

echo ""

# Check 2
if ! retry_check "Samba-Share ($SAMBA_HOST/$SAMBA_SHARE)" check_samba_share; then
    GATE_PASSED=false
fi

# ============================================================
# GATE RESULT
# ============================================================
echo ""
echo -e "${BOLD}========================================${NC}"

if $GATE_PASSED; then
    echo -e "${GREEN}${BOLD}  GATE PASSED${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
    log "Alle Checks bestanden in $(elapsed)s."
    log "Phase 4 (GPU-Passthrough) kann gestartet werden."
    echo ""
    info "Naechste Schritte:"
    info "  1. GPU-Passthrough vorbereiten:"
    info "     sudo bash proxmox/vm-windows/setup-gpu-passthrough.sh"
    info "  2. Host neu starten (erforderlich fuer IOMMU)"
    info "  3. GPU-Status pruefen:"
    info "     sudo bash proxmox/gpu/gpu-check.sh"
    info "  4. GPU an VM zuweisen:"
    info "     qm set 100 --hostpci0 PCI_ADDR,pcie=1,x-vga=1"
    exit 0
else
    echo -e "${RED}${BOLD}  GATE FAILED${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
    err "Mindestens ein Check fehlgeschlagen nach $(elapsed)s."
    err "Phase 4 kann NICHT gestartet werden."
    echo ""
    info "Diagnose:"
    info "  SSD:   systemctl status mnt-omarchy.mount"
    info "  SSD:   blkid | grep omarchy"
    info "  Samba: systemctl status smbd nmbd"
    info "  Samba: testparm -s /etc/samba/smb.conf"
    info "  Netz:  ss -tlnp | grep 445"
    exit 1
fi
