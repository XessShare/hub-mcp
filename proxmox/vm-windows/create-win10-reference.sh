#!/usr/bin/env bash
# create-win10-reference.sh — Deterministic Windows 10 reference VM setup
#
# Target host: pve (192.168.16.2)
# VMID:        110
# Purpose:     Reference client for Samba validation and future GPU passthrough
#
# Prerequisites:
#   - Proxmox VE on pve (192.168.16.2)
#   - Windows 10 ISO uploaded to /var/lib/vz/template/iso/
#   - VirtIO drivers ISO uploaded to /var/lib/vz/template/iso/
#
# Usage:
#   sudo bash proxmox/vm-windows/create-win10-reference.sh [VMID] [VM_NAME]
#
# After VM creation:
#   1. Start: qm start 110
#   2. Access via console: open Proxmox Web GUI → VM 110 → Console
#   3. Install Windows from ISO
#   4. Install VirtIO storage driver: D:\amd64\w10\
#   5. Install VirtIO network driver: D:\NetKVM\w10\amd64\
#   6. Install VirtIO guest tools: D:\virtio-win-guest-tools.exe
#   7. Enable Remote Desktop
#   8. Validate: \\192.168.16.2\fitna-shared reachable via Explorer

set -euo pipefail

# --- Configuration ---
VMID="${1:-110}"
VM_NAME="${2:-win10-reference}"
STORAGE="local-lvm"
BRIDGE="vmbr0"
MEMORY=8192
CORES=4
DISK_SIZE="80G"
OS_TYPE="win10"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root."
    exit 1
fi

# --- Detect ISOs ---
ISO_DIR="/var/lib/vz/template/iso"

WIN_ISO=$(find "$ISO_DIR" -maxdepth 1 -iname '*win*10*' -o -iname '*Win10*' 2>/dev/null | head -1)
VIRTIO_ISO=$(find "$ISO_DIR" -maxdepth 1 -iname '*virtio*' 2>/dev/null | head -1)

if [ -z "$WIN_ISO" ]; then
    warn "No Windows 10 ISO found in $ISO_DIR"
    warn "VM will be created without CDROM. Upload ISO and attach manually:"
    warn "  qm set $VMID --ide0 local:iso/YOUR_WIN10.iso,media=cdrom"
fi

if [ -z "$VIRTIO_ISO" ]; then
    warn "No VirtIO drivers ISO found in $ISO_DIR"
    warn "Download from: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
fi

# --- Check for existing VM ---
if qm status "$VMID" &>/dev/null; then
    err "VM $VMID already exists!"
    err "To recreate: qm destroy $VMID --purge"
    exit 1
fi

# --- Create VM ---
log "Creating VM $VMID ($VM_NAME)..."
log "  BIOS: OVMF (UEFI), Machine: q35"
log "  CPU: host, Cores: $CORES, Memory: ${MEMORY}MB"
log "  Network: virtio on $BRIDGE"
log "  Storage: $STORAGE, Disk: $DISK_SIZE"

qm create "$VMID" \
    --name "$VM_NAME" \
    --bios ovmf \
    --machine q35 \
    --agent 1 \
    --cpu host \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --balloon 0 \
    --net0 "virtio,bridge=${BRIDGE}" \
    --scsihw virtio-scsi-single \
    --ostype "$OS_TYPE"

# --- Add EFI disk ---
log "Adding EFI disk..."
qm set "$VMID" --efidisk0 "${STORAGE}:1,efitype=4m,pre-enrolled-keys=1"

# --- Add OS disk ---
log "Adding OS disk (${DISK_SIZE})..."
qm set "$VMID" --scsi0 "${STORAGE}:${DISK_SIZE},iothread=1,ssd=1,discard=on"

# --- Attach ISOs ---
if [ -n "$WIN_ISO" ]; then
    WIN_ISO_REL="${WIN_ISO#$ISO_DIR/}"
    log "Attaching Windows ISO: $WIN_ISO_REL"
    qm set "$VMID" --ide0 "local:iso/${WIN_ISO_REL},media=cdrom"
fi

if [ -n "$VIRTIO_ISO" ]; then
    VIRTIO_ISO_REL="${VIRTIO_ISO#$ISO_DIR/}"
    log "Attaching VirtIO ISO: $VIRTIO_ISO_REL"
    qm set "$VMID" --ide1 "local:iso/${VIRTIO_ISO_REL},media=cdrom"
fi

# --- Set boot order ---
if [ -n "$WIN_ISO" ]; then
    qm set "$VMID" --boot order="ide0;scsi0"
else
    qm set "$VMID" --boot order="scsi0"
fi

# --- Display: use default VGA for initial setup (GPU passthrough added later) ---
qm set "$VMID" --vga std

log ""
log "VM $VMID ($VM_NAME) created successfully."
log ""
log "Machine is GPU-passthrough compatible (q35 + OVMF + host CPU)."
log "GPU passthrough can be added later with:"
log "  qm set $VMID --hostpci0 PCI_ADDR,pcie=1,x-vga=1"
log "  qm set $VMID --vga none"
log ""
log "Next steps:"
log "  1. Start VM:      qm start $VMID"
log "  2. Open console:  Proxmox Web GUI → VM $VMID → Console"
log "  3. Install Windows from ISO"
log "  4. Install VirtIO drivers"
log "  5. Validate Samba: \\\\192.168.16.2\\fitna-shared"
