#!/usr/bin/env bash
# debug-gpu-passthrough.sh — Diagnose and fix GPU passthrough issues
#
# Interactive debug tool for VMs with GPU passthrough (RX 6800 XT).
# Diagnoses common problems (missing USB input, IOMMU, VGA conflicts,
# GPU reset bugs) and provides guided fixes.
#
# Run on the Proxmox host as root.
#
# Usage: sudo bash debug-gpu-passthrough.sh [VMID]
# Example: sudo bash debug-gpu-passthrough.sh 100
#
# For non-interactive USB-only fix, use fix-usb-passthrough.sh instead.

set -euo pipefail

VMID="${1:-100}"
LOG_FILE="/root/vm${VMID}-debug-$(date +%Y%m%d_%H%M%S).log"

# --- Colors & formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()     { echo -e "$1" | tee -a "$LOG_FILE"; }
info()    { log "${BLUE}[INFO]${NC}  $1"; }
success() { log "${GREEN}[ OK ]${NC}  $1"; }
warn()    { log "${YELLOW}[WARN]${NC}  $1"; }
error()   { log "${RED}[FAIL]${NC}  $1"; }
header()  { log "\n${BOLD}${CYAN}=== $1 ===${NC}"; }

header "VM${VMID} GPU-PASSTHROUGH DEBUG & FIX"
info "Log: $LOG_FILE"
info "Date: $(date)"
info "Kernel: $(uname -r)"
info "PVE: $(pveversion 2>/dev/null || echo 'unknown')"

# =====================================================================
# PHASE 1: DIAGNOSIS
# =====================================================================
header "PHASE 1: SYSTEM DIAGNOSIS"

# 1.1 VM Status
info "VM $VMID status..."
VM_STATUS=$(qm status "$VMID" 2>/dev/null | awk '{print $2}') || VM_STATUS="not found"
if [[ "$VM_STATUS" == "running" ]]; then
    success "VM $VMID is running"
elif [[ "$VM_STATUS" == "stopped" ]]; then
    warn "VM $VMID is stopped"
else
    error "VM $VMID status: $VM_STATUS"
fi

# 1.2 VM configuration
info "VM configuration:"
echo "---" >> "$LOG_FILE"
qm config "$VMID" >> "$LOG_FILE" 2>&1
echo "---" >> "$LOG_FILE"

log ""
log "${BOLD}Current VM $VMID configuration:${NC}"
qm config "$VMID" | grep -E 'hostpci|vga|machine|tablet|usb|cpu|memory|net|boot|agent' | while read -r line; do
    log "  $line"
done

# 1.3 GPU passthrough details
info "GPU passthrough configuration:"
HOSTPCI=$(qm config "$VMID" 2>/dev/null | grep "hostpci" || echo "NONE")
if [[ "$HOSTPCI" == "NONE" ]]; then
    warn "No GPU passthrough configured"
else
    log "  $HOSTPCI"
fi

# 1.4 IOMMU status
info "IOMMU status:"
if dmesg | grep -q "IOMMU enabled"; then
    success "IOMMU is enabled"
else
    warn "IOMMU may not be active"
fi
IOMMU_GROUPS=$(find /sys/kernel/iommu_groups/ -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
info "IOMMU groups found: $IOMMU_GROUPS"

# 1.5 GPU identification
info "AMD GPU details:"
GPU_PCI=$(lspci | grep -i "vga\|display\|amd.*navi" | head -5)
log "  $GPU_PCI"

# GPU IOMMU group
GPU_ADDR=$(echo "$HOSTPCI" | grep -oP '\d+:\d+:\d+\.\d+' | head -1 || echo "")
if [[ -n "$GPU_ADDR" ]]; then
    IOMMU_GROUP=$(find /sys/kernel/iommu_groups/ -name "0000:$GPU_ADDR" 2>/dev/null | head -1)
    if [[ -n "$IOMMU_GROUP" ]]; then
        GROUP_NUM=$(echo "$IOMMU_GROUP" | grep -oP 'iommu_groups/\K\d+')
        info "GPU IOMMU group: $GROUP_NUM"
        info "Devices in same group:"
        for dev in /sys/kernel/iommu_groups/"$GROUP_NUM"/devices/*; do
            DEV_ID=$(basename "$dev")
            DEV_DESC=$(lspci -nns "${DEV_ID#0000:}" 2>/dev/null | head -1)
            log "    $DEV_DESC"
        done
    fi
fi

# 1.6 USB devices on host
info "USB devices on host:"
lsusb 2>/dev/null | while read -r line; do
    log "  $line"
done

# 1.7 VGA config
VGA_TYPE=$(qm config "$VMID" 2>/dev/null | grep "^vga:" | awk '{print $2}' || echo "default")
info "VM display/VGA type: $VGA_TYPE"

# 1.8 QEMU Guest Agent
AGENT_STATUS=$(qm config "$VMID" 2>/dev/null | grep "^agent:" || echo "not configured")
info "QEMU Guest Agent: $AGENT_STATUS"

# 1.9 Network — find VM IP
info "Looking for VM IP..."
VM_IP=""

# Method 1: Guest Agent
if [[ "$VM_STATUS" == "running" ]]; then
    VM_IP=$(qm guest cmd "$VMID" network-get-interfaces 2>/dev/null | \
        python3 -c "
import sys, json
data = json.load(sys.stdin)
for iface in data:
    for ip in iface.get('ip-addresses', []):
        if ip['ip-address-type'] == 'ipv4' and not ip['ip-address'].startswith('127.'):
            print(ip['ip-address'])
            sys.exit(0)
" 2>/dev/null) || true
fi

# Method 2: ARP table
if [[ -z "$VM_IP" ]]; then
    VM_MAC=$(qm config "$VMID" 2>/dev/null | grep "^net0:" | grep -oP '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | head -1 || echo "")
    if [[ -n "$VM_MAC" ]]; then
        VM_IP=$(arp -an 2>/dev/null | grep -i "$VM_MAC" | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1) || true
        info "VM MAC: $VM_MAC"
    fi
fi

# Method 3: Network scan
if [[ -z "$VM_IP" ]] && command -v nmap &>/dev/null; then
    info "Running network scan..."
    VM_IP=$(nmap -sn 192.168.16.0/24 2>/dev/null | grep -B2 "Host is up" | grep -oP '\d+\.\d+\.\d+\.\d+' | grep -v "192.168.16.2" | head -1) || true
fi

if [[ -n "$VM_IP" ]]; then
    success "VM IP found: $VM_IP"
    if timeout 3 bash -c "echo > /dev/tcp/$VM_IP/22" 2>/dev/null; then
        success "SSH port 22 is open on $VM_IP"
    else
        warn "SSH port 22 not reachable on $VM_IP"
    fi
else
    warn "VM IP could not be determined"
fi

# =====================================================================
# PHASE 2: IDENTIFY PROBLEMS
# =====================================================================
header "PHASE 2: PROBLEM ANALYSIS"

PROBLEMS=()

# Problem 1: No USB passthrough for keyboard/mouse
USB_PASSTHROUGH=$(qm config "$VMID" 2>/dev/null | grep -c "^usb" || echo "0")
if [[ "$USB_PASSTHROUGH" -eq 0 ]]; then
    error "PROBLEM: No USB devices passed through to VM"
    log "  -> Physical keyboard/mouse cannot reach the VM"
    PROBLEMS+=("usb_missing")
fi

# Problem 2: GPU reset bug
if dmesg | grep -q "failed to reset PCI device"; then
    warn "PROBLEM: AMD GPU reset bug detected"
    PROBLEMS+=("gpu_reset_bug")
fi

# Problem 3: VGA not set to 'none' with GPU passthrough
if [[ "$HOSTPCI" != "NONE" ]] && [[ "$VGA_TYPE" != "none" ]] && [[ "$VGA_TYPE" != "default" ]]; then
    warn "PROBLEM: VGA is '$VGA_TYPE' — should be 'none' with GPU passthrough"
    PROBLEMS+=("vga_conflict")
fi

# Problem 4: No QEMU Guest Agent
if ! echo "$AGENT_STATUS" | grep -q "enabled=1"; then
    warn "PROBLEM: QEMU Guest Agent not enabled"
    PROBLEMS+=("no_agent")
fi

# =====================================================================
# PHASE 3: APPLY FIXES
# =====================================================================
header "PHASE 3: FIXES"

log ""
log "${BOLD}${YELLOW}Problems found: ${#PROBLEMS[@]}${NC}"
for p in "${PROBLEMS[@]}"; do
    log "  - $p"
done
log ""

# --- Fix menu ---
log "${BOLD}Available fixes:${NC}"
log ""
log "  ${CYAN}1)${NC} Pass through USB keyboard + mouse (RECOMMENDED)"
log "  ${CYAN}2)${NC} Optimize VM configuration for GPU passthrough"
log "  ${CYAN}3)${NC} Check & fix GRUB/IOMMU kernel parameters"
log "  ${CYAN}4)${NC} Apply all fixes (1+2+3)"
log "  ${CYAN}5)${NC} SSH access only (quick-fix)"
log "  ${CYAN}6)${NC} Diagnosis only (no changes)"
log ""

read -rp "Which fix to apply? [1-6]: " FIX_CHOICE

case $FIX_CHOICE in
    1|4)
        # === FIX 1: USB PASSTHROUGH ===
        header "FIX: USB Passthrough for Keyboard & Mouse"

        # VM must be stopped for hardware changes
        if [[ "$VM_STATUS" == "running" ]]; then
            warn "VM must be stopped for USB configuration"
            read -rp "Stop VM now? [y/n]: " STOP_VM
            if [[ "$STOP_VM" == "y" ]]; then
                qm stop "$VMID"
                sleep 3
                success "VM stopped"
            else
                error "USB passthrough requires a stopped VM"
                error "Alternative: use Proxmox Web UI for hot-plug"
            fi
        fi

        info "Available USB devices:"
        log ""

        # List USB devices with numbers
        USB_DEVICES=()
        IDX=0
        while IFS= read -r line; do
            VENDOR_PRODUCT=$(echo "$line" | grep -oP '\K[0-9a-f]{4}:[0-9a-f]{4}')
            DESC=$(echo "$line" | sed 's/.*ID [0-9a-f]*:[0-9a-f]* //')

            # Filter out hubs
            if echo "$DESC" | grep -qi "hub"; then
                continue
            fi

            IDX=$((IDX + 1))
            USB_DEVICES+=("$VENDOR_PRODUCT|$DESC")
            log "  ${CYAN}$IDX)${NC} $DESC ${YELLOW}[$VENDOR_PRODUCT]${NC}"
        done < <(lsusb 2>/dev/null)

        log ""
        log "  ${CYAN}a)${NC} Pass through entire USB controller (PCI-level)"
        log "  ${CYAN}k)${NC} Auto-detect keyboard + mouse"
        log ""

        read -rp "Which devices to pass through? [numbers comma-separated / a / k]: " USB_CHOICE

        if [[ "$USB_CHOICE" == "a" ]]; then
            # Pass through entire USB controller
            info "Looking for USB controllers..."
            USB_CONTROLLERS=$(lspci | grep -i "USB controller" | head -5)
            log "$USB_CONTROLLERS"

            USB_PCI=$(lspci | grep -i "USB controller" | head -1 | awk '{print $1}')
            if [[ -n "$USB_PCI" ]]; then
                info "Passing through USB controller $USB_PCI..."
                NEXT_PCI=1
                while qm config "$VMID" | grep -q "^hostpci${NEXT_PCI}:"; do
                    NEXT_PCI=$((NEXT_PCI + 1))
                done
                qm set "$VMID" -hostpci${NEXT_PCI} "$USB_PCI"
                success "USB controller added as hostpci${NEXT_PCI}"
            fi

        elif [[ "$USB_CHOICE" == "k" ]]; then
            # Auto-detect keyboard and mouse
            info "Searching for keyboard and mouse..."

            USB_SLOT=0

            # Keyboard
            KB_LINE=$(lsusb 2>/dev/null | grep -i "keyboard\|kbd\|Logitech.*K\|Cherry\|Corsair.*K" | head -1)
            if [[ -n "$KB_LINE" ]]; then
                KB_VID=$(echo "$KB_LINE" | grep -oP 'ID \K[0-9a-f]{4}')
                KB_PID=$(echo "$KB_LINE" | grep -oP 'ID [0-9a-f]{4}:\K[0-9a-f]{4}')
                KB_DESC=$(echo "$KB_LINE" | sed 's/.*ID [0-9a-f]*:[0-9a-f]* //')
                qm set "$VMID" -usb${USB_SLOT} "host=${KB_VID}:${KB_PID}"
                success "Keyboard passed through: $KB_DESC (usb${USB_SLOT})"
                USB_SLOT=$((USB_SLOT + 1))
            else
                warn "Keyboard not auto-detected — select manually"
            fi

            # Mouse
            MS_LINE=$(lsusb 2>/dev/null | grep -i "mouse\|Logitech.*M\|gaming\|optical\|Razer\|SteelSeries" | head -1)
            if [[ -n "$MS_LINE" ]]; then
                MS_VID=$(echo "$MS_LINE" | grep -oP 'ID \K[0-9a-f]{4}')
                MS_PID=$(echo "$MS_LINE" | grep -oP 'ID [0-9a-f]{4}:\K[0-9a-f]{4}')
                MS_DESC=$(echo "$MS_LINE" | sed 's/.*ID [0-9a-f]*:[0-9a-f]* //')
                qm set "$VMID" -usb${USB_SLOT} "host=${MS_VID}:${MS_PID}"
                success "Mouse passed through: $MS_DESC (usb${USB_SLOT})"
                USB_SLOT=$((USB_SLOT + 1))
            else
                warn "Mouse not auto-detected — select manually"
            fi

        else
            # Manual selection
            IFS=',' read -ra SELECTIONS <<< "$USB_CHOICE"
            USB_SLOT=0
            for sel in "${SELECTIONS[@]}"; do
                sel=$(echo "$sel" | tr -d ' ')
                if [[ "$sel" -ge 1 ]] && [[ "$sel" -le "${#USB_DEVICES[@]}" ]] 2>/dev/null; then
                    IDX=$((sel - 1))
                    VENDOR_PRODUCT=$(echo "${USB_DEVICES[$IDX]}" | cut -d'|' -f1)
                    DESC=$(echo "${USB_DEVICES[$IDX]}" | cut -d'|' -f2)
                    VID=$(echo "$VENDOR_PRODUCT" | cut -d: -f1)
                    PID=$(echo "$VENDOR_PRODUCT" | cut -d: -f2)
                    qm set "$VMID" -usb${USB_SLOT} "host=${VID}:${PID}"
                    success "USB device passed through: $DESC (usb${USB_SLOT})"
                    USB_SLOT=$((USB_SLOT + 1))
                fi
            done
        fi

        ;;&  # Fall-through for option 4

    2|4)
        # === FIX 2: OPTIMIZE VM CONFIGURATION ===
        header "FIX: VM Configuration for GPU Passthrough"

        if [[ "$VM_STATUS" == "running" ]]; then
            warn "Some changes require a VM restart"
        fi

        # VGA to none (display comes from passthrough GPU)
        info "Setting VGA to 'none' (GPU takes over display)..."
        qm set "$VMID" -vga none
        success "VGA: none"

        # Machine type q35
        MACHINE=$(qm config "$VMID" | grep "^machine:" | awk '{print $2}' || echo "")
        if [[ "$MACHINE" != "q35" ]]; then
            info "Setting machine type to q35 (better for PCIe passthrough)..."
            qm set "$VMID" -machine q35
            success "Machine: q35"
        else
            success "Machine already q35"
        fi

        # BIOS check
        BIOS=$(qm config "$VMID" | grep "^bios:" | awk '{print $2}' || echo "seabios")
        if [[ "$BIOS" != "ovmf" ]]; then
            warn "BIOS is '$BIOS' — OVMF (UEFI) recommended for GPU passthrough"
            warn "WARNING: Changing BIOS requires OS reinstallation!"
            warn "Skipping BIOS change (decide manually)"
        else
            success "BIOS already OVMF"
        fi

        # CPU type
        CPU_TYPE=$(qm config "$VMID" | grep "^cpu:" | awk '{print $2}' || echo "")
        if [[ "$CPU_TYPE" != "host" ]]; then
            info "Setting CPU type to 'host' (best performance)..."
            qm set "$VMID" -cpu host
            success "CPU: host"
        fi

        # QEMU Guest Agent
        info "Enabling QEMU Guest Agent..."
        qm set "$VMID" -agent enabled=1
        success "Guest Agent enabled"

        # Optimize hostpci options
        HOSTPCI_LINE=$(qm config "$VMID" | grep "^hostpci0:" || echo "")
        if [[ -n "$HOSTPCI_LINE" ]]; then
            GPU_PCI_ADDR=$(echo "$HOSTPCI_LINE" | grep -oP 'hostpci0: \K[^,]+' || echo "")
            if [[ -n "$GPU_PCI_ADDR" ]]; then
                if ! echo "$HOSTPCI_LINE" | grep -q "x-vga=1"; then
                    info "Adding x-vga=1 (GPU as primary display)..."
                    qm set "$VMID" -hostpci0 "${GPU_PCI_ADDR},pcie=1,x-vga=1"
                    success "GPU passthrough optimized: pcie=1,x-vga=1"
                else
                    success "GPU passthrough already has x-vga=1"
                fi
            fi
        fi

        ;;&  # Fall-through for option 4

    3|4)
        # === FIX 3: GRUB/IOMMU ===
        header "FIX: GRUB & IOMMU Kernel Parameters"

        GRUB_LINE=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub)
        info "Current GRUB line:"
        log "  $GRUB_LINE"

        NEEDS_UPDATE=false
        CURRENT_PARAMS=$(echo "$GRUB_LINE" | grep -oP '"\K[^"]+')
        NEW_PARAMS="$CURRENT_PARAMS"

        # Check required parameters
        for PARAM in "amd_iommu=on" "iommu=pt"; do
            if ! echo "$CURRENT_PARAMS" | grep -q "$PARAM"; then
                NEW_PARAMS="$NEW_PARAMS $PARAM"
                NEEDS_UPDATE=true
                warn "Missing: $PARAM"
            else
                success "Present: $PARAM"
            fi
        done

        # Optional: pci=noats for AMD reset bug workaround
        if ! echo "$CURRENT_PARAMS" | grep -q "pci=noats"; then
            NEW_PARAMS="$NEW_PARAMS pci=noats"
            NEEDS_UPDATE=true
            info "Adding pci=noats (AMD reset workaround)"
        fi

        # Optional: video=efifb:off for clean GPU handoff
        if ! echo "$CURRENT_PARAMS" | grep -q "video=efifb:off"; then
            NEW_PARAMS="$NEW_PARAMS video=efifb:off"
            NEEDS_UPDATE=true
            info "Adding video=efifb:off (prevent host from claiming GPU framebuffer)"
        fi

        if [[ "$NEEDS_UPDATE" == "true" ]]; then
            info "New GRUB line:"
            log "  GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_PARAMS\""

            cp /etc/default/grub "/etc/default/grub.bak.$(date +%s)"

            sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_PARAMS\"|" /etc/default/grub
            update-grub 2>/dev/null
            success "GRUB updated (reboot required to take effect)"
        else
            success "GRUB parameters already correct"
        fi

        # Check VFIO modules
        info "Checking VFIO kernel modules..."
        VFIO_CONF="/etc/modules-load.d/vfio.conf"

        if [[ ! -f "$VFIO_CONF" ]]; then
            info "Creating $VFIO_CONF..."
            printf '%s\n' "vfio" "vfio_iommu_type1" "vfio_pci" > "$VFIO_CONF"
            success "VFIO modules configured"
        else
            success "VFIO configuration exists"
            while read -r line; do log "  $line"; done < "$VFIO_CONF"
        fi

        # Bind GPU to vfio-pci
        if [[ -n "$GPU_ADDR" ]]; then
            GPU_IDS=$(lspci -n -s "$GPU_ADDR" | awk '{print $3}')
            AUDIO_ADDR=$(echo "$GPU_ADDR" | sed 's/\.0$/.1/')
            AUDIO_IDS=$(lspci -n -s "$AUDIO_ADDR" 2>/dev/null | awk '{print $3}' || echo "")

            VFIO_IDS="$GPU_IDS"
            [[ -n "$AUDIO_IDS" ]] && VFIO_IDS="$VFIO_IDS,$AUDIO_IDS"

            info "GPU device IDs: $VFIO_IDS"

            VFIO_PCI_CONF="/etc/modprobe.d/vfio-pci.conf"
            echo "options vfio-pci ids=$VFIO_IDS" > "$VFIO_PCI_CONF"
            success "VFIO-PCI IDs configured: $VFIO_IDS"

            # Blacklist amdgpu on host
            cat > /etc/modprobe.d/blacklist-gpu.conf << 'BLACKLIST'
blacklist amdgpu
blacklist radeon
BLACKLIST
            success "amdgpu/radeon blacklisted on host"
        fi

        # Update initramfs
        info "Updating initramfs..."
        update-initramfs -u -k all 2>/dev/null
        success "initramfs updated"

        ;;

    5)
        # === FIX 5: QUICK SSH ===
        header "QUICK-FIX: SSH Access to VM"

        if [[ -n "$VM_IP" ]]; then
            info "VM reachable at: $VM_IP"
            log ""
            log "${BOLD}Connect now with:${NC}"
            log "  ${GREEN}ssh user@${VM_IP}${NC}"
            log ""
            log "If SSH is not configured in the VM:"
            log "  The VM has a login prompt on the physical monitor."
            log "  You need USB passthrough for keyboard (-> option 1)"
        else
            warn "VM IP not found"
            info "Possible IPs in network:"

            arp -an 2>/dev/null | grep -v "incomplete" | while read -r line; do
                IP=$(echo "$line" | grep -oP '\d+\.\d+\.\d+\.\d+')
                if [[ "$IP" != "192.168.16.2" ]] && echo "$IP" | grep -q "192.168.16"; then
                    log "  $IP"
                fi
            done

            log ""
            info "Running ping scan..."
            for i in $(seq 1 254); do
                IP="192.168.16.$i"
                if [[ "$IP" != "192.168.16.2" ]]; then
                    if timeout 0.5 ping -c1 "$IP" &>/dev/null; then
                        log "  ${GREEN}$IP responds${NC}"
                    fi
                fi
            done
        fi
        ;;

    6)
        info "Diagnosis only — no changes made"
        ;;

    *)
        error "Invalid selection"
        ;;
esac

# =====================================================================
# PHASE 4: SUMMARY
# =====================================================================
header "SUMMARY"

log ""
log "${BOLD}Current VM $VMID configuration after fixes:${NC}"
qm config "$VMID" | grep -E 'hostpci|vga|machine|tablet|usb|cpu|memory|net|boot|agent|bios' | while read -r line; do
    log "  $line"
done

log ""
if [[ -n "$VM_IP" ]]; then
    log "${BOLD}VM access:${NC}"
    log "  SSH:     ${GREEN}ssh user@${VM_IP}${NC}"
    log "  Console: ${YELLOW}Monitor on GPU + USB keyboard/mouse${NC}"
fi

log ""
log "${BOLD}Next steps:${NC}"
log "  1. Start VM:  ${CYAN}qm start $VMID${NC}"
log "  2. Status:    ${CYAN}qm status $VMID${NC}"
log "  3. Console:   Connect monitor to RX 6800 XT"
log "  4. SSH:       ${CYAN}ssh user@<VM-IP>${NC}"
log ""

if echo "${FIX_CHOICE:-0}" | grep -qE "3|4"; then
    log "${RED}${BOLD}*** REBOOT of Proxmox host required for GRUB changes ***${NC}"
    log "  ${CYAN}reboot${NC}"
    log ""
    read -rp "Reboot now? [y/n]: " DO_REBOOT
    if [[ "$DO_REBOOT" == "y" ]]; then
        info "Rebooting in 5 seconds..."
        sleep 5
        reboot
    fi
fi

log ""
success "Debug log saved: $LOG_FILE"
log "${BOLD}Script complete.${NC}"
