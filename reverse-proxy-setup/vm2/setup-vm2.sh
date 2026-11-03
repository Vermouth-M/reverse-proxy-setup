#!/usr/bin/env bash
# Setup VM2 = Server X (backend Nginx)
# Jalankan: sudo bash setup-vm2.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Jalankan dengan sudo"; exit 1; }
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[1/3] Install nginx..."
apt-get update -y
apt-get install -y nginx curl

echo "[2/3] Pasang halaman Server X..."
cp "$DIR/index.html" /var/www/html/index.html

echo "[3/3] Start nginx..."
nginx -t
systemctl enable nginx
systemctl restart nginx
if command -v ufw >/dev/null; then ufw allow 80/tcp || true; fi

echo "Selesai. Tes: curl http://localhost"
