#!/usr/bin/env bash
# usb-passthrough-vm100.sh — Pass Logitech USB keyboard+mouse to VM 100
#
# Usage (run as root on pve):
#   bash usb-passthrough-vm100.sh
#
# This script:
#   1. Detects Logitech USB devices (keyboards, mice, receivers)
#   2. Passes them through to VM 100 via qm set
#   3. Works with Logitech Unifying receivers (single dongle for both)
#
# NOTE: VM 100 must be running. USB devices will be hot-plugged.

set -euo pipefail

VMID=100

echo "=== USB Passthrough to VM ${VMID} ==="
echo ""

# Check VM is running
VM_STATUS=$(qm status "$VMID" 2>/dev/null | awk '{print $2}')
if [[ "$VM_STATUS" != "running" ]]; then
    echo "ERROR: VM ${VMID} is not running (status: ${VM_STATUS})"
    echo "Start it first: qm start ${VMID}"
    exit 1
fi

echo "VM ${VMID} is running. Detecting USB devices..."
echo ""

# List all USB devices
echo "=== All USB devices ==="
lsusb
echo ""

# Find Logitech devices (Vendor ID: 046d)
echo "=== Logitech devices ==="
LOGITECH_DEVICES=$(lsusb | grep -i "046d\|logitech" || true)

if [[ -z "$LOGITECH_DEVICES" ]]; then
    echo "No Logitech devices found. Listing all HID devices instead..."
    echo ""
    # Fallback: find any HID keyboard/mouse devices
    HID_DEVICES=$(lsusb | grep -iE "keyboard|mouse|hid|input|receiver" || true)
    if [[ -z "$HID_DEVICES" ]]; then
        echo "No HID input devices found."
        echo ""
        echo "All USB devices:"
        lsusb
        echo ""
        echo "Manually pass through with:"
        echo "  qm set ${VMID} -usb0 host=VENDOR:PRODUCT"
        exit 1
    fi
    echo "$HID_DEVICES"
    DEVICES_TO_PASS="$HID_DEVICES"
else
    echo "$LOGITECH_DEVICES"
    DEVICES_TO_PASS="$LOGITECH_DEVICES"
fi

echo ""

# Extract vendor:product IDs and pass them through
USB_INDEX=0
while IFS= read -r line; do
    # Extract vendor:product ID (format: 046d:c52b)
    VENDOR_PRODUCT=$(echo "$line" | grep -oP '[0-9a-f]{4}:[0-9a-f]{4}')
    DEVICE_NAME=$(echo "$line" | sed 's/.*ID [0-9a-f:]\+ //')

    if [[ -n "$VENDOR_PRODUCT" ]]; then
        echo "Passing through USB${USB_INDEX}: ${VENDOR_PRODUCT} (${DEVICE_NAME})"
        qm set "$VMID" -usb${USB_INDEX} "host=${VENDOR_PRODUCT}" 2>&1 || {
            echo "  WARNING: Failed to set usb${USB_INDEX}. Trying with usb3=1..."
            qm set "$VMID" -usb${USB_INDEX} "host=${VENDOR_PRODUCT},usb3=1" 2>&1 || true
        }
        USB_INDEX=$((USB_INDEX + 1))
    fi
done <<< "$DEVICES_TO_PASS"

if [[ $USB_INDEX -eq 0 ]]; then
    echo "ERROR: No devices were passed through."
    exit 1
fi

echo ""
echo "=== Done! ${USB_INDEX} device(s) passed to VM ${VMID} ==="
echo ""
echo "If devices don't work immediately:"
echo "  1. Wait 10 seconds for hot-plug detection"
echo "  2. Check VM console: dmesg | tail -20"
echo "  3. If still not working, restart VM: qm reboot ${VMID}"
echo ""
echo "To remove passthrough later:"
for i in $(seq 0 $((USB_INDEX - 1))); do
    echo "  qm set ${VMID} -delete usb${i}"
done
