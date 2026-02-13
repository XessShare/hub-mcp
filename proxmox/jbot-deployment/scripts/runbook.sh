#!/usr/bin/env bash
# JBOT Sprint 0 Runbook — GPU/Docker/Qdrant Readiness Check
# Run on Proxmox Host; Parameter: LXC VMID
# Usage: ./runbook.sh 100

set -euo pipefail

VMID="${1:-100}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOGFILE="jbot_runbook_${TIMESTAMP}.log"

echo "=== JBOT Runbook Start @ $(date) ===" | tee -a "$LOGFILE"
echo "Target LXC: $VMID" | tee -a "$LOGFILE"

# ─────────────────────────────────────────────────────────────
# TASK A — LXC Features & Device Passthrough
# ─────────────────────────────────────────────────────────────
echo -e "\n[TASK A] Checking LXC features..." | tee -a "$LOGFILE"

# Set features if not already set
pct set "$VMID" -features nesting=1,keyctl=1 2>&1 | tee -a "$LOGFILE" || true

# Verify devices
echo "Checking /dev/dri in LXC..." | tee -a "$LOGFILE"
if pct exec "$VMID" -- ls -l /dev/dri 2>&1 | tee -a "$LOGFILE" | grep -q "card0"; then
    echo "  /dev/dri/card0 found [OK]" | tee -a "$LOGFILE"
else
    echo "  /dev/dri/card0 NOT found — GPU passthrough broken [FAIL]" | tee -a "$LOGFILE"
    exit 1
fi

echo "Checking /dev/kfd in LXC..." | tee -a "$LOGFILE"
if pct exec "$VMID" -- ls -l /dev/kfd 2>&1 | tee -a "$LOGFILE"; then
    echo "  /dev/kfd found [OK]" | tee -a "$LOGFILE"
else
    echo "  /dev/kfd NOT found (may be expected if unused) [WARN]" | tee -a "$LOGFILE"
fi

# ─────────────────────────────────────────────────────────────
# TASK B — Docker Daemon Config (overlay2 + MTU)
# ─────────────────────────────────────────────────────────────
echo -e "\n[TASK B] Deploying /etc/docker/daemon.json..." | tee -a "$LOGFILE"

pct exec "$VMID" -- bash -c 'cat > /etc/docker/daemon.json' <<'DOCKERJSON'
{
  "storage-driver": "overlay2",
  "mtu": 1380,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true
}
DOCKERJSON

echo "Restarting Docker daemon..." | tee -a "$LOGFILE"
pct exec "$VMID" -- systemctl restart docker 2>&1 | tee -a "$LOGFILE"
sleep 3

echo "Verifying Docker config..." | tee -a "$LOGFILE"
pct exec "$VMID" -- docker info 2>&1 | tee -a "$LOGFILE" | grep -E "Storage Driver|MTU" || true

if pct exec "$VMID" -- docker info 2>&1 | grep -q "Storage Driver: overlay2"; then
    echo "  Docker overlay2 active [OK]" | tee -a "$LOGFILE"
else
    echo "  Docker overlay2 NOT active [FAIL]" | tee -a "$LOGFILE"
    exit 1
fi

# ─────────────────────────────────────────────────────────────
# TASK C — Validate Docker Compose Presence
# ─────────────────────────────────────────────────────────────
echo -e "\n[TASK C] Checking docker compose..." | tee -a "$LOGFILE"

if pct exec "$VMID" -- docker compose version 2>&1 | tee -a "$LOGFILE"; then
    echo "  docker compose installed [OK]" | tee -a "$LOGFILE"
else
    echo "  docker compose not found — install before proceeding [WARN]" | tee -a "$LOGFILE"
fi

# ─────────────────────────────────────────────────────────────
# TASK D — Check Qdrant Port & Healthcheck (if deployed)
# ─────────────────────────────────────────────────────────────
echo -e "\n[TASK D] Checking Qdrant (if running)..." | tee -a "$LOGFILE"

if pct exec "$VMID" -- docker ps --format '{{.Names}}' 2>/dev/null | grep -q qdrant; then
    echo "Qdrant container running, checking health..." | tee -a "$LOGFILE"
    pct exec "$VMID" -- curl -sS http://127.0.0.1:6333/collections 2>&1 | tee -a "$LOGFILE" || echo "  Qdrant API unreachable [WARN]" | tee -a "$LOGFILE"
else
    echo "  Qdrant not yet deployed (normal for first run) [INFO]" | tee -a "$LOGFILE"
fi

# ─────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────
echo -e "\n=== Runbook Complete @ $(date) ===" | tee -a "$LOGFILE"
echo "Log saved to: $LOGFILE"
echo ""
echo "Next Step: Deploy stack with 'docker compose up -d' in LXC"
echo "   Then run: pct exec $VMID -- docker compose ps"
