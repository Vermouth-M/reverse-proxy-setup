#!/usr/bin/env bash
# Setup VM1 = Server Utama + Nginx Reverse Proxy
# Jalankan: sudo bash setup-vm1.sh
set -euo pipefail

# ====== SESUAIKAN ======
VM2_IP="192.168.1.102"
DOCKER_IP="192.168.1.100"     # IP host yang menjalankan Docker
DOCKER_PORT="8083"
# =======================

[ "$(id -u)" -eq 0 ] || { echo "Jalankan dengan sudo"; exit 1; }
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[1/5] Install nginx..."
apt-get update -y
apt-get install -y nginx curl

echo "[2/5] Pasang halaman Server Utama..."
cp "$DIR/index.html" /var/www/html/index.html

echo "[3/5] Pasang konfigurasi reverse proxy..."
sed -e "s/__VM2_IP__/${VM2_IP}/g" \
    -e "s/__DOCKER_IP__/${DOCKER_IP}/g" \
    -e "s/__DOCKER_PORT__/${DOCKER_PORT}/g" \
    "$DIR/reverse-proxy.conf" > /etc/nginx/sites-available/reverse-proxy
ln -sf /etc/nginx/sites-available/reverse-proxy /etc/nginx/sites-enabled/reverse-proxy
rm -f /etc/nginx/sites-enabled/default

echo "[4/5] Tes konfigurasi..."
nginx -t

echo "[5/5] Restart nginx..."
systemctl enable nginx
systemctl restart nginx

if command -v ufw >/dev/null; then ufw allow 80/tcp || true; fi

IP="$(hostname -I | awk '{print $1}')"
echo
echo "Selesai. Tes dari Host 2:"
echo "  curl http://$IP/"
echo "  curl http://$IP/x/"
echo "  curl http://$IP/server2/"
