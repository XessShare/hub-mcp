#!/usr/bin/env bash
# JBOT Daily Health Check — Run on Proxmox Host
# Usage: ./daily-check.sh [VMID]

set -euo pipefail

VMID="${1:-100}"

echo "=== JBOT Daily Check $(date) ==="
echo ""

echo "[1/6] Container Status"
pct exec "$VMID" -- docker compose -f /opt/jbot/docker-compose.yml ps
echo ""

echo "[2/6] GPU Status"
pct exec "$VMID" -- docker exec jbot_ollama rocm-smi 2>/dev/null || echo "  rocm-smi unavailable [WARN]"
echo ""

echo "[3/6] Qdrant Collections"
pct exec "$VMID" -- curl -sS http://127.0.0.1:6333/collections 2>/dev/null | jq -r '.result.collections[] | .name' || echo "  Qdrant unreachable [WARN]"
echo ""

echo "[4/6] Disk Usage"
pct exec "$VMID" -- du -sh /var/lib/docker/volumes/jbot_* 2>/dev/null || echo "  Volumes not found [WARN]"
echo ""

echo "[5/6] Recent Errors (last 1h)"
pct exec "$VMID" -- docker compose -f /opt/jbot/docker-compose.yml logs --since 1h 2>&1 | grep -iE 'error|fatal|panic' | tail -20 || echo "  No errors found [OK]"
echo ""

echo "[6/6] ZFS ARC (Host)"
if [ -f /proc/spl/kstat/zfs/arcstats ]; then
    awk '/^c / {printf "ARC Size: %.2f GB\n", $3/1024/1024/1024}' /proc/spl/kstat/zfs/arcstats
else
    echo "  ZFS not configured on this host [INFO]"
fi

echo ""
echo "=== Check Complete ==="
