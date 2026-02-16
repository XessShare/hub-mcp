#!/usr/bin/env bash
# setup-samba-fitna.sh — Samba config for Omarchy SSD fitna-shared export
#
# Target host: pve (192.168.16.2)
# Exports:     /mnt/omarchy/home/fitna as [fitna-shared]
#
# Prerequisites:
#   - Omarchy SSD mounted at /mnt/omarchy (see proxmox/storage/mnt-omarchy.mount)
#   - Mount must be rw (not ro) for write access
#
# Usage:
#   bash proxmox/fileserver/setup-samba-fitna.sh [SHARE_USER]
#
# After running:
#   1. Set Samba password:  smbpasswd -a fitna-user
#   2. Test config:         testparm -s /etc/samba/smb.conf
#   3. Access from Windows: \\192.168.16.2\fitna-shared
#   4. Access from Linux:   mount -t cifs //192.168.16.2/fitna-shared /mnt/fitna

set -euo pipefail

# --- Configuration ---
SHARE_USER="${1:-fitna-user}"
SHARE_PATH="/mnt/omarchy/home/fitna"
SMB_CONF="/etc/samba/smb.conf"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

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

# --- Verify mount ---
if ! mountpoint -q /mnt/omarchy 2>/dev/null; then
    err "/mnt/omarchy is not mounted."
    err "Start the mount unit first: systemctl start mnt-omarchy.mount"
    exit 1
fi

if ! [ -d "$SHARE_PATH" ]; then
    warn "Share path $SHARE_PATH does not exist. Creating..."
    mkdir -p "$SHARE_PATH"
    chown "$SHARE_USER":"$SHARE_USER" "$SHARE_PATH" 2>/dev/null || true
fi

# --- Install Samba ---
if ! command -v smbd &>/dev/null; then
    log "Installing Samba..."
    apt-get update -qq
    apt-get install -y -qq samba samba-common
fi

# --- Create system user ---
if ! id "$SHARE_USER" &>/dev/null; then
    log "Creating system user: $SHARE_USER"
    useradd -M -s /usr/sbin/nologin "$SHARE_USER"
fi

# --- Set ownership ---
chown -R "$SHARE_USER":"$SHARE_USER" "$SHARE_PATH"
chmod 2770 "$SHARE_PATH"

# --- Backup existing config ---
if [ -f "$SMB_CONF" ]; then
    cp "$SMB_CONF" "${SMB_CONF}.bak.${TIMESTAMP}"
    log "Backed up existing config to ${SMB_CONF}.bak.${TIMESTAMP}"
fi

# --- Write Samba config ---
log "Writing Samba configuration..."
cat > "$SMB_CONF" <<'SMBCONF'
[global]
   workgroup = WORKGROUP
   server string = pve Samba (Fitna Data Authority)
   server role = standalone server
   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
   panic action = /usr/share/samba/panic-action %d
   obey pam restrictions = yes
   unix password sync = yes
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
   pam password change = yes
   map to guest = bad user
   usershare allow guests = no

[fitna-shared]
   path = /mnt/omarchy/home/fitna
   browseable = yes
   read only = no
   guest ok = no
   valid users = fitna-user
   force create mode = 0660
   force directory mode = 0770
SMBCONF

# --- Validate config ---
log "Validating Samba configuration..."
if ! testparm -s "$SMB_CONF" >/dev/null 2>&1; then
    err "Samba configuration validation failed!"
    err "Restoring backup..."
    cp "${SMB_CONF}.bak.${TIMESTAMP}" "$SMB_CONF"
    exit 1
fi

# --- Enable and restart services ---
log "Enabling and restarting Samba services..."
systemctl enable smbd nmbd
systemctl restart smbd nmbd

log "Samba setup complete."
log ""
log "Next steps:"
log "  1. Set Samba password:  smbpasswd -a $SHARE_USER"
log "  2. From Windows:        \\\\192.168.16.2\\fitna-shared"
log "  3. From Linux:          mount -t cifs //192.168.16.2/fitna-shared /mnt/fitna -o username=$SHARE_USER"
