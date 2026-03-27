#!/usr/bin/env bash
# fix-usb-passthrough.sh — Pass through USB keyboard & mouse to a VM
#
# When GPU passthrough is active, the display output goes to the physical GPU
# but keyboard and mouse are NOT automatically passed through. This script
# detects USB input devices on the host and configures them for VM passthrough.
#
# Run on the Proxmox host where the VM is running.
#
# Usage: sudo bash fix-usb-passthrough.sh [VMID]
# Example: sudo bash fix-usb-passthrough.sh 100
#
# Manual override (if auto-detection fails):
#   sudo bash fix-usb-passthrough.sh 100 --keyboard 046d:c52b --mouse 1532:006e
#   (Get vendor:product IDs from 'lsusb')

set -euo pipefail

VMID="${1:-100}"
shift || true

# --- Parse optional manual overrides ---
KB_MANUAL=""
MS_MANUAL=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --keyboard) KB_MANUAL="$2"; shift 2 ;;
        --mouse)    MS_MANUAL="$2"; shift 2 ;;
        *)          echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "============================================"
echo "  USB Input Passthrough Fix"
echo "  VM $VMID — Keyboard & Mouse"
echo "============================================"
echo ""

# --- Verify VM exists ---
if ! qm status "$VMID" &>/dev/null; then
    echo "ERROR: VM $VMID does not exist."
    exit 1
fi

# --- Stop VM if running ---
VM_STATE=$(qm status "$VMID" | awk '{print $2}')
if [[ "$VM_STATE" == "running" ]]; then
    echo "==> Stopping VM $VMID..."
    qm stop "$VMID"
    sleep 3
fi

# --- List USB devices ---
echo "==> USB devices on host:"
echo ""
lsusb | grep -vi hub || true
echo ""

# --- Detect keyboard and mouse ---
echo "==> Detecting input devices..."

KB_INFO="${KB_MANUAL}"
MS_INFO="${MS_MANUAL}"

if [[ -z "$KB_INFO" ]] || [[ -z "$MS_INFO" ]]; then
    for dev in /sys/class/input/event*/device; do
        [[ -f "$dev/name" ]] || continue
        [[ -f "$dev/id/vendor" ]] || continue
        [[ -f "$dev/id/product" ]] || continue

        VID=$(cat "$dev/id/vendor")
        PID=$(cat "$dev/id/product")
        NAME=$(cat "$dev/name" 2>/dev/null || echo "unknown")

        # Skip virtual devices (0000:0000)
        [[ "$VID" == "0000" ]] && continue

        # Detect keyboard via key capabilities (long bitmask = real keyboard)
        if [[ -z "$KB_INFO" ]]; then
            CAPS=$(cat "$dev/capabilities/key" 2>/dev/null || echo "0")
            if echo "$CAPS" | grep -qP '[0-9a-f]{10,}'; then
                KB_INFO="${VID}:${PID}"
                echo "    Keyboard: $NAME [$VID:$PID]"
            fi
        fi

        # Detect mouse via relative axis capabilities (REL_X, REL_Y)
        if [[ -z "$MS_INFO" ]]; then
            REL=$(cat "$dev/capabilities/rel" 2>/dev/null || echo "0")
            if [[ "$REL" != "0" ]]; then
                MS_INFO="${VID}:${PID}"
                echo "    Mouse:    $NAME [$VID:$PID]"
            fi
        fi

        # Stop once both are found
        [[ -n "$KB_INFO" ]] && [[ -n "$MS_INFO" ]] && break
    done
fi

echo ""

# --- Configure USB passthrough ---
echo "==> Configuring USB passthrough..."

SLOT=0
CONFIGURED=0

if [[ -n "$KB_INFO" ]]; then
    qm set "$VMID" -usb${SLOT} "host=${KB_INFO}"
    echo "    usb${SLOT}: keyboard (host=${KB_INFO})"
    SLOT=$((SLOT + 1))
    CONFIGURED=$((CONFIGURED + 1))
else
    echo "    WARNING: Keyboard not detected."
    echo "    Use --keyboard VENDOR:PRODUCT to specify manually."
    echo "    Run 'lsusb' to find the IDs."
fi

if [[ -n "$MS_INFO" ]]; then
    qm set "$VMID" -usb${SLOT} "host=${MS_INFO}"
    echo "    usb${SLOT}: mouse (host=${MS_INFO})"
    SLOT=$((SLOT + 1))
    CONFIGURED=$((CONFIGURED + 1))
else
    echo "    WARNING: Mouse not detected."
    echo "    Use --mouse VENDOR:PRODUCT to specify manually."
    echo "    Run 'lsusb' to find the IDs."
fi

if [[ "$CONFIGURED" -eq 0 ]]; then
    echo ""
    echo "ERROR: No input devices configured. VM not started."
    echo "       Specify devices manually:"
    echo "       sudo bash fix-usb-passthrough.sh $VMID --keyboard VENDOR:PRODUCT --mouse VENDOR:PRODUCT"
    exit 1
fi

# --- Start VM ---
echo ""
echo "==> Starting VM $VMID..."
qm start "$VMID"
sleep 5

VM_STATE=$(qm status "$VMID" | awk '{print $2}')

echo ""
echo "============================================"
echo "  USB Passthrough Configured"
echo "============================================"
echo ""
echo "  VM:     $VMID ($VM_STATE)"
if [[ -n "$KB_INFO" ]]; then
    echo "  Keyboard: host=${KB_INFO}"
fi
if [[ -n "$MS_INFO" ]]; then
    echo "  Mouse:    host=${MS_INFO}"
fi
echo ""
echo "  The VM display output goes to the"
echo "  passthrough GPU. Keyboard and mouse"
echo "  should now work on the physical monitor."
echo ""

# --- Show SSH access if available ---
echo "==> Checking VM network (waiting 15s)..."
sleep 15
VM_MAC=$(qm config "$VMID" | grep "^net0:" | grep -oP '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' || echo "")
if [[ -n "$VM_MAC" ]]; then
    VM_IP=$(arp -an | grep -i "$VM_MAC" | grep -oP '\d+\.\d+\.\d+\.\d+' || echo "")
    if [[ -n "$VM_IP" ]]; then
        echo "    SSH: ssh user@$VM_IP"
        echo "    RDP: xfreerdp /v:$VM_IP /u:Administrator /dynamic-resolution"
    else
        echo "    VM IP not yet available in ARP table."
        echo "    Try: qm guest cmd $VMID network-get-interfaces"
    fi
else
    echo "    No network interface detected."
fi
echo ""
