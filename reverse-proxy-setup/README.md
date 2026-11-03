# Tugas Reverse Proxy – Setup Lengkap

## 1. Topologi

```
                    Host 2 (klien: browser / curl)
                              |
   =====================  Ethernet Bridge (satu subnet) =====================
        |                     |                    |                |
   Windows (host)      VM1 (Server Utama)     VM2 (Server X)   Docker (Server 2)
   + Docker Desktop    NGINX REVERSE PROXY    Nginx backend    Nginx container
   192.168.1.100       192.168.1.101          192.168.1.102    di Windows, port 8083
```

Windows berada di jaringan bridge yang sama. Dalam setup ini Windows menjalankan Docker,
jadi **IP Docker = IP Windows** (cek dengan `ipconfig`). Windows juga bisa dipakai
sebagai klien penguji, sama seperti Host 2.

Alur: Host 2 -> `http://192.168.1.101/` (VM1) -> VM1 meneruskan request sesuai path:

| URL di VM1            | Diteruskan ke                  | Server        |
|-----------------------|--------------------------------|---------------|
| `/`                   | dilayani sendiri oleh VM1      | Server Utama  |
| `/x/`                 | `http://192.168.1.102:80`      | Server X (VM2)|
| `/server2/`           | `http://192.168.1.100:8083`    | Server 2 (Docker) |

> **Sesuaikan IP.** Semua IP di atas adalah contoh untuk subnet `192.168.1.0/24`.
> Cek subnet jaringan Anda (`ip a` / `ipconfig`) lalu ganti di variabel bagian atas
> `vm1/setup-vm1.sh` serta file `netplan-*.yaml`.

## 2. Struktur file

```
reverse-proxy-lab/
├── README.md
├── vm1/
│   ├── setup-vm1.sh          # install nginx + pasang konfigurasi
│   ├── reverse-proxy.conf    # konfigurasi reverse proxy
│   ├── index.html            # halaman Server Utama
│   └── netplan-vm1.yaml      # IP statis VM1
├── vm2/
│   ├── setup-vm2.sh          # install nginx backend
│   ├── index.html            # halaman Server X
│   └── netplan-vm2.yaml      # IP statis VM2
└── docker/
    ├── docker-compose.yml    # container Server 2
    └── html/index.html       # halaman Server 2
```

## 3. Langkah-langkah

### Langkah 0 – Siapkan bridge (Ethernet Bridge)
Tujuannya: VM mendapat IP di subnet yang sama dengan host dan Host 2.

**VirtualBox:** Settings VM -> Network -> Adapter 1 -> *Attached to:* **Bridged Adapter** -> pilih
kartu jaringan fisik (Ethernet/Wi-Fi). Lakukan untuk VM1 dan VM2.

**VMware:** VM Settings -> Network Adapter -> **Bridged**.

**KVM/libvirt (Linux host, Ethernet):** buat bridge `br0`:
```bash
sudo nmcli con add type bridge ifname br0 con-name br0
sudo nmcli con add type bridge-slave ifname enp3s0 master br0   # ganti enp3s0 dengan NIC Anda
sudo nmcli con up br0
```
Lalu pada VM pilih *Network source: Bridge device br0*.

> Catatan: bridge lewat Wi-Fi sering tidak berfungsi di Linux/KVM. Pakai kabel Ethernet,
> atau pada VirtualBox/VMware (Windows) bridged Wi-Fi umumnya tetap bisa.

### Langkah 1 – Buat 2 VM (Ubuntu Server 22.04/24.04)
VM1 dan VM2, masing-masing RAM 1 GB, disk 10 GB, adapter **bridged**.

### Langkah 2 – Setup VM2 (Server X / backend)
```bash
# salin folder vm2/ ke VM2 (scp, shared folder, atau flashdisk), lalu:
cd vm2
sudo bash setup-vm2.sh
```
Tes dari VM2: `curl http://localhost` -> tampil "Server X (VM2)".

### Langkah 3 – Setup Docker (Server 2) di Windows
Pasang Docker Desktop di Windows, lalu buka PowerShell di folder `docker`:
```bash
cd docker
docker compose up -d
curl http://localhost:8083     # -> "Server 2 (Docker)"
```
Izinkan port 8083 di Windows Firewall (PowerShell sebagai Administrator):
```powershell
New-NetFirewallRule -DisplayName "Docker Server2" -Direction Inbound -Protocol TCP -LocalPort 8083 -Action Allow
```
Cek IP Windows dengan `ipconfig`, lalu isi `DOCKER_IP` di `vm1/setup-vm1.sh` dengan IP itu.
(Jika Docker dijalankan di Linux: `sudo ufw allow 8083/tcp`.)

### Langkah 4 – Setup VM1 (Reverse Proxy / Server Utama)
Edit variabel IP di atas `setup-vm1.sh` (VM2_IP, DOCKER_IP, DOCKER_PORT), lalu:
```bash
cd vm1
sudo bash setup-vm1.sh
```
Skrip memasang Nginx, menaruh `index.html`, memasang `reverse-proxy.conf`, mengetes
konfigurasi, dan me-restart Nginx.

### Langkah 5 – (Opsional) IP statis
```bash
sudo cp netplan-vmX.yaml /etc/netplan/01-static.yaml
sudo chmod 600 /etc/netplan/01-static.yaml
sudo netplan apply
```
Ganti nama interface (`enp0s3`) sesuai hasil `ip a`, serta gateway sesuai router Anda.

### Langkah 6 – Pengujian dari Host 2
```bash
curl http://192.168.1.101/            # Server Utama (VM1)
curl http://192.168.1.101/x/          # Server X (VM2) lewat proxy
curl http://192.168.1.101/server2/    # Server 2 (Docker) lewat proxy
curl -I http://192.168.1.101/x/       # lihat header X-Proxy
```
Atau buka di browser. Ambil **screenshot** ketiganya untuk laporan.

### Langkah 7 – Bukti reverse proxy bekerja
Di VM2: `sudo tail -f /var/log/nginx/access.log`, lalu akses `/x/` dari Host 2.
IP sumber yang tercatat adalah **IP VM1**, bukan IP Host 2. Itu bukti request datang lewat proxy.
(Header `X-Real-IP` / `X-Forwarded-For` membawa IP asli klien.)

## 4. Troubleshooting

| Masalah | Solusi |
|---|---|
| `502 Bad Gateway` | Backend mati / IP salah. Tes `curl http://IP_BACKEND` dari VM1. |
| Timeout ke Docker | Windows Firewall blok port 8083, atau `DOCKER_IP` bukan IP Windows; cek `docker ps`. |
| VM tidak dapat IP subnet yang sama | Adapter belum *bridged* / NIC yang dipilih salah. |
| `nginx -t` gagal | Periksa titik koma dan IP di `reverse-proxy.conf`. |

## 5. Checklist laporan
- [ ] Gambar topologi (diagram tulis tangan Anda)
- [ ] Screenshot `ip a` tiap VM (bukti satu subnet)
- [ ] Screenshot `docker ps`
- [ ] Screenshot `nginx -t` di VM1
- [ ] Screenshot akses dari Host 2 ke 3 URL
- [ ] Screenshot access.log VM2 (bukti IP sumber = VM1)
