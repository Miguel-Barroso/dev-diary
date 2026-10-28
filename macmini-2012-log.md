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
- Removed the login keyring prompt (via Seahorse) so an unattended login doesn't stall.

⚠️ **Note:** RDP uses its own credentials, set in GNOME Remote Desktop settings.

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
@daily bash -c 'LOG="/home/<local-user>/catcam_rtmp.log"; [ -f "$LOG" ] && [ $(stat -c%s "$LOG") -gt $((50 * 1024 * 1024)) ] && tail -c $((1 * 1024 * 1024)) "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"'

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
doesn't touch the desktop session or local accounts, and doesn't affect this box
coming back unattended after a power cut — the appliance behaviour that makes it recover on its own
(DNS, DHCP, and the livestream encode) is untouched.

It's worth doing *because* this is an unattended appliance rather than despite it: nobody is watching
its auth log, and a password is something that can be guessed. Keys remove guessing as a category.

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

## 2026-08-21 — SmokePing's alert had nowhere to send mail, and postfix had been dead for weeks without anyone noticing

Chasing the Pi 3's ping flapping (`rbpi3-log.md`) led to actually reading the SmokePing config that was
supposed to be alerting on it — which turned out to have never been finished.

### The config was still the Debian package's example

`config.d/General` had `owner = Peter Random`, `contact = some@address.nowhere`,
`mailhost = my.mail.host`, `cgiurl = http://some.url/smokeping.cgi` — the literal placeholder values the
package ships with, never touched. `cgiurl` was easy to fix for real: this box serves the CGI through
nginx on `:8081`, so it's now `http://<macmini-ip>:8081/smokeping.cgi`.

The one alert rule, `someloss`, had a pattern that didn't match its own comment:

```
pattern = >0%,*12*,>0%,*12*,>0%
comment = loss 3 times in a row
```

`*12*` means 12 wildcard steps — at this box's 300 s polling interval, that's loss, then roughly an
hour of anything, then loss again, then another hour, then loss a third time. That's "loss recurring
across a couple of hours," not "three in a row," and it's also the stock example pattern straight out
of SmokePing's own docs, left in place with the comment carried over unchanged. Changed it to
`>0%,>0%,>0%` — three consecutive polling steps, 15 minutes, which would actually have caught the Pi
flapping earlier today. Also found `config.d/Targets.old`, a pre-rename copy of the targets file that
isn't `@include`d anywhere — dead, not dangerous, archived off the box rather than deleted outright.

### Wiring up real delivery surfaced something worse

Fixing the placeholders was step one; step two was making the alert mail actually send, through
Resend's transactional SMTP relay. Postfix was already installed on this box — just never enabled — so
the plan was to configure it as a relay-only satellite instead of adding new software: SASL auth to
`smtp.resend.com:465`, `smtp_tls_wrappermode` on since 465 is implicit TLS rather than STARTTLS, and
`inet_interfaces = loopback-only` so it never listens on the LAN. `libsasl2-modules` had to be installed
separately — the `-db` variant already on the box doesn't carry the PLAIN mechanism Resend needs.

`postmap` refused with `fatal: bad string length 0 < 1: setgid_group =`, which had nothing to do with
anything I'd just written. `main.cf` had **eight** required parameters sitting blank:

```
setgid_group, sendmail_path, newaliases_path, mailq_path,
html_directory, manpage_directory, sample_directory, readme_directory
```

`mail.log` had been recording the fallout every single day since at least Aug 16 —
`fatal: open /etc/postfix/main.cf: No such file or directory`, then the same blank-parameter fatals
once the file reappeared — off this box's own daily cron mail, with nothing surfacing it because
nothing was reading that log. Restored all eight to Postfix's own compiled-in defaults
(`postconf -d <param>` for each), and `postfix check` went from silent-but-broken to clean:

```bash
sudo postconf -e 'setgid_group = postdrop' 'sendmail_path = /usr/sbin/sendmail' \
  'newaliases_path = /usr/bin/newaliases' 'mailq_path = /usr/bin/mailq' \
  'html_directory = /usr/share/doc/postfix/html' 'manpage_directory = /usr/share/man' \
  'sample_directory = /etc/postfix' 'readme_directory = /usr/share/doc/postfix'
```

### The gotcha: the relay checks the envelope, not the header

First test bounced from Resend with ``550 Invalid `from` field``, which looked like an auth problem and
wasn't. I'd sent it as root without `-f`, and Postfix's `sendmail` derives the envelope sender from the
invoking Unix account whenever `-f` is absent — the `From:` header in the message body is cosmetic, not
what the relay checks. Root with no `-f` becomes `root@macmini`, which isn't a domain Resend will
accept mail from. Confirmed the same thing running as the actual `smokeping` service account: no `-f`,
same bounce shape, `smokeping@macmini` this time. What kept this from being a second real bug: SmokePing's
own alert code (`Smokeping.pm`) already calls `sendmail -f $from`, using the Alerts `from` address
explicitly — so the live alert path was never going to hit this. Worth knowing anyway for anything else
on this box that shells out to `sendmail` without thinking about the envelope.

Verified with `-f` set correctly, run as the `smokeping` user: `status=sent`, with a Resend message ID
back in `mail.log`. Postfix is enabled, not just started, so this survives a reboot — and loss alerts
now have somewhere real to go.

## 2026-08-23 — Two days spent monitoring an address I'd retired, and the cron mail that bounced in silence

Started as "why does SmokePing say the Pi 3 is dead when it is plainly streaming". Nothing to do with
the Pi 3 (`rbpi3-log.md`); all of it lives on this box.

### Editing the config is not what makes SmokePing read it

`config.d/Targets` said `host = <pi3-eth-ip>`, eth0's MAC in the remark. `fping` from this box to that
address: 0% loss, 1.78 ms avg. Config correct, network correct, graph flat dead.

The daemon had last started **2026-08-21 18:23:59**. `Targets` had an mtime of **2026-08-23 14:03**.
SmokePing parses its config once, at startup, and I had edited the file without telling it.

Rather than guess what it held, I read it off the running process. The `FPing` probe batches every
target into one `fping` per cycle, so the argument list *is* the loaded config:

```bash
pgrep -x -a fping    # caught mid-poll — targets are argv
```

It listed `.50`, the Pi's wlan0 address that I had soft-blocked earlier the same day, and no `.51`
anywhere. A `tcpdump` across one full 300 s cycle agreed: 20 echo requests per target, `.51` not among
them. SmokePing was faithfully monitoring an interface I had deliberately retired, and correctly
reporting it dead.

`systemctl reload smokeping` fixed it in one command. What kept it invisible for two days is that
`ActiveEnterTimestamp` only moves on *restart* — after a SIGHUP it still read Aug 21, so a reloaded
daemon and one running two-day-old config are indistinguishable from `systemctl status`. Nothing in the
stack warns that the config on disk is newer than the process. `smokeping --check` validates the file,
not what's in memory, so it would have passed happily throughout.

### The RRD does not remember which address produced which sample

`IPCameras/RPi3.rrd` has accumulated since 2025-07-25 as one continuous series. Changing `host =` does
not start a new one. That graph now splices `.51` data onto two days of `.50` data onto whatever
preceded it, under a title reading "(Ethernet)" for the entire period it was measuring WiFi. Nothing in
the file records the change. The title describes intent; the RRD describes whatever was in argv that
week. Worth knowing before reading any history off it.

### The camera that looked like it was on WiFi

Same shape, different box: `kura1` (a DCS-932L) had moved from WiFi to Ethernet, the Orbi wouldn't list
it, and pinging it *felt* like WiFi while SmokePing showed wired latency.

SmokePing was right. Measured from this box, 40 samples each, in ms:

| target | avg | max | sd | reading |
|---|---|---|---|---|
| QNAP, wired | 0.26 | 0.33 | 0.03 | wired reference |
| `kura1` | **1.10** | **1.98** | **0.17** | **wired** |
| mesh satellite | 2.59 | 4.72 | 0.64 | wireless backhaul |
| `engawa1`, 2.4 GHz | 12.26 | 48.10 | 8.88 | WiFi reference |

Standard deviation is the discriminator, not the average. sd 0.17 is not a radio; `engawa1` at sd 8.88
plainly is. `kura1` also beats the satellites themselves, so it isn't sitting behind a wireless
backhaul either. An `nmap -sn` sweep of the whole `/24` found exactly one D-Link on the network,
matching its single AdGuard reservation — no second interface anywhere, unlike the Pis, which each hold
a `-wifi`/`-eth` reservation pair.

So the wireless latency was at the measuring end, not the measured end: pinging from a laptop on WiFi
puts a radio in the path no matter what sits at the far end. Two wired vantage points both showed it
flat. The Pi 3 lesson arrived at from the opposite direction — establish where you are standing before
attributing what you see to the target.

**And the Orbi isn't blind, it just isn't the DHCP server any more.** AdGuard on this box has
`dhcp.enabled: true`, so Netgear's Attached Devices list — populated largely from its own lease table —
stopped seeing anything it doesn't lease. Absence from that list ceased to be evidence of anything the
day DHCP moved here, which is documented four entries up and which I still managed to forget.

Genuinely down while I was in there: `toilet1`, 100% loss, no ARP entry at all. Real, unrelated, and
visible again now the reload has taken.

### The alert mail was fine. Everything else's mail was not.

The 2026-08-21 entry above ends "loss alerts now have somewhere real to go", and that holds —
`Smokeping.pm`'s `sendmail` sub execs `sendmail -f $from`, so alerts carry a valid envelope sender. But
six messages sat in the deferred queue retrying every 70 minutes, two of which bounced *after* that fix.

They were not alerts. They were **cron mail** — the catcam RTMP log watcher and `IPCAMERAS/IPCAM1.sh` —
and cron doesn't pass `-f`. Same ``550 Invalid `from` field`` from Resend, for the same reason as the
manual tests: an envelope sender of `<local-user>@macmini` is not a routable address. The Aug 21 fix
had addressed the one caller that already did the right thing, and left every other caller on the box
broken.

A second fault then stacked on top. Postfix tried to bounce those rejections back to local recipients,
local delivery needs alias resolution, and `/etc/aliases.db` **did not exist** — `newaliases` had never
been run. Every failure produced a bounce that itself could not be delivered, deferring forever at
`status=deferred (alias database unavailable)`. A bounce loop that emits no bounce, which is precisely
why a week of it made no noise.

Fixed at the transport rather than per-caller, so it covers anything on the box that shells out to
`sendmail`:

```bash
# /etc/postfix/generic
@macmini    <alert-from>
```

```bash
sudo postmap /etc/postfix/generic
sudo postconf -e 'smtp_generic_maps = hash:/etc/postfix/generic'
sudo newaliases
sudo systemctl reload postfix
```

`smtp_generic_maps` applies only on delivery via the smtp transport, so local mail keeps local
addresses and only what actually leaves the box gets a routable sender. Verified as the `smokeping`
user with no `-f` at all: `status=sent`, Resend message ID in `mail.log`. Queue flushed to empty, all
six bounces delivered to local mailboxes rather than discarded.

One trap worth naming: `postmap -q smokeping@macmini hash:/etc/postfix/generic` returns nothing and
exits 1. That is not a broken map — `postmap -q` does exact-key lookups and never applies `@domain`
wildcard logic. The only honest test of a rewrite rule is to send a message and read `mail.log`.

### The placeholder that was only harmless by accident

`General` still carried `mailhost = my.mail.host` from the package example. `Smokeping.pm` tries
`Net::SMTP` to `mailhost` **first** and only falls through to the sendmail branch when that connection
fails. So every alert was paying a DNS lookup plus up to a 5 s timeout, and the whole alert path rested
on `my.mail.host` continuing not to resolve. AdGuard hands out `local_domain_name: lan`; the day
anything answers for that name, alerts stop arriving and nothing reports it. Removed the line.

Adding `sendmail = /usr/sbin/sendmail` in its place was a mistake — `config.d/pathnames`, which
`General` `@include`s, already sets it, and a duplicate definition is a parse error:

```
ERROR: /etc/smokeping/config.d/pathnames, line 1: variable already defined
```

`smokeping --check` caught it before the reload. The part worth remembering: `systemctl reload
smokeping` returned 0 and left the service `active` with that error outstanding — the same "reload
tells you nothing" problem that opened this entry, showing up again at the end of it. Check the config,
then reload; the reload's own exit status is not the confirmation it appears to be.
---

## 2026-10-13 — The DNS box becomes a UPS client, and the bit that brings it back

This machine shares the APC Back-UPS RS 550S with the QNAP and it is the house's resolver (AdGuard Home on
53), so it has to shut down before the battery does and come back on its own when power returns. The QNAP
is the NUT master — QTS "network UPS master" writes `ACCEPT` lines for `<macmini-ip>` and `<astromeda-ip>` into its
`upsd.conf` — and `printf 'LIST UPS\n' | nc <qnap-lan-ip> 3493` answered `qnapups` before anything was installed.

### The client

`nut-client` 2.7.4, `nut.conf` `MODE=netclient`, and in `upsmon.conf` a single `MONITOR
qnapups@<qnap-lan-ip> 1 … slave` line, `SHUTDOWNCMD "/sbin/shutdown -h +0"`,
`POLLFREQ 5`, `DEADTIME 15`. No `upssched` timer: the box powers down on **OB+LB** (10 % or 120 s left) or on
an FSD from the master, and not before. The Delta 2 upstream causes brief transfers several times a day that
the APC bridges; a five-minute timer would be fine for the NAS and pointless here, and the CatCam stream
should not drop for a relay click.

Ubuntu's client-only package has a quirk: `/run/nut` is created by `nut-server`, which is not installed, so
`upsmon` logs `fopen /run/nut/upsmon.pid: No such file` and systemd reports "supervising process … which is
not our child" — the service shows active but is not actually tracked. A drop-in with `RuntimeDirectory=nut`
and `RuntimeDirectoryPreserve=yes` fixes it; after that `MainPID` is the real daemon. Checks that mean
something: `upsc qnapups@<qnap-lan-ip> ups.status` (OL), `upsc -c qnapups@<qnap-lan-ip>` listing this host, and
the journal.

### The bit that brings it back

When I plugged the shut-down mini into the UPS last week it chimed and booted, which is the SMC's "restart
after power failure" already set from the macOS days. On Linux the same thing is readable in the HM77 PCH:
`setpci -s 00:1f.0 0xa4.b` gave `0x08`, bit 0 (`AFTERG3_EN`) clear = power on when AC returns. A clean Linux
shutdown can set that bit on these minis, so it is now re-cleared with a mask at boot and on the way down
(`macmini-autopoweron.service`, `setpci -s 00:1f.0 0xa4.b=00:01` as `ExecStart` and `ExecStop`) and once more
from `/lib/systemd/system-shutdown/`, which runs after every unit has stopped.

What is not done: nobody has pulled the APC's plug. The whole chain — QTS auto-protection, this client going
to OB, the chime on return — is configured and verified piecewise, not end to end. That is a thirty-second
test on a quiet afternoon, and until it is run this entry describes intent.

## 2026-10-25 — The stream that "stopped every twelve hours" was the network card, and a dialog nobody could click

*Update, same evening: a storm came back with the IOMMU change in place, and the NAS stormed in the same minutes. See the next entry. The OBS half of this entry stands.*

The fanclub page on nekocafetime.com embeds the CatCam broadcast by video ID. It's unlisted, so the
channel's live URL isn't an option. Since late summer the broadcast had been ending on its own every so
often, which leaves members looking at "stream ended" until I paste in a new ID. It felt like every
twelve hours or so. It wasn't.

### Two kinds of drop

OBS keeps a log per launch, and every disconnect in them since March falls into one of two groups. Most
are `WriteN, RTMP send error 32`, which is YouTube closing the socket, followed by a reconnect ten seconds
later that lands on the same broadcast. There are dozens of those. They predate the problem, and nobody
watching notices them. The others start with `send error 110` (a timeout), then
`RTMP_Connect, failed to connect socket` again and again while OBS backs off to several minutes between
retries. They only get through after 9 to 31 minutes. YouTube ends a broadcast about a minute after video
stops arriving, so every one of those became a new video ID.

### The kernel's side

Every gap over nine minutes since August lines up with this in the kernel log:

```
tg3 0000:01:00.0 enp1s0f0: NETDEV WATCHDOG: CPU: 2: transmit queue 0 timed out 5021 ms
tg3 0000:01:00.0 enp1s0f0: transmit timed out, resetting
tg3 0000:01:00.0 enp1s0f0: Link is down
tg3 0000:01:00.0 enp1s0f0: Link is up at 1000 Mbps, full duplex
```

The same four lines then repeat every 20 to 60 seconds, 15 to 18 times over about ten minutes, before
the onboard Broadcom BCM57766 settles down. On 24 October the first reset was logged at 22:23:01 and OBS
lost YouTube at 22:23:12. The journal has 228 of these resets in 12 storms between 21 August (the first)
and 24 October: six of them this month, none in July. The gap between storms ranged from half an hour
(two on the night of 22 October) to seventeen days, so "twelve hours" was just how often I happened to
look. A few shorter outages, two or three minutes long, have nothing behind them in the kernel log, and
neither do two 43-minute gaps on 22 July. Those were something else.

During a storm the box is effectively off the network. upsmon loses the NAS's UPS server with
`No route to host`, and Tailscale decides UDP is blocked. Since this box is also the house's resolver,
everyone's DNS goes with it for ten minutes.

It doesn't look like a dying card. The physical-layer counters in `ethtool -S` are all zero (FCS,
alignment, jabber, collisions). The kernel has logged no PCIe AER errors since the journal begins in
July, and the link renegotiates at gigabit straight away after every reset. What stalls is the transmit
queue: the chip stops completing DMA, the watchdog fires after five seconds, and the driver resets it.
One thing I can't explain yet: `rx_xoff_pause_rcvd` sits near 98,000 and went up by nine in the minute I
watched it. So something upstream of the mini sends it a steady trickle of "stop sending" pause frames.
That may be nothing.

### IOMMU passthrough

Pop!_OS's 7.1 kernel is built with `CONFIG_INTEL_IOMMU_DEFAULT_ON=y` and lazy DMA mode, and the NIC's
IOMMU group reported `DMA-FQ`: every DMA the card does goes through translation. Launchpad bug 2085011
describes the same BCM57766 in a 2014 Mac mini on Ubuntu, "transmit timed out, resetting" and all, and
the reporter's fix was `iommu.passthrough=1`. Pop boots through systemd-boot with kernelstub, not GRUB:

```bash
sudo kernelstub -a "iommu.passthrough=1"   # undo: sudo kernelstub -d "iommu.passthrough=1"
```

After the reboot, `/sys/bus/pci/devices/0000:01:00.0/iommu_group/type` reads `identity`. That fix comes
from one person after one day, and storms here have been seventeen days apart, so I'm not calling it
until late November. In the meantime a small timer (`tg3-stats-log.timer`) appends the non-zero NIC
counters to `/var/log/tg3-stats.log` every minute. If a storm comes back it will at least leave data
behind, including whether those pause frames spike first. In that case the next step is
`ethtool -K enp1s0f0 tso off gso off`, and after that a USB 3 gigabit adapter. Not Apple's
Thunderbolt-to-Ethernet adapter: that's a BCM57762, same family, same driver.

### The dialog that kept the reboot from recovering

The reboot for this was supposed to cost a minute of black screen. It cost seven and a half. The
autostart entry launched OBS, and OBS 32.2.2 stopped at a modal "OBS Studio Crash Detected" box offering
Safe Mode. The reboot had killed the previous instance mid-stream and left its `run_<uuid>` file in
`~/.var/app/com.obsproject.Studio/config/obs-studio/.sentinel/`. Nobody sits at this machine, so nobody
clicks. In that state OBS also ignores SIGTERM, and a second launch just adds an "OBS is already running"
box. Older releases had a `--disable-shutdown-check` flag, but it isn't in this build.

Going back through the logs, this had already happened once. The launch at 09:01 on 11 October logged
`Crash or unclean shutdown detected` and then nothing for thirteen hours, until the mini was rebooted
that evening.

The autostart entry now runs a wrapper instead of OBS directly:

```sh
#!/bin/sh
S="$HOME/.var/app/com.obsproject.Studio/config/obs-studio/.sentinel"
if ! pgrep -x obs >/dev/null; then
    rm -f "$S"/run_*
fi
exec flatpak run com.obsproject.Studio --startstreaming
```

I tested it by starting it by hand (`systemd-run --user`, after `kill -9` on the two stuck instances),
not through an actual login. The next reboot will be the real test.

What still isn't solved: any gap longer than about a minute still ends the broadcast. YouTube's default
"Stream" broadcast has no auto-stop switch. A scheduled stream has one, but that's more ceremony than
pasting a new video ID now and then. The aim is to make those gaps rare.

## 2026-10-25, later — It wasn't this card, or not only: the NAS stormed in the same minutes

*Correction to the entry above. The IOMMU change didn't hold, and the "dying card" framing was too narrow.*

At 21:27 the same evening, five hours after the reboot, it happened again with `iommu.passthrough=1`
in place: fourteen resets in eight minutes, the usual four lines each time. So whatever IOMMU
translation does to this card, it isn't what starts a storm.

This time the per-minute counter logger was running, and it showed the thing I had waved away.
`rx_xoff_pause_rcvd` went from 125 to 28,116 between 21:26 and 21:36. Over the same eight minutes
`tx_octets` grew by about 36 KB. Something was telling the mini to stop sending, about fifty times a
second, and it was barely sending anything.

### Two other machines had the same minutes

The NAS has Intel's `igb`: a different chip, a different driver, a different kernel. It logged
`Reset adapter` 19 times between 21:27 and 21:35, and 20 times between 22:23 and 22:32 on 24 October,
the same window as the mini's previous storm. Since its last boot on 22 October it has received
139,811 pause frames and sent 228. That also answers the "separate and unresolved" LAN stalls of 11 and
12 October in the NAS log: they were two of these storms, not a separate switch fault.

Then the Windows desktop. Its onboard Killer E3100G is a Realtek RTL8125 underneath, and it was still
running the board's original driver from July 2020. Its System log has an NDIS event 10400, "the
network interface has begun resetting", within one to two minutes of the last mini reset in every storm
since 7 September. That's twelve storms and twelve events, counting the night of 22 October as two
storms. The very first storm, on 21 August, has Hyper-V virtual-switch NIC events at its end instead.

### What that does and doesn't show

The tempting story is that the RTL8125 hangs while still asserting XOFF, the switches back up, and every
machine that honours pause frames freezes until its watchdog resets it. Then the storm ends when Windows
finally resets the hung card. RTL8125s hanging under old drivers isn't a rare complaint.

But the correlation fits a second story just as well: the desktop is one more victim, and simply the
last one to recover. Pause frames also aren't forwarded by a compliant switch; they act on one link. If
the desktop is the source, the flood reached the mini by congestion spreading hop by hop, with each
switch generating its own pause frames. The path is desktop → mesh satellite → satellite → router →
8-port switch → the NAS and the mini. I haven't verified that these mesh units behave that way. So
the honest label is "strongly suspected", not "found".

Two smaller things I had wrong:

- On this box, `ethtool -a` says pause isn't negotiated at all ("RX negotiated: off"). Yet it counts
  the frames and its transmit queue still stalls under them. I can't explain that yet. It may be the
  switch port, not the mini, that stops draining.
- On the Pi 3, `ethtool -a` answers "not supported". That only means the `smsc95xx` driver doesn't
  expose the query. The chip does support pause frames. The kernel's own link message ("flow control
  off") is the thing to read.

### What I did, and what I didn't

Watchers first, then one change:

- **A probe on the Pi 3**, which hangs off a different satellite, every 30 seconds: DNS on this box over
  UDP (TCP every five minutes), pings to the router, the satellites, the NAS and this box, and ARP to
  the desktop (it drops pings). It writes only when something changes, plus a heartbeat a day.
- **An observation-only watchdog on the desktop**, every minute: pings from its Ethernet address to the
  satellite it's plugged into, then to the router and the NAS. Each minute is classified as healthy,
  "upstream" (the satellite answers, nothing beyond it does) or "NIC-suspect" (link up, the next hop
  silent three minutes running, counters frozen). It logs and never acts. A watchdog that restarts a
  card on a bad guess would just make more outages.
- **The one change:** the desktop's NIC driver, 10.43.723.2020 → 1125.28.50.1224, from the Microsoft
  Update Catalog (that entry is in the desktop log). Every previous advanced setting was put back
  afterwards, flow control included, so the driver is the only variable.

Deliberately left alone: `iommu.passthrough=1` stays until the checkpoint, because taking it out now
would be a second change. The `tso`/USB-adapter plan from the entry above is dropped, and so is pause
handling on the NAS.

If a storm comes back, the test that would actually settle it is cheap: pull the desktop's Ethernet
cable mid-storm and see whether everything recovers within seconds. Otherwise the checkpoint is late
November, four weeks out, against a longest gap so far of seventeen days.

## 2026-10-25, night — A resolver that trusted a broken CA, and a fix I got wrong first

Two security disclosures landed in the same week, and I went through this box for both.

The first was a pair of PHP remote-code-execution bugs, fixed upstream on 21 October. Nothing to do
here: there is no PHP on this machine at all. SmokePing looks like the kind of thing that would be PHP
and isn't. It's a Perl CGI script run by `fcgiwrap` behind nginx, and the PHP block in nginx's default
site is the commented-out template from the package.

The second was eMudhra. eMudhra is an Indian certificate authority, and a flaw in its April 2025 key
ceremony gave eight of its intermediate CAs private keys with almost no entropy, so anyone could derive
them from the certificates themselves. A researcher reported it on 17 October, and browsers blocked the
intermediates within days. What stays exposed are programs that carry their own list of trusted roots
and don't check revocation, which describes most of what runs in a container.

### What was fine

The host's `ca-certificates` update had already disabled the two roots the bad intermediates chain to:
emSign ECC Root CA - G3 directly, and Sectigo's AAA Certificate Services through cross-signs. `curl`
against the researcher's test hosts failed with a certificate error, which is the pass result. Firefox,
Tailscale (built with a fixed Go) and the Home Assistant container (a fixed `certifi`) were fine too.

### What wasn't

AdGuard Home. The latest stable release was built with Go 1.26.6, before Go added a denylist for these
intermediates in 1.26.10. Its Alpine image ships a CA bundle from June that still contains the emSign
root. And it sends every DNS query in the house to Cloudflare over DNS-over-HTTPS. Anyone in a position
to intercept that connection could have presented a forged certificate for the upstream and answered
for the whole house. Unlikely, but this is the one service everything else trusts.

There was no fixed AdGuard release, so the fix had to come from outside the image.

### The fix I suggested first wouldn't have worked

My first idea was to bind-mount the host's fixed bundle over the container's
`/etc/ssl/certs/ca-certificates.crt`. Before doing it, I checked how Go builds its root pool on Linux:
it reads the first bundle file it finds, and then also loads every file in `/etc/ssl/certs`. This image
keeps one file per root there as well, including `ca-cert-emSign_ECC_Root_CA_-_G3.pem`. Swapping the
bundle would have left the bad root loaded from the directory, and the box looking fixed.

AdGuard has its own root loading on Linux, but it only applies when `/opt/etc/ssl/certs` exists (an
Entware convention). Otherwise it hands over to Go's default, so Go's standard variables work:

```yaml
    volumes:
      - /etc/ssl/certs:/etc/ssl/host-certs:ro
    environment:
      SSL_CERT_FILE: /etc/ssl/host-certs/ca-certificates.crt
      SSL_CERT_DIR: /nonexistent
```

The mount is the whole directory rather than the one file on purpose. `update-ca-certificates` replaces
the bundle with a new file instead of rewriting it, and a single-file bind mount would keep showing the
old one. Go reads its roots once per process, so a host update reaches AdGuard at its next restart.

### Testing the real thing

`curl` on the host proves nothing about a Go program in a container. So I wrote a ten-line Go client,
built it static with the same Go version AdGuard uses (1.26.6, cross-compiled on the laptop), copied it
into the running container and ran it there with `docker exec`, before and after the change:

| Test host | Before | After |
|---|---|---|
| eMudhra test chain, direct | connected | rejected |
| eMudhra test chain, via the Sectigo cross-sign | rejected | rejected |
| cloudflare-dns.com (the upstream) | connected | connected |
| adguardteam.github.io (the blocklists) | connected | connected |
| raw.githubusercontent.com | connected | connected |

The cross-signed chain was already rejected before, because the June bundle no longer had the AAA root.
The direct one was the hole. DNS was answering again about two seconds after the container was
recreated, and DHCP reloaded its leases.

The box's nightly `docker-auto-update` job runs `compose pull` and `up -d` for every running project, so
a new AdGuard image picks up the same override by itself. Once AdGuard ships a build on a fixed Go, the
override comes out again. Left in place, it ties the resolver's trust store to this machine's OS, which
has its own end-of-life date.

## 2026-10-26 — A second resolver on a floating address, and an updater that had never updated anything

This box is the house's only DNS and DHCP server, so every reboot, every AdGuard update and every
NIC storm took the whole LAN's name resolution with it. Now there's a standby. The Pi 3 runs a
second AdGuard Home, and the two share a floating address, `<dns-vip>`, via keepalived. That's
what DHCP, the router and the tailnet now hand out instead of `<macmini-ip>`.

### The pieces

- **keepalived** with unicast VRRP between the two boxes (no multicast through the mesh). This box
  has priority 150, the Pi 100. A failing health check costs 60, so 90 loses to 100.
- **The health check** asks the local AdGuard for a name (any answer counts; a blocked name is
  answered from the lists, so the internet doesn't matter) and pings the router out of the LAN
  port. A link whose transmit queue has stalled, as in the storms, fails the ping even while the
  link reads "up".
- **adguardhome-sync** copies settings one way, from this box to the Pi, every ten minutes. Filter
  lists, rules, clients and the DHCP reservations go across; the DHCP server settings, query log and
  stats don't. I edit on this box only. The first run failed on the reservations with
  `dhcpv4: adding static lease: server is unconfigured`. The replica won't take a reservation until
  its own DHCP server has an interface and a range, even a disabled one. Once it had them, all the
  reservations went across.

### The hold-down that keepalived didn't do

I wanted this box to take the address back only after five minutes of health, so a NIC that flaps
for ten minutes can't drag DNS back and forth with it. I first tried keepalived's own way: the
check needs `rise 60` passes in a row, and `init_fail` makes it start as failed. On 2.2.4 it simply
didn't hold. The log shows `VRRP_Script(chk_dns) succeeded` and `Entering MASTER STATE` within
eight seconds of starting. So the hold-down now lives in the check script: it keeps failing until 300
seconds after its last bad run, and a boot counts as a bad run. Then I tested it from the outside:
the Pi took the address about ten seconds into the hold-down, and this box took it back five
minutes later. A DNS query to the floating address answered the whole time.

### Moving the house over

DHCP now hands out `<dns-vip>` as the DNS server. Changing that meant restarting AdGuard, which cost
1.8 seconds of DNS on this box's own address. It also doubled as the first real failover test: the
health check failed, the Pi took the floating address, and it came back after the hold-down. A
fresh lease on the laptop showed the new server straight away. Everything else moves over at
renewal, half of a 7-day lease.

The satellites briefly take an address near the top of the range while they boot, then switch to
their reservation. So the Pi's own DHCP pool (for later, while it holds the floating address)
stops one short of it.

### unattended-upgrades had been doing nothing

While checking that the Pi would get updates, I looked at how this box gets them. Its
unattended-upgrades log says `No packages found that can be upgraded unattended` every morning:
about 90 runs since the logs begin at the end of July, and not one installed a package. The reason is in the line above it: `Allowed origins are: o=Pop,a=jammy, …`.
The stock config builds its allowed origins from `${distro_id}`, which on Pop!_OS is `Pop`. But the
security updates come from Ubuntu's archive, whose origin is `Ubuntu`. Nothing could ever match,
so every update this box has had came from me running apt by hand. A local drop-in now allows
Ubuntu's `jammy-security` and Pop's own repo. Docker's repo stays manual, since upgrading it restarts
AdGuard and Home Assistant, and reboots stay manual too. Whether it actually installs something is
for the next Ubuntu security update to show.

### Two smaller things

- **SmokePing** now watches the computers too. The laptop has macOS's stealth mode on and drops
  every ping. So it gets SmokePing's TCPPing probe instead: a small `tcpping` wrapper around the
  setuid `tcptraceroute.mt`, timing a single SYN to port 22. The kernel resets the half-open
  connection, so sshd never sees a session.
- **A leftover Wi-Fi hotspot profile** in NetworkManager would have claimed the desktop's old
  address if anything ever switched it on. Deleted.

## 2026-10-26, evening — AdGuard out of Docker, DHCP that follows the floating address, and a house renumbered into blocks

### Native, on the same files

AdGuard Home ran in a container that mounted `conf/` and `work/` at the same paths inside as
outside. So moving it out of Docker didn't need a config migration at all. I downloaded the same
version's release tarball, checked it against the release's `checksums.txt`, stopped the container,
and installed the binary as a systemd service pointed at the existing directories. DNS was answering
again 2.5 seconds after the container stopped, too short for the health check to even move the
floating address. The compose file is renamed rather than deleted, and the rollback is three commands.

The container had one override worth keeping: during the CA compromise the day before, it had been
told to trust the host's CA bundle instead of the image's stale one. The native service gets the same
thing as a systemd drop-in (`SSL_CERT_FILE` pointing at the host bundle, `SSL_CERT_DIR` at nothing),
and the host store itself no longer carries the compromised roots.

Updates are now a small script on a timer. This box installs the latest stable release at 03:30. The
Pi asks this box which version it runs and installs exactly that at 04:45, so the two can't drift
apart. Both verify the checksum first, back up the binary and config, and put the old ones back if
DNS doesn't answer within 30 seconds of the restart.

Docker stays for Home Assistant, whose supported install on a normal Linux box is the container.
Removing the AdGuard image showed that the nightly `docker image prune -f` only drops untagged
images: a leftover Unbound image from 2025 and `hello-world` were still sitting there, a quarter of
a gigabyte between them.

### DHCP that follows the address

Until now the Pi only took over DNS. Now whichever box holds `<dns-vip>` also serves DHCP, and the
other one stays silent. A small script compares "do I hold the address?" with AdGuard's DHCP state
and flips it through the API: it sends back exactly the config AdGuard reported, with only `enabled`
changed. It runs every 30 seconds, and immediately from keepalived's notify hook.

The hook doesn't run the script itself. keepalived starts its scripts with a scrubbed environment,
so a variable set on the keepalived service (like which port this box's AdGuard API is on) wouldn't
reach it. Instead the hook starts the script's own systemd unit, which carries that setting.

The two pools don't overlap, and both servers have the same reservations, so even a few seconds of
both serving can't hand one address to two devices. The DNS option sits in each server's YAML, outside
the API's view, and I checked that toggling DHCP leaves it intact.

The test: force this box into its hold-down, then send a DHCP DISCOVER with a random MAC
(`nmap --script broadcast-dhcp-discover`). Exactly one offer came back, from the Pi, from its own
pool, with a one-hour lease and the floating address as DNS. Five minutes later both flipped back.

*(2026-10-28: this test was flawed. nmap sends from the host's own address, so it never did what a
client without an address does, and the Pi's firewall dropped exactly those requests. See the
Pi 3 log for the real failover, the fix and a proper test.)*

### The house in blocks

Every known device now has a reservation in a block by kind: infrastructure, servers and Pis,
cameras, IoT, computers, TVs and consoles, tablets, phones. Anything that shows up in a DHCP pool is
new by definition. For devices with both, Ethernet takes the lower number and Wi-Fi the next one.

Working out which phone was whose came from the query log, not from guessing. I listed each unknown
device's apps by the domains it looked up, plus an hour-of-day activity profile, then asked. One
profile misled me until I split foreground traffic from background polling: a device that is busy
all day isn't necessarily being used all day.

Changing a reservation is the easy part. The real work is what else has the old address written
down: the NAS firewall's allow-list (changed via two imported profiles, as in the NAS log),
SmokePing's targets, the RTMP server's publish list, the monitoring probes, Plex's custom URL, and
browser bookmarks.

### "Already publishing"

The CatCam Pi moved addresses too, and its push to the RTMP server here didn't come back. Its log
said `Server error: Already publishing`, over and over. The old session from the old address was
still "established" in nginx-rtmp: that address had simply vanished, so nothing ever sent a reset,
and the server kept the stream name locked to a publisher that no longer existed. Killing that one
socket (`ss -K … dst <old-pi-ip>`) let the Pi straight back in. The application now has
`drop_idle_publisher 10s`, so a silent publisher gets dropped by the server itself.

The broadcast ended that afternoon anyway, and I first blamed the camera gap. But the camera going
blank doesn't end a YouTube broadcast: OBS keeps sending the frozen or black source. OBS's log shows
its RTMPS connection to YouTube unbroken from 13:35 until the stream was stopped by hand at 21:55,
with no send errors and no reconnects. So whatever ended the broadcast happened on YouTube's side,
with data still arriving. I don't know what.

## 2026-10-28 — A failover nobody asked for, a hold-down that kept restarting, and what "User stopped the stream" means

The mesh got new firmware today, and afterwards I tidied its settings. Applying them made the router
skip pings for a moment. That was enough: the health check pings the router, so this box failed its
check at 14:07 and the Pi took the floating address 30 seconds later. That part worked as designed,
and DNS answered throughout. DHCP didn't (see the Pi 3 log).

### A hold-down that kept restarting

The hold-down lasts five minutes from the last bad check, so the address should have come back
around 14:13. Instead the check failed three more times, at 14:09, 14:12 and 14:14. Each time AdGuard
on this box hadn't answered its own two-second test query. Each failure restarted the five minutes,
and the address only came back at 14:19:55. AdGuard logged no errors. The first two misses bracket an
`apt upgrade` I ran at 14:10, and tailscaled was logging timed-out connections at the same time. The
overlap is suggestive but not proof, so I'll watch for it again.

### Who bypasses the floating address

With failover working, the remaining risk is a device that has this box's own address set as its DNS
server somewhere. It would lose DNS in a failover while everything else carried on. Three minutes of
`tcpdump` for DNS sent to this box's own address found exactly one sender: the Pi's monitoring probe,
which asks this box directly on purpose. Nothing else.

### unattended-upgrades, for real

Two days ago I wrote that only the next Ubuntu security update would show whether the new drop-in
worked. It came the next morning: at 06:25 on 10-27 the log says
`Packages that will be upgraded: … nginx nginx-common nginx-core …`, then `All upgrades installed`.

### "User stopped the stream"

At 14:07 the router's settings apply cut OBS's connection to YouTube, and it reconnected by itself ten
seconds later. At 14:11 its log says `User stopped the stream`, followed by a clean shutdown. That was
me closing OBS to install updates: quitting OBS mid-stream logs exactly that, and a clean exit means no
Safe Mode dialog at the next start.

### Reading SmokePing without rrdtool

Afterwards the SmokePing graphs showed red bands on every mesh satellite, which looked like packet
loss. This box has no `rrdtool` binary, but SmokePing's own Perl module reads the files directly:
`RRDs::fetch("…/Sat1.rrd", "AVERAGE", "-s", "-40h", "-r", "300")`. The `loss` column, lost pings
out of 20 per five minutes, lined up exactly with the firmware reboots and the DHCP outage. The 38
hours before were at zero, and 100 fast pings per unit afterwards lost none.
