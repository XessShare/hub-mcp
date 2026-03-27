#!/usr/bin/env bash
# reset-vm-credentials.sh — Reset cloud-init user/password for a Proxmox VM
#
# When cloud-init credentials are wrong or forgotten, this script resets
# the username and password via Proxmox's cloud-init interface, regenerates
# the cloud-init drive, and restarts the VM so the new credentials apply.
#
# Run on the Proxmox host as root.
#
# Usage: sudo bash reset-vm-credentials.sh [VMID] [USERNAME] [PASSWORD]
# Example: sudo bash reset-vm-credentials.sh 100 admin changeme
#
# If no arguments are given, defaults to VMID=100, user=admin, pass=changeme

set -euo pipefail

VMID="${1:-100}"
CI_USER="${2:-admin}"
CI_PASS="${3:-changeme}"

echo "============================================"
echo "  Cloud-Init Credential Reset"
echo "  VM $VMID"
echo "============================================"
echo ""

# --- Verify VM exists ---
if ! qm status "$VMID" &>/dev/null; then
    echo "ERROR: VM $VMID does not exist."
    exit 1
fi

VM_STATE=$(qm status "$VMID" | awk '{print $2}')
echo "==> VM $VMID is: $VM_STATE"

# --- Show current cloud-init config ---
echo ""
echo "==> Current cloud-init config:"
qm cloudinit dump "$VMID" user 2>/dev/null | grep -E 'user|password|ssh' || echo "    (no cloud-init config found)"
echo ""

# --- Set new credentials ---
echo "==> Setting credentials: user=$CI_USER"
qm set "$VMID" -ciuser "$CI_USER"
qm set "$VMID" -cipassword "$CI_PASS"

# Enable password authentication (some cloud images disable it)
qm set "$VMID" -ciupgrade 0

echo "    User:     $CI_USER"
echo "    Password: $CI_PASS"
echo ""

# --- Regenerate cloud-init drive ---
echo "==> Regenerating cloud-init drive..."
qm cloudinit update "$VMID" 2>/dev/null || true
echo "    Done."
echo ""

# --- Restart VM to apply ---
if [[ "$VM_STATE" == "running" ]]; then
    echo "==> Restarting VM to apply new credentials..."
    qm reboot "$VMID"
    echo "    VM rebooting..."
    sleep 10
else
    echo "==> Starting VM..."
    qm start "$VMID"
    sleep 10
fi

VM_STATE=$(qm status "$VMID" | awk '{print $2}')
echo "    VM is now: $VM_STATE"
echo ""

# --- Alternative: direct password reset via chroot ---
echo "============================================"
echo "  Credentials Applied"
echo "============================================"
echo ""
echo "  Login with:"
echo "    User:     $CI_USER"
echo "    Password: $CI_PASS"
echo ""
echo "  Try in Proxmox web console or serial terminal:"
echo "    $CI_USER"
echo "    $CI_PASS"
echo ""
echo "  If cloud-init still doesn't apply the password,"
echo "  use the emergency reset method below."
echo ""
echo "============================================"
echo "  EMERGENCY: Direct Disk Password Reset"
echo "============================================"
echo ""
echo "  If cloud-init fails, mount the VM disk directly:"
echo ""
echo "    # Stop the VM first"
echo "    qm stop $VMID"
echo ""
echo "    # Find the disk"
echo "    lvs | grep vm-${VMID}"
echo ""
echo "    # Mount it (adjust path to your storage)"
echo "    mkdir -p /mnt/vm${VMID}"
echo "    DISK=\$(pvesm path local-lvm:vm-${VMID}-disk-0)"
echo "    kpartx -av \$DISK"
echo "    mount /dev/mapper/\$(basename \$DISK)p1 /mnt/vm${VMID}  # try p1, p2, p3"
echo ""
echo "    # Reset root password"
echo "    chroot /mnt/vm${VMID} passwd root"
echo ""
echo "    # Or create/reset your user"
echo "    chroot /mnt/vm${VMID} bash -c 'echo ${CI_USER}:${CI_PASS} | chpasswd'"
echo ""
echo "    # Unmount and start"
echo "    umount /mnt/vm${VMID}"
echo "    kpartx -dv \$DISK"
echo "    qm start $VMID"
echo ""
