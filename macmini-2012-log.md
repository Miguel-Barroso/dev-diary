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
  - `22/tcp` from `<lan-subnet>`
  - `3389/tcp` from `<lan-subnet>` and `100.64.0.0/10`
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
* Web UI bound to `<macmini-ip>:8080`
* DNS port (53) was already taken, so initially bound AdGuard to `5353`
* Configured firewall to only allow access to port `8080` from:

  * `<lan-subnet>` (LAN)
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

  * LAN: `<lan-subnet>`
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
dig +dnssec dnssec-failed.org @<macmini-ip>
```

---

## 🚨 Router DNS Lockdown

### DNS Enforcement

* Orbi router set with `<macmini-ip>` (Mac Mini) as **only** DNS server
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
- Set <macmini-ip> as the only DNS resolver in the Orbi Router
- Confirmed DNSSEC with ```dig +dnssec sigfail.verteiltesysteme.net @<macmini-ip>```

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
host = <router-ip>

title = Engawa1 - Entrance Camera (2.4 GHz)
host = <engawa-cam-ip>

++ Toilet1
menu = Toilet1 - Cat Toilet
title = Toilet1 - Cat Toilet (2.4 GHz)
host = <toilet-cam-ip>

++ Kura1
menu = Kura1 - Kura Camera
title = Kura1 - Kura (2.4 GHz)
host = <kura-cam-ip>

++ RPi3
menu = Raspberry Pi 3
title = Raspberry Pi 3 Camera (2.4 GHz)
host = <pi3-lan-ip>
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
<macmini-ip>/24 (255.255.255.0)
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
sudo ufw allow in  on enp1s0f0 proto udp from <lan-subnet> to any port 67
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
- Two dead background loops were still running: `catcam_rtmp.service` was pulling `rtsp://<pi4-lan-ip>:554/11` (the Pi serves no RTSP → `Connection refused` in a tight restart loop), and a stray VLC was aimed at `rtsp://<foreign-subnet-ip>` (a subnet this box can't even route to).
- MJPEG at 720p30 is ~15–40 Mbps, which is why the Pi was stuck on Ethernet.

### New architecture
```
Pi 4 (C525) → ffmpeg h264_v4l2m2m (720p30, ~3–4 Mbps) → RTMP push over 5 GHz WiFi
     → rtmp://<macmini-ip>/live/catcam      (this box's nginx-RTMP)
          → OBS Media Source rtmp://localhost/live/catcam → x264 2500k → YouTube
```
The Pi hardware-encodes H.264 itself (the C525 has no onboard H.264 — only YUYV/MJPG), which drops the link to ~3 Mbps so it rides 5 GHz WiFi with no bufferbloat. nginx-RTMP decouples OBS from the WiFi: OBS reads a rock-solid `localhost` source, so brief WiFi hiccups never reach it. No screen capture, no VLC, no X dependency.

### Changes on this box
- **UFW** — nginx-RTMP was only ever used via localhost, so 1935 was LAN-blocked (the Pi's push timed out). Opened it to the LAN, scoped like the other rules:
  ```bash
  sudo ufw allow in on enp1s0f0 proto tcp from <lan-subnet> to any port 1935
  ```
- **OBS** (scene *Bob's Family Fanclub*) — showed the existing **CatCam RTMP Stream** source (`rtmp://localhost/live/catcam`), hid **Window Capture (Xcomposite)**. The *Date and Time* overlay stays on top.
- **Retired the cruft**:
  ```bash
  sudo systemctl disable --now catcam_rtmp.service   # dead RTSP watchdog
  sudo systemctl disable --now autovlc.service        # cvlc on the retired MJPEG feed
  sudo pkill -x vlc                                    # stray <foreign-subnet-ip> window
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

**Resilience gap — macmini reboot — half-closed:** nginx and AdGuard auto-start, but OBS didn't. **Applied:** `~/.config/autostart/catcam-obs.desktop` runs `flatpak run com.obsproject.Studio --startstreaming` (verified real flag in OBS 32.1.2) with a 20 s delay, so on boot (GNOME auto-login already on) OBS relaunches and resumes the YouTube stream unattended. Caveat: YouTube assigns a **new watch/embed URL per session**, so the nekocafetime.com embed still needs updating after a restart until that's solved separately (persistent-broadcast or API approach).

### 2026-06-20 — VAAPI hardware decode: ruled out (Flatpak ships only iHD)

Tested whether the OBS Media Source could hardware-decode the incoming H.264 via VAAPI — and incidentally found why the old VAAPI *encode* was unreliable too.

- The CPU (`i7-3615QM`, **Ivy Bridge / Gen7**) needs the legacy **i965** VAAPI driver. Proven working on the host: `LIBVA_DRIVER_NAME=i965 ffmpeg -hwaccel vaapi` decoded the live stream and `intel_gpu_top` showed the `VCS/0` (video-decode) engine active (~5–7 %).
- But the OBS **Flatpak's** `org.freedesktop.Platform.VAAPI.Intel` extension (24.08/25.08) ships **only `iHD`** (intel-media-driver, Gen8+). There is **no `i965_drv_video.so` inside the sandbox**, and `iHD` fails to init on this GPU (`vaInitialize failed, error 1`).
- So VAAPI (decode *or* encode) can't work in the Flatpak OBS here — the chip is capable, but the Flatpak dropped Gen7 support. Almost certainly why VAAPI encode was flaky before and x264 was the right call.

Decision: stay on **software decode + x264 software encode**; `auto-cpufreq` handles thermals. Hardware accel would need a *native* (non-Flatpak) OBS using the host i965 — not worth it for a ~5 % decode saving. Installed `intel-gpu-tools` for the test (kept).

## 2026-07-31 — key-only SSH, and the DNS rule that has to go in first

Hardening pass across the house. This box got two changes: key-only SSH, and a place in a
deny-by-default mesh policy. The second one is where all the thinking was.

### Key-only SSH, as a drop-in rather than an edit

`PasswordAuthentication no`, which governs exactly one thing: how a remote client proves who it is. It
doesn't touch the desktop auto-login, doesn't touch passwordless `sudo`, and doesn't affect this box
coming back unattended after a power cut — the appliance behaviour that makes it recover on its own
(DNS, DHCP, and the livestream encode) is untouched.

It's worth doing *because* of that setup rather than despite it. Auto-login plus NOPASSWD `sudo` means
any shell on this box is root with no further check, so sshd is the entire access control, and a
guessable password sits directly in front of it. Keys remove guessing as a category.

I put it in `/etc/ssh/sshd_config.d/` instead of editing the main file, for a reason that's worth
knowing: **sshd takes the first value it obtains, not the last**, and the `Include` line sits near the
top of `sshd_config`. So a drop-in wins over anything later in the main file, no matter what that file
says — and reverting is deleting one file instead of remembering what a line used to be.

Then `systemctl reload ssh`, not `restart` — established sessions survive a reload, so there's no
window where I'm locked out of a box I'm currently sitting on. (Worth checking whether yours is
socket-activated; this one isn't, so reloading the service is what takes effect.)

Verified from a new connection by asking the server what it accepts, rather than by reading back the
file I'd just written:

```bash
ssh -vv -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=0 <host> true
# debug1: Authentications that can continue: publickey
```

That check is the whole point — on the NAS the same test caught a second password path still open
after I thought I'd closed it. Write-up in `qnapbox66.md`.

### The DNS grant is load-bearing, and the fix lives behind the thing you break

This box is the only resolver the mesh advertises. Every phone, laptop and Pi in the house resolves
through it.

A deny-by-default policy that forgets to allow `:53` therefore takes DNS out for **everything at
once** — and the admin UI you'd use to fix it is on this same box, behind the policy you just applied.
It's a genuinely nasty failure shape: total, instant, and it disables the tool you'd reach for.

So the DNS grant is written `src: ["*"]` on purpose, wide open to every device, and commented as
load-bearing. A tighter named list would be more correct on paper and one forgotten device away from
taking the house offline. This is the one rule where being wrong isn't a device-sized problem.

(The mesh policy console refuses to save a policy whose own test assertions fail, which is a real
safety net — but only for the paths you thought to write tests for.)

### Deny-by-default's actual cost is enumeration, not syntax

The policy took several passes, and every mistake was the same mistake: a path that exists in real
life and wasn't in the file. Writing the rules is easy. Remembering what you actually use is not,
especially for a house you administer from the road, where "I'll just check the cameras from my phone"
is a path nobody ever wrote down.

Two that nearly slipped through, both about this box:

- **The phone had SSH here and nothing else.** But this is also where the ad-blocking DNS admin UI
  lives — the exact thing you want from a hotel room when the house's DNS is misbehaving. Granting a
  shell and withholding the web UI would have been precisely backwards.
- **"The cat cam is LAN, not mesh" was half true.** I'd confirmed the Pi *publishing* the stream goes
  over the LAN, which is real: the policy can't break the stream itself. Then I nearly reasoned from
  that to "so the cat cam isn't affected at all" — but *watching* it remotely comes back over the mesh
  to this box, which is a different direction entirely and was denied by the draft. Publisher and
  subscriber are not the same path, and evidence about one says nothing about the other.

The habit that fixed both: probe what's actually **listening**, then ask what each of those services
is *for*, rather than asking what rules feel sensible. `ss -tlnp` found services on this box I'd have
sworn weren't reachable from the phone, because I'd never thought about them from that direction.

### Verified afterwards, from the boxes it applies to

Applying a policy and reading "saved" is not verification. What actually convinced me:

- The public-facing web server can no longer reach the NAS's file shares, its shell, or this box's
  SSH — probed from that machine, not assumed from the rules.
- A Pi, which is granted nothing but DNS, is refused everywhere else and still resolves fine.
- This box's own grants are exactly what the file says, read back out of the running config on the
  node rather than off the screen I typed it into.
- And nothing on this box *initiates* anything over the mesh — no cron, script or live connection —
  which mattered because it's a destination in every rule and a source in none. An outbound
  dependency here would have failed silently.

## 2026-08-03 — Closing the RTMP server, and a source that was never on air

Two things on this box, both found by looking at what it's *actually* connected to rather than at
what its config files say.

### nginx-rtmp's defaults are open on both sides

The livestream ingest here is nginx-rtmp, and the block was as short as blocks get:

```nginx
application live {
    live on;
    record off;
}
```

No `allow`, no `deny`, no `on_publish` or `on_play` — and **nginx-rtmp's default is to permit both
play and publish.** So anything that could reach the port could watch the stream with no credentials,
and could publish into it too. Confirmed rather than assumed, by playing it from a different machine
on the LAN.

The fix is cheap here for one specific reason: **OBS ingests from `rtmp://localhost/live/…`**, so the
only legitimate player is loopback. That makes the tight version free —

```nginx
allow play 127.0.0.1;
deny play all;
allow publish 127.0.0.1;
allow publish <pi-lan-ip>;
deny publish all;
```

RTMP has no HTTP-Basic equivalent, so IP allow/deny is the proportionate control *because* the
consumer is loopback. If the players were spread around the house this would be the wrong tool.

Three things I'd have got wrong without checking:

- **This needs `restart`, not `reload`.** nginx-rtmp keeps stream state **per worker**, and this box
  runs `worker_processes 1`. On a reload the old worker keeps the publisher and its existing players
  while new connections land on a fresh worker that has no stream — so it looks completely fine, and
  then hands you a black screen at the next reconnect, unattended, hours later. A restart converges
  it in one event. The `open socket left … aborting` lines in `error.log` afterwards are the old
  worker draining, not a fault.
- **Test a publish ACL with a different stream name.** I used a throwaway name, which is the only
  reason the publish side was testable at all — a decoy can't collide with the live stream even if
  the ACL turns out to be broken. (An earlier pass skipped testing publish entirely to avoid racing
  the live feed, which is how it stayed untested.)
- **`allow play 127.0.0.1` is only safe while the listener is IPv4-only.** It is here (`0.0.0.0:1935`).
  Add an IPv6 listener later and OBS resolving `localhost` to `::1` gets *denied* by your own rule.
  `allow play ::1;` would need to go in at the same time.

Verified after: LAN playback fails, unauthorised publish gets a broken pipe, OBS still plays and the
Pi still publishes. OBS kept its PID across the whole thing; the publisher was back in under 8 s and
the media source re-attached itself in about 20.

### A source pointing at nothing, and how not to diagnose it

Separately, an OBS scene had a source pointing at an RTSP URL on an address with no listener on 554,
which looked alarming until I checked what it was.

It's a **hidden, non-rendering, non-ingesting orphan** — `visible: false`, and the running OBS
process has no connection to `:554` anywhere. The address belongs to a Pi's *wired* interface, which
is down on purpose because that camera was deliberately moved to WiFi; and the house's two actual
RTSP cameras are a different vendor entirely, on their own addresses. The path in the URL is right
for that camera family, so the source was probably typed for one of them and never corrected. It
costs nothing and it's staying.

What settled it wasn't the address. It was two things: the scene collection's `visible` flags, and
`lsof` on the live OBS process — what it's **actually connected to**. I'd started down the path of
treating the address as evidence about the livestream, which it never was.

**And don't fix an OBS source by editing the scene JSON.** OBS holds the collection in memory and
writes it out on exit, so a file edit gets silently clobbered the next time it closes cleanly. The
proof it never autosaves was right there: the file's mtime was over a year older than the running
process. The durable routes are the UI while it's running, or editing the file with OBS stopped —
and obs-websocket isn't installed here, so there was no scripted third option.

### Where AdGuard actually keeps DHCP reservations

Worth knowing before you go looking, because it cost me a detour. `dhcp.dhcpv4.static_leases` in
`AdGuardHome.yaml` is **empty**, and the dynamic pool is a narrow range at the top of the subnet — so
every pinned address in the house looks unmanaged if you read the config file. The reservations are
the **expiry-less entries in `work/data/leases.json`**. Nothing is statically configured on the hosts
themselves; they're all DHCP clients.