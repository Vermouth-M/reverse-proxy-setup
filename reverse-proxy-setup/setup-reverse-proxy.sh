#!/usr/bin/env bash
# =============================================================
# Setup Host 1: Ethernet Bridge + KVM (VM1, VM2) + Docker + Nginx Reverse Proxy
# Target OS : Ubuntu 22.04 / 24.04
# Pemakaian : sudo ./setup-reverse-proxy.sh <tahap>
#   tahap   : packages | bridge | docker | nginx | all
# PENTING   : edit bagian KONFIGURASI di bawah sebelum dijalankan.
# =============================================================
set -euo pipefail

# ---------------- KONFIGURASI (SESUAIKAN) ----------------
IFACE="eth0"                  # NIC ethernet fisik (cek: ip -br link)
BRIDGE="br0"                  # nama bridge
HOST_IP="192.168.1.10/24"     # IP Host 1 (dipindah ke bridge)
GATEWAY="192.168.1.1"
DNS="8.8.8.8,1.1.1.1"

VM1_IP="192.168.1.101"        # Server Utama (VM1)
VM2_IP="192.168.1.102"        # Server X     (VM2)
DOCKER_PORT="8082"            # port container Docker di Host 1 (Server 2)

DOMAIN_UTAMA="utama.local"
DOMAIN_X="serverx.local"
DOMAIN_2="server2.local"
# ---------------------------------------------------------

need_root() { [[ $EUID -eq 0 ]] || { echo "Jalankan dengan sudo/root."; exit 1; }; }
log() { echo -e "\n\e[1;32m==> $*\e[0m"; }

install_packages() {
  log "Install paket KVM/libvirt, bridge-utils, nginx"
  apt-get update
  apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst \
    bridge-utils nginx curl ca-certificates
  systemctl enable --now libvirtd
  [[ -n "${SUDO_USER:-}" ]] && usermod -aG libvirt,kvm "$SUDO_USER" || true
}

setup_bridge() {
  log "Membuat bridge ${BRIDGE} di atas ${IFACE}"
  ip link show "$IFACE" >/dev/null 2>&1 || { echo "Interface $IFACE tidak ada"; exit 1; }

  local f=/etc/netplan/01-bridge.yaml
  [[ -f $f ]] && cp "$f" "$f.bak.$(date +%s)"

  cat > "$f" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: false
  bridges:
    ${BRIDGE}:
      interfaces: [${IFACE}]
      addresses: [${HOST_IP}]
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: [${DNS}]
      parameters:
        stp: false
        forward-delay: 0
EOF
  chmod 600 "$f"

  echo "File netplan dibuat: $f"
  echo "Menerapkan dengan 'netplan try' (otomatis rollback 120 dtk bila koneksi putus)."
  echo "Bila lewat SSH dan koneksi putus, tunggu rollback."
  netplan try --timeout 120
}

setup_docker() {
  log "Install Docker & jalankan container Server 2"
  if ! command -v docker >/dev/null; then
    curl -fsSL https://get.docker.com | sh
  fi
  systemctl enable --now docker
  docker rm -f server2 >/dev/null 2>&1 || true
  docker run -d --name server2 --restart unless-stopped \
    -p 127.0.0.1:${DOCKER_PORT}:80 nginx:alpine
  # halaman identitas supaya mudah dites
  docker exec server2 sh -c "echo '<h1>Server 2 (Docker)</h1>' > /usr/share/nginx/html/index.html"
}

setup_nginx() {
  log "Konfigurasi Nginx reverse proxy"
  cat > /etc/nginx/sites-available/reverse-proxy.conf <<EOF
# ---- Upstream ----
upstream server_utama { server ${VM1_IP}:80; }        # VM1
upstream server_x     { server ${VM2_IP}:80; }        # VM2
upstream server_2     { server 127.0.0.1:${DOCKER_PORT}; }  # Docker

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

# ---- Server Utama (VM1) ----
server {
    listen 80;
    server_name ${DOMAIN_UTAMA};
    location / {
        proxy_pass http://server_utama;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade           \$http_upgrade;
        proxy_set_header Connection        \$connection_upgrade;
    }
}

# ---- Server X (VM2) ----
server {
    listen 80;
    server_name ${DOMAIN_X};
    location / {
        proxy_pass http://server_x;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade           \$http_upgrade;
        proxy_set_header Connection        \$connection_upgrade;
    }
}

# ---- Server 2 (Docker) ----
server {
    listen 80;
    server_name ${DOMAIN_2};
    location / {
        proxy_pass http://server_2;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade           \$http_upgrade;
        proxy_set_header Connection        \$connection_upgrade;
    }
}

# ---- Default: tolak host yang tidak dikenal ----
server {
    listen 80 default_server;
    server_name _;
    return 444;
}
EOF
  rm -f /etc/nginx/sites-enabled/default
  ln -sf /etc/nginx/sites-available/reverse-proxy.conf /etc/nginx/sites-enabled/reverse-proxy.conf
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx

  if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow 80/tcp; ufw allow 443/tcp
  fi
  echo "Selesai. Tes dari Host 2:  curl -H 'Host: ${DOMAIN_UTAMA}' http://${HOST_IP%/*}/"
}

need_root
case "${1:-}" in
  packages) install_packages ;;
  bridge)   setup_bridge ;;
  docker)   setup_docker ;;
  nginx)    setup_nginx ;;
  all)      install_packages; setup_bridge; setup_docker; setup_nginx ;;
  *) echo "Pemakaian: sudo $0 {packages|bridge|docker|nginx|all}"; exit 1 ;;
esac
