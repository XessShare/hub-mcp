#!/usr/bin/env bash
# backup-user-data.sh — Backup user-created data from Omarchy SSD to pve-ryzen 2TB HDD
#
# Copies all self-created files from /mnt/omarchy/@home/fitna/ on pve (16.2)
# to the 2TB HDD on pve-ryzen (17.1) via rsync over SSH.
#
# Usage (run as root on pve):
#   bash backup-user-data.sh [--dry-run] [--skip-desktop]
#
# Prerequisites:
#   - Omarchy SSD mounted at /mnt/omarchy on pve
#   - SSH key-based access from pve to pve-ryzen (root@192.168.17.1)
#   - 2TB HDD mounted on pve-ryzen (auto-detected or set via BACKUP_HDD_MOUNT)
#
# What gets backed up:
#   - FItnaai/ (project code, configs, tests, docs)
#   - .secrets/ (environment files, tokens)
#   - .ssh/ (SSH keys)
#   - .gnupg/ (GPG keys)
#   - .git-credentials (GitHub tokens — ROTATE AFTER BACKUP!)
#   - Documents/, Pictures/, Videos/, Business/
#   - homelab/, J-Jeco/, content-pipeline/, scripts/
#   - Desktop/ (466GB — use --skip-desktop to exclude)
#   - Config files (.claude.json, .zshrc, .bash_history, etc.)
#
# What gets EXCLUDED:
#   - .venv/, node_modules/, __pycache__/ (regeneratable)
#   - .cache/, .ruff_cache/, .pytest_cache/ (caches)
#   - .mozilla/, .config/chromium/ (browser data)
#   - .local/share/Trash/ (trash)
#   - .ollama/models/ (re-downloadable, multi-GB)
#   - *.iso, *.qcow2, *.vmdk, *.vdi (VM images — separate backup)
#   - Omarchy/Linux system files (not present in user home)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SOURCE="/mnt/omarchy/@home/fitna/"
REMOTE_HOST="192.168.17.1"
REMOTE_USER="root"

# Auto-detect 2TB HDD mount on pve-ryzen, or set manually
BACKUP_HDD_MOUNT="${BACKUP_HDD_MOUNT:-}"
BACKUP_DIR_NAME="fitna-backup"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOGFILE="/var/log/backup-user-data-${TIMESTAMP}.log"

DRY_RUN=""
SKIP_DESKTOP=""
SKIP_LARGE_MEDIA=""

# ============================================================================
# Argument parsing
# ============================================================================

for arg in "$@"; do
    case "$arg" in
        --dry-run)     DRY_RUN="--dry-run" ;;
        --skip-desktop) SKIP_DESKTOP="1" ;;
        --skip-media)  SKIP_LARGE_MEDIA="1" ;;
        --help|-h)
            head -30 "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $arg"
            echo "Usage: $0 [--dry-run] [--skip-desktop] [--skip-media]"
            exit 1
            ;;
    esac
done

# ============================================================================
# Functions
# ============================================================================

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOGFILE"
}

die() {
    log "FATAL: $1"
    exit 1
}

check_ssh() {
    log "Checking SSH connectivity to ${REMOTE_USER}@${REMOTE_HOST}..."
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${REMOTE_USER}@${REMOTE_HOST}" "echo ok" >/dev/null 2>&1; then
        die "Cannot SSH to ${REMOTE_USER}@${REMOTE_HOST}. Set up key-based auth first:
  ssh-copy-id ${REMOTE_USER}@${REMOTE_HOST}"
    fi
    log "SSH OK."
}

detect_hdd() {
    if [[ -n "$BACKUP_HDD_MOUNT" ]]; then
        log "Using manually set HDD mount: $BACKUP_HDD_MOUNT"
        return
    fi

    log "Auto-detecting 2TB HDD on ${REMOTE_HOST}..."

    # Find mounted filesystems >= 1.5TB that aren't the root/boot/LVM partitions
    local hdd_info
    hdd_info=$(ssh -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" \
        "lsblk -bnro NAME,SIZE,MOUNTPOINT,TYPE | awk '\$2 > 1500000000000 && \$3 != \"\" && \$4 == \"part\"' | head -1" 2>/dev/null || true)

    if [[ -z "$hdd_info" ]]; then
        # Fallback: check df for large mounted volumes
        hdd_info=$(ssh -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" \
            "df -B1 --output=target,size | awk 'NR>1 && \$2 > 1500000000000 && \$1 != \"/\"' | head -1" 2>/dev/null || true)

        if [[ -z "$hdd_info" ]]; then
            log "WARNING: Could not auto-detect 2TB HDD."
            log "Available block devices on ${REMOTE_HOST}:"
            ssh "${REMOTE_USER}@${REMOTE_HOST}" "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT" 2>&1 | tee -a "$LOGFILE"
            echo ""
            log "Please either:"
            log "  1. Mount the 2TB HDD on ${REMOTE_HOST} and re-run"
            log "  2. Set BACKUP_HDD_MOUNT=/path/to/mount and re-run"
            die "2TB HDD not found or not mounted on ${REMOTE_HOST}"
        fi

        BACKUP_HDD_MOUNT="$(echo "$hdd_info" | awk '{print $1}')"
    else
        BACKUP_HDD_MOUNT="$(echo "$hdd_info" | awk '{print $3}')"
    fi

    log "Detected 2TB HDD at: ${BACKUP_HDD_MOUNT}"
}

check_remote_space() {
    log "Checking available space on ${REMOTE_HOST}:${BACKUP_HDD_MOUNT}..."

    local avail_bytes
    avail_bytes=$(ssh "${REMOTE_USER}@${REMOTE_HOST}" \
        "df -B1 --output=avail '${BACKUP_HDD_MOUNT}' | tail -1" 2>/dev/null | tr -d ' ')

    local avail_gb=$(( avail_bytes / 1073741824 ))
    log "Available space: ${avail_gb} GB"

    if (( avail_gb < 50 )); then
        die "Less than 50 GB free on ${BACKUP_HDD_MOUNT}. Aborting."
    fi
}

check_source() {
    if [[ ! -d "$SOURCE" ]]; then
        die "Source not found: $SOURCE — Is the Omarchy SSD mounted?"
    fi
    log "Source exists: $SOURCE"
}

build_excludes() {
    local excludes=(
        # Regeneratable / caches
        ".venv/"
        "node_modules/"
        "__pycache__/"
        ".cache/"
        ".ruff_cache/"
        ".pytest_cache/"
        "*.pyc"
        ".mypy_cache/"
        "*.egg-info/"

        # Browser data (large, not user-created)
        ".mozilla/"
        ".config/chromium/"
        ".config/google-chrome/"

        # Trash
        ".local/share/Trash/"

        # Ollama models (re-downloadable, multi-GB)
        ".ollama/models/"

        # Package manager caches
        ".npm/_cacache/"
        ".cargo/registry/"
        ".cargo/git/"

        # Thumbnails and caches
        ".thumbnails/"
        ".local/share/recently-used.xbel"

        # Logs that can be regenerated
        ".xsession-errors"

        # Temp files
        "*.tmp"
        "*.swp"
        "*.swo"
        "*~"

        # VM disk images (separate backup via vzdump)
        "*.qcow2"
        "*.vmdk"
        "*.vdi"
        "*.raw"

        # ISO files (re-downloadable)
        "*.iso"

        # Git internal objects (we keep .git but skip large packfiles if needed)
        # Keeping .git for full repo history
    )

    # Optional: skip Desktop (466GB)
    if [[ -n "$SKIP_DESKTOP" ]]; then
        excludes+=("Desktop/")
        log "SKIPPING Desktop/ (--skip-desktop)"
    fi

    # Optional: skip large media
    if [[ -n "$SKIP_LARGE_MEDIA" ]]; then
        excludes+=("Videos/" "Pictures/" "Music/")
        log "SKIPPING Videos/, Pictures/, Music/ (--skip-media)"
    fi

    # Build rsync exclude arguments
    EXCLUDE_ARGS=""
    for excl in "${excludes[@]}"; do
        EXCLUDE_ARGS="${EXCLUDE_ARGS} --exclude='${excl}'"
    done
}

run_backup() {
    local dest="${BACKUP_HDD_MOUNT}/${BACKUP_DIR_NAME}"

    log "============================================"
    log "BACKUP STARTING"
    log "============================================"
    log "Source:      ${SOURCE}"
    log "Destination: ${REMOTE_USER}@${REMOTE_HOST}:${dest}"
    log "Timestamp:   ${TIMESTAMP}"
    log "Dry run:     ${DRY_RUN:-no}"
    log "Skip Desktop: ${SKIP_DESKTOP:-no}"
    log "Skip Media:  ${SKIP_LARGE_MEDIA:-no}"
    log "============================================"

    # Create destination directory
    ssh "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p '${dest}'"

    # Run rsync
    # -a: archive mode (preserves permissions, timestamps, symlinks, etc.)
    # -v: verbose
    # -z: compress during transfer
    # --progress: show per-file progress
    # --partial: keep partially transferred files
    # --delete: remove files from dest that no longer exist in source
    # --human-readable: human-readable sizes
    # --stats: show transfer statistics
    eval rsync -avz \
        --progress \
        --partial \
        --delete \
        --human-readable \
        --stats \
        ${DRY_RUN} \
        ${EXCLUDE_ARGS} \
        "${SOURCE}" \
        "${REMOTE_USER}@${REMOTE_HOST}:${dest}/" \
        2>&1 | tee -a "$LOGFILE"

    local exit_code=${PIPESTATUS[0]}

    if [[ $exit_code -eq 0 ]]; then
        log "============================================"
        log "BACKUP COMPLETED SUCCESSFULLY"
        log "============================================"

        # Write manifest
        ssh "${REMOTE_USER}@${REMOTE_HOST}" "cat > '${dest}/BACKUP_MANIFEST.txt'" <<EOF
Backup Manifest
===============
Source Host:  pve (192.168.16.2)
Source Path:  ${SOURCE}
Dest Host:    pve-ryzen (${REMOTE_HOST})
Dest Path:    ${dest}
Timestamp:    ${TIMESTAMP}
Dry Run:      ${DRY_RUN:-no}
Skip Desktop: ${SKIP_DESKTOP:-no}
Skip Media:   ${SKIP_LARGE_MEDIA:-no}

Contents:
---------
$(ssh "${REMOTE_USER}@${REMOTE_HOST}" "du -sh '${dest}'/*/ 2>/dev/null | sort -rh | head -30" || true)

Backup performed by: proxmox/backup/backup-user-data.sh
EOF

        log "Manifest written to ${dest}/BACKUP_MANIFEST.txt"
    else
        log "============================================"
        log "ERROR: rsync exited with code ${exit_code}"
        log "============================================"
    fi

    return $exit_code
}

# ============================================================================
# Main
# ============================================================================

log "=== FitnaAI User Data Backup ==="
log "Script: $0"
log "Args: $*"

check_source
check_ssh
detect_hdd
check_remote_space
build_excludes
run_backup

# Post-backup summary
log ""
log "=== POST-BACKUP ACTIONS ==="
log "1. ROTATE GitHub token in .git-credentials (token was compromised)"
log "2. Verify backup: ssh ${REMOTE_USER}@${REMOTE_HOST} 'ls -la ${BACKUP_HDD_MOUNT}/${BACKUP_DIR_NAME}/'"
log "3. Check backup size: ssh ${REMOTE_USER}@${REMOTE_HOST} 'du -sh ${BACKUP_HDD_MOUNT}/${BACKUP_DIR_NAME}/'"
log "4. Test restore of critical file:"
log "   rsync ${REMOTE_USER}@${REMOTE_HOST}:${BACKUP_HDD_MOUNT}/${BACKUP_DIR_NAME}/FItnaai/ /tmp/restore-test/ -av"
log ""
log "Log saved to: ${LOGFILE}"
