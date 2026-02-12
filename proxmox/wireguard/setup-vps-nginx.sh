#!/usr/bin/env bash
# setup-vps-nginx.sh — Phase 7b: Nginx reverse proxy on Hetzner VPS
#
# Configures nginx to proxy public HTTPS requests to fitnaai via WireGuard.
# Uses Let's Encrypt (certbot) for TLS.
#
# Run on: Hetzner VPS
# Usage:  sudo bash setup-vps-nginx.sh [DOMAIN]
# Example: sudo bash setup-vps-nginx.sh api.fitnaai.de

set -euo pipefail

DOMAIN="${1:-api.fitnaai.de}"
BACKEND="http://10.0.0.2:8000"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

echo "============================================"
echo "  Phase 7b: Nginx Reverse Proxy (VPS)"
echo "============================================"
echo "  Domain:  $DOMAIN"
echo "  Backend: $BACKEND (via WireGuard)"
echo ""

# Install nginx + certbot
echo "==> Installing nginx and certbot..."
apt-get update -qq
apt-get install -y -qq nginx certbot python3-certbot-nginx

# Check WireGuard tunnel
echo "==> Checking WireGuard tunnel..."
if ping -c1 -W3 10.0.0.2 &>/dev/null; then
    echo "    Tunnel to 10.0.0.2: OK"
else
    echo "    WARNING: Cannot reach 10.0.0.2 via WireGuard."
    echo "    Ensure wg0 is up: systemctl status wg-quick@wg0"
    echo "    Continuing anyway (nginx will be configured)..."
fi

# Write nginx config
cat > "$NGINX_CONF" <<EOF
# fitnaai reverse proxy — $DOMAIN
# Backend: fitnaai API at 10.0.0.2:8000 (via WireGuard tunnel)

upstream fitnaai {
    server 10.0.0.2:8000;
}

server {
    listen 80;
    server_name $DOMAIN;

    # Redirect to HTTPS (certbot will modify this)
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # TLS certs managed by certbot (placeholder until certbot runs)
    # ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # Security headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;

    location / {
        limit_req zone=api burst=20 nodelay;

        proxy_pass $BACKEND;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Timeouts
        proxy_connect_timeout 30s;
        proxy_send_timeout 60s;
        proxy_read_timeout 120s;
    }

    location /health {
        proxy_pass $BACKEND/health;
        access_log off;
    }
}
EOF

# Enable site
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test config
echo "==> Testing nginx configuration..."
nginx -t

# Reload nginx
systemctl reload nginx

# Get TLS certificate
echo "==> Requesting TLS certificate..."
echo "    Domain: $DOMAIN"
echo ""
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@$DOMAIN || {
    echo "    WARNING: Certbot failed. You can run manually:"
    echo "    certbot --nginx -d $DOMAIN"
}

echo ""
echo "============================================"
echo "  VPS Reverse Proxy Configured"
echo "============================================"
echo ""
echo "  Public URL:  https://$DOMAIN"
echo "  Backend:     $BACKEND (via WireGuard)"
echo "  TLS:         Let's Encrypt (auto-renew)"
echo "  Nginx conf:  $NGINX_CONF"
echo ""
echo "  Test:"
echo "    curl https://$DOMAIN/health"
echo ""
echo "  Auto-renewal check:"
echo "    certbot renew --dry-run"
echo ""
