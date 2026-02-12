#!/usr/bin/env bash
# firewall-prod.sh — Production firewall rules for 192.168.16.2
#
# Locks down the production host:
# - SSH from LAN only
# - Proxmox Web UI from LAN only
# - fitnaai API from localhost + WireGuard only
# - WireGuard port open for VPS tunnel
# - All other inbound traffic dropped
#
# Run on: pve GamingPC (192.168.16.2) as root
# Usage:  sudo bash firewall-prod.sh

set -euo pipefail

echo "============================================"
echo "  Production Firewall — 192.168.16.2"
echo "============================================"
echo ""

# Flush existing rules
iptables -F INPUT
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Loopback
iptables -A INPUT -i lo -j ACCEPT

# Established connections
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# ICMP (ping)
iptables -A INPUT -p icmp -j ACCEPT

# SSH from LAN only
iptables -A INPUT -s 192.168.16.0/24 -p tcp --dport 22 -j ACCEPT

# Proxmox Web UI from LAN only
iptables -A INPUT -s 192.168.16.0/24 -p tcp --dport 8006 -j ACCEPT

# WireGuard (from anywhere — needed for VPS tunnel)
iptables -A INPUT -p udp --dport 51820 -j ACCEPT

# fitnaai API from WireGuard tunnel only
iptables -A INPUT -s 10.0.0.0/24 -p tcp --dport 8000 -j ACCEPT

# Ollama — localhost only (Docker handles this via 127.0.0.1 bind)
# No explicit rule needed

# NAT for VM network (vmbr1)
iptables -A FORWARD -i vmbr1 -o vmbr0 -j ACCEPT
iptables -A FORWARD -i vmbr0 -o vmbr1 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -t nat -A POSTROUTING -s 192.168.20.0/24 -o vmbr0 -j MASQUERADE

# Save
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
    echo "    Rules saved via netfilter-persistent."
else
    echo "    WARNING: Install iptables-persistent to persist rules."
    echo "    apt install iptables-persistent"
fi

echo ""
echo "  Allowed inbound:"
echo "    SSH (22)       ← 192.168.16.0/24 only"
echo "    PVE (8006)     ← 192.168.16.0/24 only"
echo "    WireGuard (51820) ← anywhere (UDP)"
echo "    fitnaai (8000) ← 10.0.0.0/24 (WireGuard) only"
echo ""
echo "  Default policy: DROP"
echo ""
