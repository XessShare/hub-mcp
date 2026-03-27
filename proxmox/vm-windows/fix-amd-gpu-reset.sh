#!/usr/bin/env bash
# fix-amd-gpu-reset.sh — Fix AMD Navi GPU reset bug for Proxmox passthrough
#
# AMD Navi GPUs (RX 5000/6000/7000 series) have a known reset bug:
# after a VM shuts down, the GPU cannot be reset by the host, which
# prevents the VM from starting again without a full host reboot.
#
# This script installs the vendor-reset kernel module, configures GRUB
# IOMMU parameters, sets up VFIO binding, and blacklists the host GPU
# driver — permanently fixing the reset issue.
#
# Run on the Proxmox host as root.
#
# Usage: sudo bash fix-amd-gpu-reset.sh [GPU_PCI_ADDRESS]
# Example: sudo bash fix-amd-gpu-reset.sh 0a:00.0
#
# If no address given, the script auto-detects the AMD GPU.

set -euo pipefail

GPU_ADDR="${1:-}"

echo "============================================"
echo "  AMD GPU Reset Bug Fix"
echo "  vendor-reset + IOMMU + VFIO"
echo "============================================"
echo ""

# =====================================================================
# PHASE 1: DIAGNOSE GPU
# =====================================================================
echo "==> Phase 1: GPU Diagnosis"
echo ""

# Auto-detect AMD GPU if not specified
if [[ -z "$GPU_ADDR" ]]; then
    GPU_ADDR=$(lspci | grep -i "VGA.*AMD\|Display.*AMD\|VGA.*ATI\|VGA.*Navi\|VGA.*Radeon" | head -1 | awk '{print $1}')
    if [[ -z "$GPU_ADDR" ]]; then
        echo "ERROR: No AMD GPU found. Specify PCI address manually."
        echo "  lspci | grep -i vga"
        exit 1
    fi
    echo "    Auto-detected AMD GPU at: $GPU_ADDR"
fi

# GPU details
echo ""
echo "    GPU PCI address: $GPU_ADDR"
GPU_INFO=$(lspci -nns "$GPU_ADDR" 2>/dev/null || echo "not found")
echo "    GPU info: $GPU_INFO"

# Extract vendor:device IDs
GPU_IDS=$(lspci -n -s "$GPU_ADDR" 2>/dev/null | awk '{print $3}')
echo "    GPU IDs: $GPU_IDS"

# Check for audio function (usually .1)
AUDIO_ADDR=$(echo "$GPU_ADDR" | sed 's/\.[0-9]$/.1/')
AUDIO_IDS=""
if lspci -s "$AUDIO_ADDR" &>/dev/null; then
    AUDIO_IDS=$(lspci -n -s "$AUDIO_ADDR" 2>/dev/null | awk '{print $3}')
    AUDIO_INFO=$(lspci -nns "$AUDIO_ADDR" 2>/dev/null || echo "")
    echo "    Audio:    $AUDIO_ADDR ($AUDIO_IDS)"
fi

# Current driver binding
echo ""
echo "    Current driver binding:"
lspci -nnk -s "$GPU_ADDR" | while read -r line; do echo "      $line"; done
echo ""
if [[ -n "$AUDIO_ADDR" ]]; then
    lspci -nnk -s "$AUDIO_ADDR" 2>/dev/null | while read -r line; do echo "      $line"; done
    echo ""
fi

# IOMMU group
IOMMU_PATH=$(find /sys/kernel/iommu_groups/ -name "0000:$GPU_ADDR" 2>/dev/null | head -1)
if [[ -n "$IOMMU_PATH" ]]; then
    GROUP_NUM=$(echo "$IOMMU_PATH" | grep -oP 'iommu_groups/\K\d+')
    echo "    IOMMU group: $GROUP_NUM"
    echo "    Devices in group $GROUP_NUM:"
    for dev in /sys/kernel/iommu_groups/"$GROUP_NUM"/devices/*; do
        echo "      $(lspci -nns "$(basename "$dev" | sed 's/^0000://')" 2>/dev/null)"
    done
else
    echo "    WARNING: GPU not found in any IOMMU group"
    echo "    IOMMU may not be enabled in BIOS/GRUB"
fi

# Check for reset bug symptoms in dmesg
echo ""
echo "    Checking dmesg for GPU reset issues..."
RESET_ERRORS=$(dmesg 2>/dev/null | grep -c "failed to reset PCI device\|GPU reset\|amdgpu.*reset\|vfio.*reset" || echo "0")
if [[ "$RESET_ERRORS" -gt 0 ]]; then
    echo "    FOUND: $RESET_ERRORS GPU reset related messages in dmesg"
    dmesg 2>/dev/null | grep -i "failed to reset PCI device\|GPU reset\|amdgpu.*reset\|vfio.*reset" | tail -5 | while read -r line; do
        echo "      $line"
    done
else
    echo "    No GPU reset errors found (yet)"
fi

# Identify GPU generation for vendor-reset compatibility
echo ""
NAVI_GEN=""
if echo "$GPU_INFO" | grep -qi "navi 1[04]"; then
    NAVI_GEN="navi10"
elif echo "$GPU_INFO" | grep -qi "navi 2[1-4]\|6[6-9]00\|6[0-9]00 XT"; then
    NAVI_GEN="navi21-24"
elif echo "$GPU_INFO" | grep -qi "navi 3\|7[0-9]00"; then
    NAVI_GEN="navi31-33"
elif echo "$GPU_INFO" | grep -qi "ellesmere\|polaris\|RX 5[0-9]0"; then
    NAVI_GEN="polaris"
elif echo "$GPU_INFO" | grep -qi "vega"; then
    NAVI_GEN="vega"
fi
echo "    Detected GPU family: ${NAVI_GEN:-unknown}"
echo "    vendor-reset support: $(if [[ -n "$NAVI_GEN" ]]; then echo 'YES'; else echo 'check manually'; fi)"

# =====================================================================
# PHASE 2: INSTALL VENDOR-RESET MODULE
# =====================================================================
echo ""
echo "============================================"
echo "==> Phase 2: Install vendor-reset Module"
echo "============================================"
echo ""

if lsmod | grep -q vendor_reset; then
    echo "    vendor-reset module already loaded"
else
    # Check if already installed but not loaded
    if modinfo vendor_reset &>/dev/null; then
        echo "    vendor-reset module installed but not loaded"
        echo "    Loading..."
        modprobe vendor_reset
        echo "    Done."
    else
        echo "    Installing vendor-reset from source..."
        echo ""

        # Install build dependencies
        echo "    Installing build dependencies..."
        apt-get update -qq
        apt-get install -y -qq git dkms pve-headers-$(uname -r) build-essential 2>/dev/null

        # Clone and install
        VENDOR_RESET_DIR="/opt/vendor-reset"
        if [[ -d "$VENDOR_RESET_DIR" ]]; then
            echo "    Updating existing source..."
            git -C "$VENDOR_RESET_DIR" pull --ff-only 2>/dev/null || true
        else
            echo "    Cloning vendor-reset repository..."
            git clone https://github.com/gnif/vendor-reset.git "$VENDOR_RESET_DIR"
        fi

        # Build with DKMS
        cd "$VENDOR_RESET_DIR"
        DKMS_VER=$(cat VERSION 2>/dev/null || echo "0.1.1")

        # Remove old DKMS version if exists
        dkms remove vendor-reset/"$DKMS_VER" --all 2>/dev/null || true

        # Install via DKMS (survives kernel updates)
        dkms install .
        echo ""
        echo "    vendor-reset $DKMS_VER installed via DKMS"

        # Load module
        modprobe vendor_reset
        echo "    Module loaded"
    fi
fi

# Verify
echo ""
if lsmod | grep -q vendor_reset; then
    echo "    [OK] vendor-reset module is active"
    # Check if it attached to our GPU
    dmesg | grep -i "vendor.reset" | tail -3 | while read -r line; do
        echo "      $line"
    done
else
    echo "    [FAIL] vendor-reset module not loaded"
    echo "    Check: dmesg | grep vendor"
fi

# Auto-load on boot
echo "vendor_reset" > /etc/modules-load.d/vendor-reset.conf
echo "    Auto-load on boot: /etc/modules-load.d/vendor-reset.conf"

# Ensure vendor-reset loads BEFORE vfio-pci
SOFTDEP_CONF="/etc/modprobe.d/vendor-reset.conf"
cat > "$SOFTDEP_CONF" << 'EOF'
# Load vendor-reset before vfio-pci so it can handle GPU reset
softdep vfio-pci pre: vendor_reset
EOF
echo "    Soft dependency configured: vendor-reset loads before vfio-pci"

# =====================================================================
# PHASE 3: CONFIGURE GRUB / IOMMU
# =====================================================================
echo ""
echo "============================================"
echo "==> Phase 3: GRUB & IOMMU Parameters"
echo "============================================"
echo ""

GRUB_FILE="/etc/default/grub"
GRUB_LINE=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB_FILE")
echo "    Current: $GRUB_LINE"

CURRENT_PARAMS=$(echo "$GRUB_LINE" | grep -oP '"\K[^"]+')
NEW_PARAMS="$CURRENT_PARAMS"
GRUB_CHANGED=false

# Required parameters
declare -A REQUIRED_PARAMS=(
    ["amd_iommu=on"]="Enable AMD IOMMU"
    ["iommu=pt"]="IOMMU passthrough mode (better performance)"
)

for PARAM in "${!REQUIRED_PARAMS[@]}"; do
    if ! echo "$CURRENT_PARAMS" | grep -q "$PARAM"; then
        NEW_PARAMS="$NEW_PARAMS $PARAM"
        GRUB_CHANGED=true
        echo "    Adding: $PARAM (${REQUIRED_PARAMS[$PARAM]})"
    else
        echo "    [OK] $PARAM"
    fi
done

# AMD Navi specific: prevent host from claiming GPU framebuffer
if ! echo "$CURRENT_PARAMS" | grep -q "video=efifb:off"; then
    NEW_PARAMS="$NEW_PARAMS video=efifb:off"
    GRUB_CHANGED=true
    echo "    Adding: video=efifb:off (prevent host GPU framebuffer claim)"
fi

# AMD reset workaround
if ! echo "$CURRENT_PARAMS" | grep -q "pci=noats"; then
    NEW_PARAMS="$NEW_PARAMS pci=noats"
    GRUB_CHANGED=true
    echo "    Adding: pci=noats (AMD ATS workaround)"
fi

if [[ "$GRUB_CHANGED" == "true" ]]; then
    echo ""
    echo "    New: GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_PARAMS\""
    cp "$GRUB_FILE" "${GRUB_FILE}.bak.$(date +%s)"
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_PARAMS\"|" "$GRUB_FILE"
    update-grub 2>/dev/null
    echo "    [OK] GRUB updated"
else
    echo "    [OK] GRUB parameters already correct"
fi

# =====================================================================
# PHASE 4: VFIO-PCI BINDING
# =====================================================================
echo ""
echo "============================================"
echo "==> Phase 4: VFIO-PCI Binding"
echo "============================================"
echo ""

# Collect all IDs to bind
VFIO_IDS="$GPU_IDS"
[[ -n "$AUDIO_IDS" ]] && VFIO_IDS="$VFIO_IDS,$AUDIO_IDS"

echo "    Device IDs for vfio-pci: $VFIO_IDS"

# VFIO modules
VFIO_MODULES_CONF="/etc/modules-load.d/vfio.conf"
cat > "$VFIO_MODULES_CONF" << 'EOF'
vfio
vfio_iommu_type1
vfio_pci
EOF
echo "    [OK] VFIO modules: $VFIO_MODULES_CONF"

# VFIO-PCI device IDs
VFIO_PCI_CONF="/etc/modprobe.d/vfio-pci.conf"
cat > "$VFIO_PCI_CONF" << EOF
options vfio-pci ids=$VFIO_IDS
EOF
echo "    [OK] VFIO-PCI IDs: $VFIO_PCI_CONF"

# Blacklist AMD GPU drivers on host
BLACKLIST_CONF="/etc/modprobe.d/blacklist-amdgpu.conf"
cat > "$BLACKLIST_CONF" << 'EOF'
# Prevent host from loading AMD GPU drivers (reserved for VM passthrough)
blacklist amdgpu
blacklist radeon
EOF
echo "    [OK] Blacklisted amdgpu/radeon on host: $BLACKLIST_CONF"

# =====================================================================
# PHASE 5: UPDATE INITRAMFS
# =====================================================================
echo ""
echo "============================================"
echo "==> Phase 5: Update initramfs"
echo "============================================"
echo ""

echo "    Updating initramfs for all kernels..."
update-initramfs -u -k all 2>/dev/null
echo "    [OK] initramfs updated"

# =====================================================================
# SUMMARY
# =====================================================================
echo ""
echo "============================================"
echo "  AMD GPU Reset Fix — Complete"
echo "============================================"
echo ""
echo "  GPU:          $GPU_ADDR ($GPU_INFO)"
echo "  VFIO IDs:     $VFIO_IDS"
echo "  vendor-reset: $(if lsmod | grep -q vendor_reset; then echo 'ACTIVE'; else echo 'installed (loads on boot)'; fi)"
echo "  GRUB:         $(if [[ "$GRUB_CHANGED" == "true" ]]; then echo 'UPDATED (reboot required)'; else echo 'OK'; fi)"
echo ""
echo "  Files modified:"
echo "    /etc/default/grub"
echo "    /etc/modules-load.d/vfio.conf"
echo "    /etc/modules-load.d/vendor-reset.conf"
echo "    /etc/modprobe.d/vfio-pci.conf"
echo "    /etc/modprobe.d/vendor-reset.conf"
echo "    /etc/modprobe.d/blacklist-amdgpu.conf"
echo ""

if [[ "$GRUB_CHANGED" == "true" ]]; then
    echo "  *** HOST REBOOT REQUIRED ***"
    echo ""
    echo "  After reboot, verify with:"
    echo "    lsmod | grep vendor_reset"
    echo "    lspci -nnk -s $GPU_ADDR"
    echo "    dmesg | grep -i 'vendor.reset\|vfio'"
    echo ""
    read -rp "  Reboot now? [y/n]: " DO_REBOOT
    if [[ "$DO_REBOOT" == "y" ]]; then
        echo "  Rebooting in 5 seconds..."
        sleep 5
        reboot
    fi
else
    echo "  Verify with:"
    echo "    lsmod | grep vendor_reset"
    echo "    lspci -nnk -s $GPU_ADDR"
    echo ""
    echo "  Then start the VM:"
    echo "    qm start 100"
fi
echo ""
