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

---

# 🧾 System Hardening Log — May 17, 2025

**Machine:** Mac Mini 2012  
**OS:** Pop!\_OS 22.04  
**Role:** Cat Café Livestream Host, AdGuard DNS Server  

---

## 🔧 Issues Observed

- System entered unintended sleep, causing DNS and stream outage.
- OBS using x264 software encoding, overloading CPU.
- `io.elementary.appcenter` (Pop!_Shop) consuming 100% CPU for no reason.
- Remote Desktop sessions were laggy and unstable.
- Load average spiking above 19 with poor responsiveness.

---

## ✅ Actions Taken

### 🛑 Disabled Sleep
```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'nothing'
```

---

### 🎥 Optimized OBS for VAAPI Hardware Encoding
- Confirmed H.264 VAAPI support via `vainfo`
- Launched OBS with:
```bash
LIBVA_DRIVER_NAME=i965 obs
```
- Set encoder: `FFMPEG VAAPI`
- Set bitrate: `2500 Kbps`
- Disabled preview in OBS to reduce GPU load

---

### 🧼 Removed Unnecessary Software (Pop!_Shop)
```bash
sudo apt remove pop-shop
sudo apt autoremove
```
Confirmed `io.elementary.appcenter` binary is gone.

---

### 📉 Outcome

| Component | Status |
|----------|--------|
| Sleep | ✅ Disabled |
| OBS | ✅ Hardware-accelerated (VAAPI) |
| System load | ✅ Normalized (avg ~1.9) |
| AppCenter | ✅ Removed |
| DNS + Stream | ✅ Stable and responsive |
| RDP / GUI Lag | ✅ Resolved |

---

**System is now clean, lean, and stable for 24/7 cat café streaming.**

🐱📡🧠  

## 2025-07-25 – AdGuard + SmokePing Update

### 🔧 AdGuard DNS Configuration
- Updated upstream DNS resolver to use **Cloudflare over HTTPS**:  
  `https://cloudflare-dns.com/dns-query`
- Set **bootstrap DNS** to `1.1.1.1` for reliable resolution of the DoH hostname.
- This ensures encrypted DNS lookups with minimal external dependencies and avoids plaintext DNS leaks.
- Saved a copy of the updated `AdGuardHome.yaml` to the home directory for backup and version control.
- Set 192.168.1.19 as the only DNS resolver in the Orbi Router
- Confirmed DNSSEC with ```dig +dnssec sigfail.verteiltesysteme.net @192.168.1.19```

### 📡 SmokePing Monitoring Expansion
- Expanded monitoring targets to include local infrastructure:
  - Internet Connectivity
  - IP cameras
  - Orbi router and satellites
  - QNAP NAS and other key devices
  Using ```sudo nano /etc/smokeping/config.d/Targets```
- This helps visualize latency and availability across the home network, especially for critical nodes like the surveillance system and storage.
- Added pretty host labels for better readability in the web UI. 
- Added specific meta tag for UTF-8 in the html template (may be overwritten during an update)
- Saved Targets file backup to home folder

NB1: You can check the configuration either using ```systemctl status smokeping``` or ```smokeping --check```

NB2: The Targets file need variable declarations ontop and an example is as follows:
```
*** Targets ***

probe = FPing
menu = Top
title = Smoke on the LAN

+ MeshNetwork
menu = Orbi Mesh
title = Orbi Mesh Network Devices

++ RBR50
menu = RBR50 Router
title = RBR50 - Main Router (Ethernet, near MacMini)
host = 192.168.1.1

title = Engawa1 - Entrance Camera (2.4 GHz)
host = 192.168.1.35

++ Toilet1
menu = Toilet1 - Cat Toilet
title = Toilet1 - Cat Toilet (2.4 GHz)
host = 192.168.1.34

++ Kura1
menu = Kura1 - Kura Camera
title = Kura1 - Kura (2.4 GHz)
host = 192.168.1.26

++ RPi3
menu = Raspberry Pi 3
title = Raspberry Pi 3 Camera (2.4 GHz)
host = 192.168.1.50
```

## 2025-07-30 – AdGuard as DHCP Server Update

Background:
Needed to serve DHCP via AdGuard Home to map which clients generate which DNS requests—and use that insight to refine the block/allow lists.

Steps Taken
	1.	Enable DHCP in AdGuard Home
Edited conf/AdGuardHome.yaml:
```dhcp:
  enabled: true
  interface_name: enp1s0f0
  ```
2.	Assign Static IP to Mac mini
Configured enp1s0f0 in Pop!_OS to:
```
192.168.1.19/24 (255.255.255.0)
```
3.	Point System DNS Locally
In Pop!_OS network settings, set DNS to:
```
127.0.0.1   # AdGuard Home
1.1.1.1     # fallback
```
4.	Run AdGuard in Docker with Host Networking
In docker-compose.yml (or via docker run):
```
network_mode: host
cap_add:
  - NET_ADMIN
  - NET_RAW
```
This allows the container to bind to UDP/67 for DHCP.

5.	Unblock DHCP in the Firewall

UFW rules (scoped to enp1s0f0):
  ```
sudo ufw allow in  on enp1s0f0 proto udp from 192.168.1.0/24 to any port 67
sudo ufw allow in  on enp1s0f0 proto udp to any port 68
sudo ufw allow out on enp1s0f0 proto udp from any to any port 67
sudo ufw allow out on enp1s0f0 proto udp from any to any port 68
sudo ufw reload
  ```

Raw iptable rules:

  ```
sudo iptables -I INPUT  -p udp --dport 67 -j ACCEPT
sudo iptables -I OUTPUT -p udp --sport 67 -j ACCEPT
  ```
UFW “before” rules (to let broadcast DHCP packets bypass filters):
  ```
*filter
# Allow DHCP DISCOVER / REQUEST
-A ufw-before-input  -p udp --sport 68 --dport 67 -j ACCEPT
# Allow DHCP OFFER / ACK
-A ufw-before-output -p udp --sport 67 --dport 68 -j ACCEPT
  ```

6.	Install Docker Compose
  
  ```
sudo apt update
sudo apt install docker-compose-plugin
  ```
7.	Declare AdGuard in docker-compose.yml
Created /opt/adguardhome/docker-compose.yml:
```
services:
  adguardhome:
    image: adguard/adguardhome:latest
    container_name: adguardhome
    restart: unless-stopped
    network_mode: host
    cap_add:
      - NET_ADMIN
      - NET_RAW
    volumes:
      - ./conf:/opt/adguardhome/conf
      - ./work:/opt/adguardhome/work
    command:
      - --no-check-update
      - -c
      - /opt/adguardhome/conf/AdGuardHome.yaml
      - -w
      - /opt/adguardhome/work
```
Brought it up with:
```
docker compose up -d
```
Result:
Mac mini now reliably serves DHCP via AdGuard Home in Docker, with all firewall rules correctly in place and service managed declaratively through Docker Compose.

## 2025-07-30 – CatCam1 Live Stream Update

**Background**  
Stream was struggling to keep up and YouTube sometimes disconnected due to too little data.

### Changes Applied

1. **Switched Encoder**  
   - Moved from VAAPI to software x264 for greater reliability.

2. **Optimized x264 Settings**  
   - **Keyframe Interval:** 2 seconds (keyint=60)  
   - **Resolution:** 1280 × 720 (no rescaling)  
   - **Frame Rate:** 30 fps  
   - **Video Bitrate:** CBR 2 500 kbps  
   - **Preset & Profile:** veryfast preset, main profile  
   - **Additional Flags:** `tune=zerolatency`  
   - **Audio:** Disabled all audio devices
3. **Reduce Local Load**  
   - Disabled OBS preview window  
   - Closed all unnecessary applications (browsers, background tasks)

### Result

- **Dropped frames** reduced from ~21 % to **< 1 %**  
- Stream stability restored; no further YouTube disconnects observed  

---

## 2026-06-20 — CatCam: Pi 4 H.264-over-WiFi → RTMP, retiring the VLC-window capture

### Background
The cat-café feed (Pi 4 + Logitech C525) was served as **MJPEG** over HTTP by `mjpg-streamer` on the Pi, played in a headless VLC window here, and pulled into OBS via **XComposite Window Capture** (see `rbpi4-catcam.md`). It worked, but it was a pile of workarounds:

- OBS can't ingest the raw MJPEG Media Source without silently stalling — hence the screen-capture hack.
- `autovlc.sh` had drifted to `--run-time=30 … vlc://quit`, so the captured VLC window relaunched every ~35 s — a periodic black-frame hiccup baked into the broadcast.
- Two dead background loops were still running: `catcam_rtmp.service` was pulling `rtsp://192.168.1.41:554/11` (the Pi serves no RTSP → `Connection refused` in a tight restart loop), and a stray VLC was aimed at `rtsp://192.168.68.104` (a subnet this box can't even route to).
- MJPEG at 720p30 is ~15–40 Mbps, which is why the Pi was stuck on Ethernet.

### New architecture
```
Pi 4 (C525) → ffmpeg h264_v4l2m2m (720p30, ~3–4 Mbps) → RTMP push over 5 GHz WiFi
     → rtmp://192.168.1.19/live/catcam      (this box's nginx-RTMP)
          → OBS Media Source rtmp://localhost/live/catcam → x264 2500k → YouTube
```
The Pi hardware-encodes H.264 itself (the C525 has no onboard H.264 — only YUYV/MJPG), which drops the link to ~3 Mbps so it rides 5 GHz WiFi with no bufferbloat. nginx-RTMP decouples OBS from the WiFi: OBS reads a rock-solid `localhost` source, so brief WiFi hiccups never reach it. No screen capture, no VLC, no X dependency.

### Changes on this box
- **UFW** — nginx-RTMP was only ever used via localhost, so 1935 was LAN-blocked (the Pi's push timed out). Opened it to the LAN, scoped like the other rules:
  ```bash
  sudo ufw allow in on enp1s0f0 proto tcp from 192.168.1.0/24 to any port 1935
  ```
- **OBS** (scene *Bob's Family Fanclub*) — showed the existing **CatCam RTMP Stream** source (`rtmp://localhost/live/catcam`), hid **Window Capture (Xcomposite)**. The *Date and Time* overlay stays on top.
- **Retired the cruft**:
  ```bash
  sudo systemctl disable --now catcam_rtmp.service   # dead RTSP watchdog
  sudo systemctl disable --now autovlc.service        # cvlc on the retired MJPEG feed
  sudo pkill -x vlc                                    # stray 192.168.68.104 window
  ```

### Gotcha — OBS source stuck black
The `CatCam RTMP Stream` Media Source has `reconnect_delay_sec` unset and had been failing to open since long before the new publisher existed. When the live stream finally appeared it stayed **black** (socket connected, no playback). This OBS build has no *Restart* item in the source right-click menu; **toggling the source's eye icon off→on** forced a clean re-open and the cats came back. **TODO:** set a Reconnect Delay in the source Properties so it self-heals after a Pi reboot.

### Result
- OBS ingests a clean H.264 720p30 source — no screen capture, lower CPU.
- Pi 4 streams over 5 GHz WiFi → free to relocate.
- All stale/failing loops gone; only the Pi → RTMP → OBS path remains.

### 2026-06-20 (later) — resilience hardening + reboot test

Audited the whole chain for stability before calling it done.

- **`worker_processes auto` was the real flakiness.** nginx-rtmp keeps published streams **per worker**; with `auto` (10 workers here) the publisher lives on one worker and any subscriber that connects to a *different* worker sees **no stream**. That's what made the OBS CatCam source "stick black" and need reconnect roulette. Fixed with **`worker_processes 1;`** (this box's nginx only does RTMP + SmokePing) + `systemctl restart nginx`. Publisher and OBS now always share the one worker. *(`gop_cache on` is **not** supported by Ubuntu's arut `libnginx-mod-rtmp` — only the http-flv fork has it; that attempt was reverted. Backup: `nginx.conf.bak-2026-06-20`.)*
- **OBS CatCam source** (set via GUI): network buffering 4 MB, Reconnect Delay 10 s, "Restart playback when source becomes active" on, "Show nothing when playback ends" on. Hardware decode left **off** — 720p30 H.264 software decode is ~5 % CPU and dodges the flaky i965 VAAPI path; the heat is in the x264 *output* encode, not decode.
- **Reboot test — passed.** Rebooted the Pi 4: WiFi auto-rejoined 5 GHz ch36, powersave off, pinned route re-applied, `catcam-rtmp` auto-started and pushed, nginx received it, and **OBS reconnected unattended** — cats back in ~90 s with no manual step.
- **Thermals re-checked.** `auto-cpufreq` (+ `thermald`) is actively gating turbo — caught it dropping cores 3.1 → 2.3 GHz when the package hit ~88 °C, pulling it back from a brief 99 °C turbo peak. Total CPU load only ~18 %, so heat is dissipation-bound, not compute-bound, and turbo gating is the right lever. Sits at the ~87 °C "high" line but ~18 °C under the 105 °C critical; stable. De-dust/repaste would add summer headroom but isn't urgent.

**Open resilience gap — macmini reboot:** nginx and AdGuard auto-start, but **OBS does not** (no `~/.config/autostart` entry, launched manually as `obs`, no auto-start-streaming). A macmini reboot leaves the YouTube stream down until OBS is started by hand. Fix: a `~/.config/autostart` `.desktop` running `flatpak run com.obsproject.Studio --startstreaming` (GNOME auto-login is already enabled). **Not yet applied** — pending decision.