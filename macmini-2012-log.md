# Mac Mini 2012 Live Stream System Log

## 📅 2025-04-27

### 🧼 Maintenance
- De-dusted and wiped clean the machine.
- Confirmed all 4 USB ports work.
- Backed up and archived old configs for OBS and camera switching scripts.

### ⚙️ System Upgrade
- Updated system to Pop!_OS 22.04 LTS (from 20.04).
- Installed missing WiFi driver (as fallback).
- Installed Tailscale for remote access.

### 🎥 OBS Studio
- Imported OBS scenes from Astromeda PC.
- Set video source to Rec.709, Limited, no buffering.
- Set encoder profile to high (everything else default).

### 🖥️ Remote Desktop
- Configured GNOME Desktop Sharing (Settings → Sharing).
- VNC is deprecated in favor of RDP.
- Set up headless login (auto-login enabled via GNOME).
- Set user password to blank and removed login keyring lock (via Seahorse).

⚠️ **Note:** RDP password must still be set in GNOME Remote Desktop settings.

### 🔐 Remote Access
- Added SSH public keys for Termux (Nothing Phone 2) and Astromeda PC.
- Verified key-based login works.
- Left password login disabled.

### 🔒 Firewall
- UFW set to default deny.
- Allowed:
  - `22/tcp` from `192.168.0.0/24`
  - `3389/tcp` from `192.168.0.0/24` and `100.64.0.0/10`
- Removed overly permissive rules.
- System remains headless with secure RDP and SSH.

---

## 🛠️ 2025-05-07 — Solving Cat Camera Feed Freeze

### Problem
OBS Media Source stalls on low-end RTSP IP cam.

### Solution
- Created `watchdog_catcam_rtmp.sh`
- Streams RTSP feed to local RTMP server (via FFmpeg).
- Auto-restarts on:
  - RTSP 5XX errors
  - Frame=0 (stalls)

### Deployment
- Managed via `systemd`:
  - Script: `~/watchdog_catcam_rtmp.sh`
  - Service: `/etc/systemd/system/catcam_rtmp.service`
- Log file: `~/catcam_rtmp.log`

### Log Rotation
```bash
@daily bash -c 'LOG="/home/macmini2012/catcam_rtmp.log"; [ -f "$LOG" ] && [ $(stat -c%s "$LOG") -gt $((50 * 1024 * 1024)) ] && tail -c $((1 * 1024 * 1024)) "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"'

## 📅 2025-05-09 — AdGuard Home Setup

### Docker Installation

* Added Docker GPG key and repository
* Installed `docker-ce`, `docker-ce-cli`, and `containerd.io`

### Installed Unbound

* Local recursive DNS resolver to eliminate upstream logging and improve privacy and cache efficiency

### AdGuard Home Setup

* Pulled and ran AdGuard Home in Docker
* Switched to `--network host` for simplicity and stability
* Web UI bound to `192.168.1.19:8080`
* DNS port (53) was already taken, so initially bound AdGuard to `5353`
* Configured firewall to only allow access to port `8080` from:

  * `192.168.1.0/24` (LAN)
  * `100.64.0.0/10` (Tailscale)
* Changed ownership and permissions to fix permission warnings:

```bash
sudo chown -R $USER:$USER /opt/adguardhome
chmod 700 /opt/adguardhome/work
```

---

## 📝 Log Entry: Unbound on Port 5353

### Purpose

Set up a local recursive resolver to forward all requests securely to the root servers.

### Config

```bash
sudo mkdir -p /opt/unbound
sudo nano /opt/unbound/unbound.conf
```

```conf
server:
  verbosity: 1
  interface: 0.0.0.0
  port: 5353
  do-ip4: yes
  do-udp: yes
  access-control: 127.0.0.0/8 allow
```

### Docker Run

```bash
docker run -d \
  --name unbound \
  --network host \
  --health-cmd='exit 0' \
  -v /opt/unbound/unbound.conf:/etc/unbound/unbound.conf:ro \
  --restart unless-stopped \
  mvance/unbound \
  unbound -v -d -c /etc/unbound/unbound.conf
```

### Verified with

```bash
dig @127.0.0.1 -p 5353 www.google.com
```

### UFW Rules

```bash
sudo ufw allow in on lo to any port 5353 proto tcp
sudo ufw allow in on lo to any port 5353 proto udp
```

---

## 🔒 Hardened AdGuard Home DNS (No Unbound)

### Removed Unbound

* `docker rm -f unbound`
* Deleted `/opt/unbound`
* Removed UFW rules for port 5353

### Took Over Port 53

* Disabled systemd-resolved:

```bash
sudo systemctl disable --now systemd-resolved
```

* Overwrote `/etc/resolv.conf` with:

```bash
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
sudo chattr +i /etc/resolv.conf
```

### Restarted AdGuard

* Edited `AdGuardHome.yaml` to bind to port `53`
* Docker container uses `--network host`
* Restarted the container

### UFW Rules

* Allowed port 53 from:

  * LAN: `192.168.1.0/24`
  * Tailscale: `100.64.0.0/10`

### Upstream Configuration in AdGuard

* DNS-over-HTTPS:

  * `https://dns10.quad9.net/dns-query`
  * `https://dns.google/dns-query`
  * `https://1.1.1.1/dns-query`
* Bootstrap DNS:

  * `9.9.9.9`, `149.112.112.112`, `1.1.1.1`, `8.8.8.8`

### DNSSEC

* Enabled in AdGuard Home
* Verified via:

```bash
dig +dnssec dnssec-failed.org @192.168.1.19
```

---

## 🚨 Router DNS Lockdown

### DNS Enforcement

* Orbi router set with `192.168.1.19` (Mac Mini) as **only** DNS server
* All other clients blocked from upstream DNS via router firewall (port 53)
* Ensures clients can't bypass AdGuard
* Verified with `nslookup google.com 8.8.8.8` → timeout on clients, works on Mac Mini

---

## 🚀 Tailscale-Wide DNS

### Global DNS

* Mac Mini’s Tailscale IP set as Global DNS in Tailscale admin
* `Override Local DNS` toggle enabled
* Magic DNS enabled
* Android device without private DNS can now resolve DNS via AdGuard even on mobile network

---

## 🔐 Final Setup Snapshot

| Component         | Status                    |
| ----------------- | ------------------------- |
| AdGuard Home      | Bound to port 53, works   |
| DNSSEC            | Enabled, enforced         |
| DoH Upstreams     | Quad9, Google, Cloudflare |
| Unbound           | Removed                   |
| Local DNS (LAN)   | Routed through AdGuard    |
| DNS via Tailscale | Also routed to AdGuard    |
| Router DNS        | Locked to Mac Mini        |
| Firewall Rules    | Clean, verified with UFW  |
| Log Visibility    | Full query log on AdGuard |
| Blocklists        | Region-specific for Japan |

