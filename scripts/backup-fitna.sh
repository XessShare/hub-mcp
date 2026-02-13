#!/usr/bin/env bash
# =============================================================================
# backup-fitna.sh — Automated backup for ~/home/fitna (FitnaAI project data)
#
# Features:
#   - Recursive tar.gz backup with date-versioned filenames
#   - Automatic cleanup of backups older than 30 days
#   - Pre-flight checks (directory exists, write permissions)
#   - Structured logging to logs/backup-fitna.log
#   - Idempotent: safe to run repeatedly without data loss
#   - Non-root execution (no elevated permissions required)
#
# Usage:
#   ./scripts/backup-fitna.sh                    # Use defaults
#   SOURCE_DIR=/custom/path ./scripts/backup-fitna.sh
#   RETENTION_DAYS=7 ./scripts/backup-fitna.sh   # Keep only 7 days
#
# Cron example (daily at 02:00):
#   0 2 * * * /opt/fitnaai/scripts/backup-fitna.sh
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (override via environment)
# ---------------------------------------------------------------------------
SOURCE_DIR="${SOURCE_DIR:-$HOME/home/fitna}"
BACKUP_DIR="${BACKUP_DIR:-/mnt/data/backups/fitnaai}"
LOG_DIR="${LOG_DIR:-$(dirname "$0")/../logs}"
LOG_FILE="${LOG_DIR}/backup-fitna.log"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILENAME="fitna-backup-${DATE_TAG}.tar.gz"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
mkdir -p "${LOG_DIR}"

log() {
    local level="$1"; shift
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S')  [${level}]  $*"
    echo "${msg}" | tee -a "${LOG_FILE}"
}

log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
preflight() {
    log_info "=== Backup started ==="
    log_info "Source:    ${SOURCE_DIR}"
    log_info "Target:   ${BACKUP_DIR}/${BACKUP_FILENAME}"
    log_info "Retention: ${RETENTION_DAYS} days"

    # 1. Source directory exists
    if [ ! -d "${SOURCE_DIR}" ]; then
        log_error "Source directory does not exist: ${SOURCE_DIR}"
        exit 1
    fi

    # 2. Source is readable
    if [ ! -r "${SOURCE_DIR}" ]; then
        log_error "Source directory is not readable: ${SOURCE_DIR}"
        exit 1
    fi

    # 3. Backup directory exists or can be created
    if ! mkdir -p "${BACKUP_DIR}" 2>/dev/null; then
        log_error "Cannot create backup directory: ${BACKUP_DIR}"
        exit 1
    fi

    # 4. Backup directory is writable
    if [ ! -w "${BACKUP_DIR}" ]; then
        log_error "Backup directory is not writable: ${BACKUP_DIR}"
        exit 1
    fi

    log_info "Pre-flight checks passed"
}

# ---------------------------------------------------------------------------
# Create backup
# ---------------------------------------------------------------------------
create_backup() {
    local target="${BACKUP_DIR}/${BACKUP_FILENAME}"

    log_info "Creating backup archive..."
    if tar -czf "${target}" -C "$(dirname "${SOURCE_DIR}")" "$(basename "${SOURCE_DIR}")"; then
        local size
        size="$(du -h "${target}" | cut -f1)"
        log_info "Backup created successfully: ${target} (${size})"
    else
        log_error "tar failed with exit code $?"
        exit 1
    fi

    # Verify archive integrity
    if tar -tzf "${target}" > /dev/null 2>&1; then
        log_info "Archive integrity check passed"
    else
        log_error "Archive integrity check FAILED — file may be corrupt"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Cleanup old backups
# ---------------------------------------------------------------------------
cleanup_old_backups() {
    log_info "Cleaning up backups older than ${RETENTION_DAYS} days..."
    local count=0
    while IFS= read -r -d '' old_file; do
        log_info "  Removing: $(basename "${old_file}")"
        rm -f "${old_file}"
        count=$((count + 1))
    done < <(find "${BACKUP_DIR}" -maxdepth 1 -name "fitna-backup-*.tar.gz" \
                  -type f -mtime "+${RETENTION_DAYS}" -print0 2>/dev/null)

    if [ "${count}" -eq 0 ]; then
        log_info "No old backups to remove"
    else
        log_info "Removed ${count} old backup(s)"
    fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
summary() {
    local total
    total="$(find "${BACKUP_DIR}" -maxdepth 1 -name "fitna-backup-*.tar.gz" -type f | wc -l)"
    local disk_usage
    disk_usage="$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1)"
    log_info "--- Summary ---"
    log_info "  Total backups: ${total}"
    log_info "  Disk usage:    ${disk_usage}"
    log_info "=== Backup finished ==="
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    preflight
    create_backup
    cleanup_old_backups
    summary
}

main "$@"
