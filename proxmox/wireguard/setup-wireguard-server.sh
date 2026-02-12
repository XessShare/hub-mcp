#!/usr/bin/env bash
# setup-wireguard-server.sh — Phase 7a: WireGuard server on 192.168.16.2
#
# Creates a WireGuard tunnel endpoint on the production host.
# The Hetzner VPS connects as a client, creating a private tunnel
# through which nginx can reach fitnaai.
#
# Tunnel network: 10.0.0.0/24
#   Server (16.2):   10.0.0.2
#   Client (VPS):    10.0.0.1
#
# Run on: pve GamingPC (192.168.16.2) as root
# Usage:  sudo bash setup-wireguard-server.sh [VPS_PUBLIC_IP]

set -euo pipefail

VPS_PUBLIC_IP="${1:-}"
WG_INTERFACE="wg0"
WG_PORT="51820"
WG_DIR="/etc/wireguard"
SERVER_IP="10.0.0.2/24"

echo "============================================"
echo "  Phase 7a: WireGuard Server (192.168.16.2)"
echo "============================================"
echo ""

# Install WireGuard
if ! command -v wg &>/dev/null; then
    echo "==> Installing WireGuard..."
    apt-get update -qq
    apt-get install -y -qq wireguard
fi

# Generate keys
mkdir -p "$WG_DIR"
chmod 700 "$WG_DIR"

if [[ ! -f "$WG_DIR/server_private.key" ]]; then
    echo "==> Generating server keys..."
    wg genkey | tee "$WG_DIR/server_private.key" | wg pubkey > "$WG_DIR/server_public.key"
    chmod 600 "$WG_DIR/server_private.key"
else
    echo "==> Server keys already exist."
fi

SERVER_PRIVKEY=$(cat "$WG_DIR/server_private.key")
SERVER_PUBKEY=$(cat "$WG_DIR/server_public.key")

# Generate client (VPS) keys if not exist
if [[ ! -f "$WG_DIR/vps_private.key" ]]; then
    echo "==> Generating VPS client keys..."
    wg genkey | tee "$WG_DIR/vps_private.key" | wg pubkey > "$WG_DIR/vps_public.key"
    chmod 600 "$WG_DIR/vps_private.key"
fi

VPS_PRIVKEY=$(cat "$WG_DIR/vps_private.key")
VPS_PUBKEY=$(cat "$WG_DIR/vps_public.key")

# Write server config
cat > "$WG_DIR/$WG_INTERFACE.conf" <<EOF
# WireGuard Server — 192.168.16.2
# Tunnel: 10.0.0.2 (server) ↔ 10.0.0.1 (VPS)

[Interface]
PrivateKey = $SERVER_PRIVKEY
Address = $SERVER_IP
ListenPort = $WG_PORT

# Allow fitnaai traffic from tunnel to reach localhost:8000
PostUp = iptables -A FORWARD -i $WG_INTERFACE -j ACCEPT
PostUp = iptables -t nat -A PREROUTING -i $WG_INTERFACE -p tcp --dport 8000 -j DNAT --to-destination 127.0.0.1:8000
PostDown = iptables -D FORWARD -i $WG_INTERFACE -j ACCEPT
PostDown = iptables -t nat -D PREROUTING -i $WG_INTERFACE -p tcp --dport 8000 -j DNAT --to-destination 127.0.0.1:8000

[Peer]
# Hetzner VPS
PublicKey = $VPS_PUBKEY
AllowedIPs = 10.0.0.1/32
EOF

if [[ -n "$VPS_PUBLIC_IP" ]]; then
    echo "Endpoint = $VPS_PUBLIC_IP:$WG_PORT" >> "$WG_DIR/$WG_INTERFACE.conf"
fi

chmod 600 "$WG_DIR/$WG_INTERFACE.conf"

# Enable and start
systemctl enable wg-quick@$WG_INTERFACE
systemctl restart wg-quick@$WG_INTERFACE

# Open firewall for WireGuard
iptables -C INPUT -p udp --dport "$WG_PORT" -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport "$WG_PORT" -j ACCEPT
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
fi

# Write VPS client config (to be transferred to the VPS)
cat > "$WG_DIR/vps-client.conf" <<EOF
# WireGuard Client — Hetzner VPS
# Copy this file to /etc/wireguard/wg0.conf on the VPS

[Interface]
PrivateKey = $VPS_PRIVKEY
Address = 10.0.0.1/24

[Peer]
# Production Server (192.168.16.2)
PublicKey = $SERVER_PUBKEY
Endpoint = YOUR_HOME_PUBLIC_IP:$WG_PORT
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
EOF

echo ""
echo "============================================"
echo "  WireGuard Server Configured"
echo "============================================"
echo ""
echo "  Server address: 10.0.0.2"
echo "  Server pubkey:  $SERVER_PUBKEY"
echo "  Listen port:    $WG_PORT"
echo ""
echo "  VPS client config saved to: $WG_DIR/vps-client.conf"
echo ""
echo "  NEXT STEPS:"
echo "  1. Get your home public IP (curl ifconfig.me)"
echo "  2. Edit $WG_DIR/vps-client.conf and replace YOUR_HOME_PUBLIC_IP"
echo "  3. Copy vps-client.conf to the Hetzner VPS:"
echo "     scp $WG_DIR/vps-client.conf root@<VPS_IP>:/etc/wireguard/wg0.conf"
echo "  4. On VPS: systemctl enable --now wg-quick@wg0"
echo "  5. Test: ping 10.0.0.2 (from VPS)"
echo "  6. Set up nginx: bash proxmox/wireguard/setup-vps-nginx.sh"
echo ""
echo "  IMPORTANT: Configure port forwarding on your router:"
echo "  WAN port $WG_PORT/UDP → 192.168.16.2:$WG_PORT/UDP"
echo ""
