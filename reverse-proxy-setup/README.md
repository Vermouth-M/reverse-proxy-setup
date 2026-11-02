# Tutorial Reverse Proxy: Ethernet Bridge, VM, Docker, dan Nginx

Panduan langkah demi langkah untuk membangun topologi pada diagram "Tugas 2 Reverse Proxy", memakai script `setup-reverse-proxy.sh`.

## Isi Paket

| File | Fungsi |
|---|---|
| `README.md` | Tutorial ini |
| `setup-reverse-proxy.sh` | Script setup Host 1 (bridge, Docker, Nginx) |

## 1. Gambaran Topologi

```
            Internet / Klien
                  |
        Host 2 (klien uji)
                  |
   +---------------------------------------+
   |  HOST 1                               |
   |  Nginx Reverse Proxy (port 80)        |
   |        |                              |
   |   [ br0 : Ethernet Bridge ]           |
   |     |          |           |          |
   |    VM1        VM2       Docker        |
   +-----|----------|-----------|----------+
         |          |           |
   Server Utama   Server X   Server 2
```

Peran tiap komponen:

- **Ethernet Bridge (br0)**: menyambungkan NIC fisik Host 1 dengan VM sehingga VM mendapat IP di jaringan LAN yang sama.
- **VM1 dan VM2**: mesin virtual KVM. VM1 menjadi Server Utama, VM2 menjadi Server X.
- **Docker**: container yang menjadi Server 2.
- **Reverse Proxy (Nginx)**: satu pintu masuk. Request diteruskan ke server tujuan berdasarkan nama domain.
- **Host 2**: komputer lain yang dipakai untuk menguji akses.

Asumsi yang dipakai (ubah sesuai kebutuhan):

| Komponen | Nilai |
|---|---|
| Jaringan LAN | 192.168.1.0/24, gateway 192.168.1.1 |
| Host 1 (bridge br0) | 192.168.1.10 |
| VM1 (Server Utama) | 192.168.1.101, domain `utama.local` |
| VM2 (Server X) | 192.168.1.102, domain `serverx.local` |
| Docker (Server 2) | 127.0.0.1:8082, domain `server2.local` |
| OS Host 1 | Ubuntu 22.04 atau 24.04 |

## 2. Prasyarat

- Host 1 memakai **kabel ethernet**. Wifi pada umumnya tidak bisa di-bridge, jadi bridge hanya berfungsi di atas NIC kabel.
- CPU mendukung virtualisasi. Cek dengan `egrep -c '(vmx|svm)' /proc/cpuinfo`; hasilnya harus lebih dari 0.
- Akses root/sudo, dan sebaiknya akses langsung ke layar atau konsol Host 1. Mengubah jaringan lewat SSH bisa memutus koneksi.
- Dua file ISO Ubuntu Server (atau OS lain) untuk VM1 dan VM2.

## 3. Menyiapkan Script

1. Ekstrak zip dan salin folder ke Host 1.
2. Cek nama interface ethernet: `ip -br link`. Contohnya `eth0`, `enp3s0`, atau `eno1`.
3. Buka `setup-reverse-proxy.sh` dan edit bagian **KONFIGURASI**: `IFACE`, `HOST_IP`, `GATEWAY`, `VM1_IP`, `VM2_IP`, dan domain.
4. Beri izin eksekusi:

```bash
chmod +x setup-reverse-proxy.sh
```

Script punya beberapa tahap yang bisa dijalankan satu per satu (disarankan, supaya mudah dicek) atau sekaligus dengan `all`:

| Perintah | Fungsi |
|---|---|
| `sudo ./setup-reverse-proxy.sh packages` | Install KVM, libvirt, bridge-utils, Nginx |
| `sudo ./setup-reverse-proxy.sh bridge` | Membuat bridge `br0` lewat Netplan |
| `sudo ./setup-reverse-proxy.sh docker` | Install Docker dan menjalankan container Server 2 |
| `sudo ./setup-reverse-proxy.sh nginx` | Menulis konfigurasi dan mengaktifkan Nginx reverse proxy |
| `sudo ./setup-reverse-proxy.sh all` | Semua tahap di atas berurutan |

**Catatan:** tahap VM1 dan VM2 dibuat manual (bagian 5) karena butuh ISO dan instalasi OS.

## 4. Membuat Ethernet Bridge

```bash
sudo ./setup-reverse-proxy.sh packages
sudo ./setup-reverse-proxy.sh bridge
```

Script membuat `/etc/netplan/01-bridge.yaml` seperti berikut:

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: false
  bridges:
    br0:
      interfaces: [eth0]
      addresses: [192.168.1.10/24]
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      parameters:
        stp: false
        forward-delay: 0
```

Script memakai `netplan try`. Jika setelah konfigurasi koneksi putus dan Anda tidak menekan ENTER, perubahan otomatis dibatalkan setelah 120 detik. Ini pengaman supaya Anda tidak terkunci dari server.

Verifikasi:

```bash
ip -br addr show br0     # br0 harus memegang IP 192.168.1.10
bridge link              # eth0 harus terdaftar sebagai anggota br0
ping -c 3 192.168.1.1    # gateway harus terjangkau
```

Jika Anda memakai Ubuntu Desktop dengan NetworkManager, ganti `renderer: networkd` menjadi `renderer: NetworkManager`, atau buat bridge dengan `nmcli`.

## 5. Membuat VM1 dan VM2 (KVM)

Beri izin user Anda ke grup libvirt lalu login ulang:

```bash
sudo usermod -aG libvirt,kvm $USER
```

Buat VM1 (Server Utama):

```bash
sudo virt-install \
  --name vm1 --memory 1024 --vcpus 1 \
  --disk size=10 \
  --cdrom /path/ubuntu-server.iso \
  --os-variant ubuntu22.04 \
  --network bridge=br0 \
  --graphics vnc,listen=0.0.0.0
```

Ulangi untuk VM2 dengan `--name vm2`. Opsi `--network bridge=br0` membuat VM tersambung ke bridge, sehingga VM tampil sebagai perangkat tersendiri di LAN.

Sambungkan ke layar instalasi dengan VNC viewer ke `IP-Host1:5900` (VM berikutnya biasanya `5901`), atau gunakan `virt-manager` jika memakai desktop.

Saat instalasi OS di dalam VM, atur IP statis:

- VM1: `192.168.1.101/24`, gateway `192.168.1.1`
- VM2: `192.168.1.102/24`, gateway `192.168.1.1`

Setelah instalasi selesai, di dalam **masing-masing VM** install web server dan buat halaman identitas:

```bash
# di VM1
sudo apt update && sudo apt install -y nginx
echo '<h1>Server Utama (VM1)</h1>' | sudo tee /var/www/html/index.html

# di VM2
sudo apt update && sudo apt install -y nginx
echo '<h1>Server X (VM2)</h1>' | sudo tee /var/www/html/index.html
```

Tes dari Host 1:

```bash
curl http://192.168.1.101
curl http://192.168.1.102
```

## 6. Menjalankan Docker (Server 2)

```bash
sudo ./setup-reverse-proxy.sh docker
```

Script menginstall Docker dan menjalankan container `nginx:alpine` bernama `server2` yang hanya mendengarkan di `127.0.0.1:8082`. Karena hanya terbuka di localhost, container tidak bisa diakses langsung dari luar dan hanya bisa dicapai lewat reverse proxy.

Verifikasi:

```bash
docker ps
curl http://127.0.0.1:8082
```

## 7. Konfigurasi Nginx Reverse Proxy

```bash
sudo ./setup-reverse-proxy.sh nginx
```

Script menulis `/etc/nginx/sites-available/reverse-proxy.conf`. Intinya ada tiga blok `server`, masing-masing meneruskan ke upstream sesuai nama domain:

```nginx
upstream server_utama { server 192.168.1.101:80; }
upstream server_x     { server 192.168.1.102:80; }
upstream server_2     { server 127.0.0.1:8082; }

server {
    listen 80;
    server_name utama.local;
    location / {
        proxy_pass http://server_utama;
        proxy_set_header Host            $host;
        proxy_set_header X-Real-IP       $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
# blok serupa untuk serverx.local -> server_x
# dan server2.local -> server_2
```

Penjelasan header:

- `Host`: meneruskan nama domain asli ke server tujuan.
- `X-Real-IP` dan `X-Forwarded-For`: agar server tujuan tahu IP klien sebenarnya, bukan IP proxy.
- `Upgrade` dan `Connection`: agar WebSocket tetap bekerja lewat proxy.

Blok `default_server` mengembalikan kode 444 (koneksi ditutup) untuk request dengan domain yang tidak dikenal, jadi proxy tidak menjawab sembarang host.

Perintah pengelolaan yang sering dipakai:

```bash
sudo nginx -t                 # cek sintaks
sudo systemctl reload nginx   # terapkan perubahan tanpa downtime
sudo tail -f /var/log/nginx/error.log
```

## 8. Pengujian dari Host 2

Agar nama domain dikenali, tambahkan ke file hosts di **Host 2**.

- Linux/macOS: `/etc/hosts`
- Windows: `C:\Windows\System32\drivers\etc\hosts` (buka sebagai Administrator)

```
192.168.1.10   utama.local serverx.local server2.local
```

Lalu uji:

```bash
curl http://utama.local     # harus menampilkan: Server Utama (VM1)
curl http://serverx.local   # harus menampilkan: Server X (VM2)
curl http://server2.local   # harus menampilkan: Server 2 (Docker)
```

Tanpa mengubah file hosts, Anda bisa menguji dengan header Host:

```bash
curl -H 'Host: utama.local' http://192.168.1.10/
```

Atau buka ketiga alamat tersebut di browser Host 2.

## 9. Troubleshooting

| Gejala | Penyebab umum | Solusi |
|---|---|---|
| Koneksi Host 1 putus setelah bridge | IP, gateway, atau nama interface salah | Tunggu rollback `netplan try`, lalu cek `ip -br link` dan perbaiki konfigurasi |
| VM tidak dapat IP / tidak terjangkau | VM tidak tersambung ke `br0`, atau memakai Wifi | Pastikan `--network bridge=br0` dan Host 1 memakai kabel |
| `502 Bad Gateway` | Upstream mati atau IP salah | `curl` langsung ke IP VM dari Host 1; cek web server di VM berjalan |
| `504 Gateway Timeout` | Firewall di VM memblokir port 80 | `sudo ufw allow 80/tcp` di VM |
| Domain tidak ditemukan | File hosts di Host 2 belum diisi | Tambahkan entri hosts seperti bagian 8 |
| Respon kosong (444) | Domain tidak cocok dengan `server_name` | Periksa ejaan domain atau header Host |
| Docker bisa diakses tapi proxy gagal | Port container berbeda | Cek `docker ps` dan samakan dengan `DOCKER_PORT` |
| `nginx -t` gagal | Salah sintaks | Baca pesan error baris yang dilaporkan |

## 10. Pengembangan Lanjutan (Opsional)

**HTTPS dengan sertifikat self-signed (jaringan lokal):**

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/proxy.key -out /etc/ssl/certs/proxy.crt \
  -subj "/CN=*.local"
```

Lalu tambahkan pada tiap blok server:

```nginx
listen 443 ssl;
ssl_certificate     /etc/ssl/certs/proxy.crt;
ssl_certificate_key /etc/ssl/private/proxy.key;
```

Untuk domain publik, gunakan Let's Encrypt: `sudo apt install certbot python3-certbot-nginx` lalu `sudo certbot --nginx`.

**Load balancing:** beberapa server dalam satu upstream.

```nginx
upstream server_utama {
    server 192.168.1.101:80;
    server 192.168.1.102:80;
}
```

**Pembatasan laju request:**

```nginx
limit_req_zone $binary_remote_addr zone=perip:10m rate=10r/s;
# di dalam location: limit_req zone=perip burst=20;
```

**Firewall di Host 1:**

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

## 11. Ringkasan Cepat

1. Edit bagian KONFIGURASI di script.
2. `sudo ./setup-reverse-proxy.sh packages`
3. `sudo ./setup-reverse-proxy.sh bridge`
4. Buat VM1 dan VM2 dengan `bridge=br0`, install web server, atur IP statis.
5. `sudo ./setup-reverse-proxy.sh docker`
6. `sudo ./setup-reverse-proxy.sh nginx`
7. Isi file hosts di Host 2, lalu uji dengan `curl`.
