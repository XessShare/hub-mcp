#!/usr/bin/env bash
# cleanup-btrfs-snapshots.sh — Remove old btrfs snapshots to free space on Omarchy SSD
#
# Usage (run as root on pve):
#   bash cleanup-btrfs-snapshots.sh [--dry-run] [--keep=N]
#
# Default: keeps the latest 2 snapshots, deletes all older ones.
# With --dry-run: shows what would be deleted without actually deleting.
#
# Background:
#   25 btrfs subvolumes on Omarchy SSD with ~534 GB in snapshot duplicates
#   (.ollama models, .windows images, .lmstudio libs duplicated per snapshot)
#   Cleaning old snapshots (keeping latest 2) should free 400+ GB

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

OMARCHY_MOUNT="/mnt/omarchy"
SNAPSHOT_BASE="${OMARCHY_MOUNT}/@home/.snapshots"
KEEP="${KEEP:-2}"
DRY_RUN=""

for arg in "$@"; do
    case "$arg" in
        --dry-run)    DRY_RUN="1" ;;
        --keep=*)     KEEP="${arg#--keep=}" ;;
        --help|-h)
            head -12 "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $arg"
            echo "Usage: $0 [--dry-run] [--keep=N]"
            exit 1
            ;;
    esac
done

echo "=== btrfs Snapshot Cleanup ==="
echo "Mount:       ${OMARCHY_MOUNT}"
echo "Snapshot dir: ${SNAPSHOT_BASE}"
echo "Keep latest: ${KEEP}"
echo "Dry run:     ${DRY_RUN:-no}"
echo ""

# ============================================================================
# Pre-checks
# ============================================================================

if [[ ! -d "$OMARCHY_MOUNT" ]]; then
    echo "ERROR: ${OMARCHY_MOUNT} not found. Mount the Omarchy SSD first."
    exit 1
fi

if [[ ! -d "$SNAPSHOT_BASE" ]]; then
    echo "ERROR: ${SNAPSHOT_BASE} not found. No snapshots directory."
    exit 1
fi

# Check disk usage before
echo "=== Current disk usage ==="
df -h "${OMARCHY_MOUNT}"
echo ""

# ============================================================================
# Discover snapshots
# ============================================================================

echo "=== Discovering snapshots ==="

# List snapshot directories (numbered), sorted numerically
SNAPSHOTS=()
while IFS= read -r dir; do
    if [[ -d "${dir}/snapshot" ]]; then
        SNAPSHOTS+=("$dir")
    fi
done < <(find "$SNAPSHOT_BASE" -maxdepth 1 -mindepth 1 -type d | sort -t/ -k$(echo "$SNAPSHOT_BASE" | tr -cd '/' | wc -c | xargs -I{} expr {} + 2)n 2>/dev/null || \
         find "$SNAPSHOT_BASE" -maxdepth 1 -mindepth 1 -type d | sort -V)

TOTAL=${#SNAPSHOTS[@]}
echo "Found ${TOTAL} snapshots"

if [[ $TOTAL -le $KEEP ]]; then
    echo "Only ${TOTAL} snapshots, keeping all (keep=${KEEP}). Nothing to delete."
    exit 0
fi

# Determine which to delete and which to keep
DELETE_COUNT=$((TOTAL - KEEP))
TO_DELETE=("${SNAPSHOTS[@]:0:$DELETE_COUNT}")
TO_KEEP=("${SNAPSHOTS[@]:$DELETE_COUNT}")

echo ""
echo "=== Will KEEP (latest ${KEEP}) ==="
for s in "${TO_KEEP[@]}"; do
    snap_name=$(basename "$s")
    snap_size=$(du -sh "${s}/snapshot" 2>/dev/null | cut -f1 || echo "?")
    echo "  [KEEP] #${snap_name} (${snap_size})"
done

echo ""
echo "=== Will DELETE (${DELETE_COUNT} old snapshots) ==="
ESTIMATED_FREE=0
for s in "${TO_DELETE[@]}"; do
    snap_name=$(basename "$s")
    snap_size=$(du -sh "${s}/snapshot" 2>/dev/null | cut -f1 || echo "?")
    echo "  [DELETE] #${snap_name} (${snap_size})"
done

echo ""

# ============================================================================
# Delete snapshots
# ============================================================================

if [[ -n "$DRY_RUN" ]]; then
    echo "=== DRY RUN — no changes made ==="
    echo "Run without --dry-run to actually delete."
    exit 0
fi

echo "=== Deleting ${DELETE_COUNT} snapshots... ==="
echo ""

DELETED=0
FAILED=0

for s in "${TO_DELETE[@]}"; do
    snap_name=$(basename "$s")
    snap_path="${s}/snapshot"

    echo -n "Deleting snapshot #${snap_name}... "

    # Try btrfs subvolume delete first (proper way)
    if btrfs subvolume delete "$snap_path" 2>/dev/null; then
        echo "OK (btrfs subvolume delete)"
        # Also remove the parent directory
        rm -rf "$s" 2>/dev/null || true
        DELETED=$((DELETED + 1))
    else
        # Fallback: some snapshots may have nested subvolumes
        echo ""
        echo "  Trying nested subvolume cleanup..."

        # Delete all nested subvolumes first (deepest first)
        NESTED=$(btrfs subvolume list -o "$snap_path" 2>/dev/null | awk '{print $NF}' | sort -r || true)
        if [[ -n "$NESTED" ]]; then
            while IFS= read -r nested; do
                nested_full="${OMARCHY_MOUNT}/${nested}"
                echo "  Deleting nested: ${nested_full}"
                btrfs subvolume delete "$nested_full" 2>/dev/null || true
            done <<< "$NESTED"
        fi

        # Retry main subvolume
        if btrfs subvolume delete "$snap_path" 2>/dev/null; then
            echo "  OK (after nested cleanup)"
            rm -rf "$s" 2>/dev/null || true
            DELETED=$((DELETED + 1))
        else
            echo "  FAILED — may need manual intervention"
            echo "  Try: btrfs subvolume delete '${snap_path}'"
            FAILED=$((FAILED + 1))
        fi
    fi
done

echo ""
echo "=== Cleanup complete ==="
echo "Deleted: ${DELETED}"
echo "Failed:  ${FAILED}"
echo ""

# Sync filesystem
echo "Syncing filesystem..."
sync
btrfs filesystem sync "${OMARCHY_MOUNT}" 2>/dev/null || true

echo ""
echo "=== Disk usage AFTER cleanup ==="
df -h "${OMARCHY_MOUNT}"
echo ""

# Show btrfs-specific usage
echo "=== btrfs filesystem usage ==="
btrfs filesystem usage "${OMARCHY_MOUNT}" 2>/dev/null || btrfs filesystem df "${OMARCHY_MOUNT}" 2>/dev/null || true
echo ""

echo "=== Remaining snapshots ==="
ls -la "${SNAPSHOT_BASE}/" 2>/dev/null | head -20 || true
