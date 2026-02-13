#!/usr/bin/env bash
# =============================================================================
# restore-fitna.sh — Restore a FitnaAI backup archive
#
# Restores from a specific backup or the most recent one.
# Always creates a safety snapshot of the current state before restoring.
#
# Usage:
#   ./scripts/restore-fitna.sh                           # Latest backup
#   ./scripts/restore-fitna.sh fitna-backup-20250215.tar.gz  # Specific file
#   RESTORE_TARGET=/custom/path ./scripts/restore-fitna.sh   # Custom target
#
# Safety:
#   - Creates a pre-restore snapshot before overwriting anything
#   - Validates archive integrity before extraction
#   - Dry-run mode available via DRY_RUN=1
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BACKUP_DIR="${BACKUP_DIR:-/mnt/data/backups/fitnaai}"
RESTORE_TARGET="${RESTORE_TARGET:-$HOME/home/fitna}"
LOG_DIR="${LOG_DIR:-$(dirname "$0")/../logs}"
LOG_FILE="${LOG_DIR}/restore-fitna.log"
DRY_RUN="${DRY_RUN:-0}"
ARCHIVE_NAME="${1:-}"

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
# Resolve archive
# ---------------------------------------------------------------------------
resolve_archive() {
    if [ -n "${ARCHIVE_NAME}" ]; then
        # Specific archive requested
        if [ -f "${BACKUP_DIR}/${ARCHIVE_NAME}" ]; then
            ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"
        elif [ -f "${ARCHIVE_NAME}" ]; then
            ARCHIVE_PATH="${ARCHIVE_NAME}"
        else
            log_error "Archive not found: ${ARCHIVE_NAME}"
            log_error "Looked in: ${BACKUP_DIR}/ and current directory"
            exit 1
        fi
    else
        # Find the most recent backup
        ARCHIVE_PATH="$(find "${BACKUP_DIR}" -maxdepth 1 -name "fitna-backup-*.tar.gz" \
                            -type f -printf '%T@ %p\n' 2>/dev/null \
                        | sort -rn | head -1 | cut -d' ' -f2-)"
        if [ -z "${ARCHIVE_PATH}" ]; then
            log_error "No backups found in ${BACKUP_DIR}"
            exit 1
        fi
    fi

    log_info "Selected archive: ${ARCHIVE_PATH}"
}

# ---------------------------------------------------------------------------
# Validate archive
# ---------------------------------------------------------------------------
validate_archive() {
    log_info "Validating archive integrity..."
    if ! tar -tzf "${ARCHIVE_PATH}" > /dev/null 2>&1; then
        log_error "Archive integrity check FAILED — file is corrupt"
        exit 1
    fi

    local size
    size="$(du -h "${ARCHIVE_PATH}" | cut -f1)"
    local files
    files="$(tar -tzf "${ARCHIVE_PATH}" | wc -l)"
    log_info "Archive OK: ${size}, ${files} entries"
}

# ---------------------------------------------------------------------------
# Pre-restore safety snapshot
# ---------------------------------------------------------------------------
safety_snapshot() {
    if [ ! -d "${RESTORE_TARGET}" ]; then
        log_info "Restore target does not exist yet — no snapshot needed"
        return
    fi

    local snapshot_name="fitna-pre-restore-$(date +%Y%m%d-%H%M%S).tar.gz"
    local snapshot_path="${BACKUP_DIR}/${snapshot_name}"

    log_info "Creating safety snapshot: ${snapshot_name}"
    if tar -czf "${snapshot_path}" -C "$(dirname "${RESTORE_TARGET}")" "$(basename "${RESTORE_TARGET}")"; then
        log_info "Safety snapshot saved to: ${snapshot_path}"
    else
        log_error "Failed to create safety snapshot — aborting restore"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Restore
# ---------------------------------------------------------------------------
do_restore() {
    local parent_dir
    parent_dir="$(dirname "${RESTORE_TARGET}")"
    mkdir -p "${parent_dir}"

    if [ "${DRY_RUN}" = "1" ]; then
        log_info "[DRY RUN] Would extract to: ${parent_dir}"
        log_info "[DRY RUN] Archive contents:"
        tar -tzf "${ARCHIVE_PATH}" | head -20 | while read -r line; do
            log_info "  ${line}"
        done
        log_info "[DRY RUN] No files were modified"
        return
    fi

    log_info "Restoring to: ${RESTORE_TARGET}"
    if tar -xzf "${ARCHIVE_PATH}" -C "${parent_dir}"; then
        log_info "Restore completed successfully"
    else
        log_error "tar extraction failed with exit code $?"
        exit 1
    fi

    # Verify restore
    if [ -d "${RESTORE_TARGET}" ]; then
        local count
        count="$(find "${RESTORE_TARGET}" -type f | wc -l)"
        log_info "Verification: ${count} files restored to ${RESTORE_TARGET}"
    else
        log_error "Restore target directory not found after extraction"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_info "=== Restore started ==="
    resolve_archive
    validate_archive
    safety_snapshot
    do_restore
    log_info "=== Restore finished ==="
}

main "$@"
