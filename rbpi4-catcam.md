# Streaming with Raspberrypi 4 and C525 webcam
**Last updated: 2026-07-28**

> **2026-06-20:** The MJPEG + VLC-window-capture pipeline described below is **superseded**. The Pi now hardware-encodes H.264 and pushes it as RTMP to the Mac Mini's nginx, which OBS ingests directly — no screen capture, and it runs over WiFi. See **[2026-06-20 Update — H.264 over WiFi → RTMP](#2026-06-20-update--h264-over-wifi--rtmp-supersedes-the-vlc-window-capture)** at the end. The MJPEG sections remain as reference.
## Background
The Raspberry Pi 3 and 4, model B-boards can relay UVC-compliant USB camera feeds over the local network. This can be utilized for live-streaming your cats, but also for surveillance applications, etc.
That said, the boards are not powerful enough to stream the camera-feed directly as it is too much data, while USB-buses and networking share the same limited bandwidth. Instead, one can ingest the feed as motion-JPEG (MJPG) data, which is basically a JPEG capture of each frame, which are relayed to a HTTP server which broadcasts on the local network.
There are many ways to achieve this however in this guide the MJPG-Streamer-Experimental library will be utilized. Note that this library is no longer maintained but remains a reliable option.

## Materials
- Raspberrypi 3 or 4, model B with at least 2GB RAM
- Protective case (RBPi4 may need active cooling)
- Raspbian 64-bit OS
- USB-A webcam (USB-C webcams send too much data for the BUS to handle)
- Adequate power adapter (i.e., 5V, 3A for RBPi4)
- [mjpg-streamer](https://github.com/jacksonliam/mjpg-streamer)

## Procedure
### Raspberry Pi Setup
Setup the Raspberry Pi so that it has the latest OS and updates. Make sure you can connect to it via SSH from another device. VNC is optional but helpful (Tiger VNC is an excellent client). Connect the USB-camera and check `dmesg` that there are no communication problems. Otherwise, check that the powersupply is of correct rating, or switch camera.
### Installing mjpg-streamer
First, make a directory called mjpg-streamer:

    mkdir -p mjpg-streamer
Download the project's zip file:
https://github.com/jacksonliam/mjpg-streamer/archive/refs/heads/master.zip
Extract its contents into the new folder.

 Ensure the Pi 4 has `cmake`, `build-essential`, and other required packages:

    sudo apt update
    sudo apt install cmake build-essential
    libjpeg-dev
Navigate to:

    cd mjpg-streamer/mjpg-streamer-experimental
Build the project:

    mkdir -p _build && cd _build
    cmake -DCMAKE_BUILD_TYPE=Release ..
    make
Make sure you build it on each target machine as there may be differences in the resulting binaries depending on which RBPi you have.

Copy binaries, plugins, and HTML files to system-wide locations:

    sudo cp _build/mjpg_streamer /usr/local/bin/
    sudo mkdir -p /usr/local/lib/mjpg-streamer
    sudo cp _build/plugins/input_uvc/input_uvc.so /usr/local/lib/mjpg-streamer/
    sudo cp _build/plugins/output_http/output_http.so /usr/local/lib/mjpg-streamer/
    sudo cp -r www /usr/local/share/mjpg-streamer/
This way the binaries are accessible by the system, along with the necessary plugins and HTML files.

## Creating mjpg-streamer service in Systemd
Systemd allows runs your program as a service on boot which means it the program will be restarted if there are any crashes. Makes it much more resilient and the Raspberry Pi acts more like a utility than a computer.

Begin by creating a service:

    sudo nano /etc/systemd/system/mjpg-streamer.service

Fill it out like this:

    [Unit]
    Description=MJPG-Streamer webcam service
    After=network.target
    
    [Service]
    Restart=always
    RestartSec=1
    User=pi-admin
    Group=pi-admin
    ExecStart=/usr/local/bin/mjpg_streamer \
      -i "/usr/local/lib/mjpg-streamer/input_uvc.so -d /dev/video0 -r 1280x720 -f 30" \
      -o "/usr/local/lib/mjpg-streamer/output_http.so -p 8080 -w /usr/local/share/mjpg-streamer/www -c admin:<YOUR_PASSWORD>"
    StandardOutput=journal
    StandardError=journal
    
    [Install]
    WantedBy=multi-user.target
It will start the mjpg-streamer service after network stack has been loaded. It will restart as soon as there is a problem. Make sure the user and group matches that of your user. You may have to change the permissions of your user so you that you can access the files used by the service.

Make sure that the paths in `ExecStart` points to the correct locations of the mjpg-streamer binary (/usr/local/bin/mjpg_streamer), the plugins (/usr/local/lib/mjpg-streamer/) and the html files (/usr/local/share/mjpg-streamer/www).

It is also here that you can set credentials for accessing the stream, set the port used and the resolution of the video. Note, if your webcam is not /dev/video01 you have to check using:

    sudo apt install v4l-utils
    v4l2-ctl --list-devices
It should list all webcams available. Change the device number accordingly in the service file. Note that devices IDs may change after reboots. To make it persistent, one can create a `udev` rule or use `-d /dev/video/by-id/...` in mjpg-streamer.

## Starting the service, troubleshooting
First, load the new service into systemd:

    sudo systemctl daemon-reload

Then, start the service:

    sudo systemctl start mjpg-streamer

Check how it went:

    systemctl status mjpg-streamer
Any error messages should now be displayed. Usually, the problems are either with permissions for the user, the paths to the binaries, plugins and HTML files or formatting issues in the mjpg-streamer.service file itself.

Systemd servives often fail if the user does not have access to the webcam device. Try:
    
    sudo usermod -aG video pi-admin
This ensures the pi user can access `/dev/video0` without `sudo`.

After you correct any issues, you can restart the service to see the effects:

    sudo systemctl restart mjpg-streamer

Once the stream is up and running, the service relays MJPG data as an http stream over the local network.

For auto-start on reboot:

    sudo systemctl enable mjpg-streamer

Access it via browser, VLC etc:
http://admin:<YOUR_PASSWORD>@<pi-lan-ip>:8080/?action=stream

The stream can be fed into different software, depending on the purpose; either live-streams or surveillance, etc.

## Live-streaming via OBS Studio (Linux)

> ⚠️ **Superseded 2026-06-20** — kept for reference. OBS now ingests an H.264 RTMP stream from the Pi directly; see the update at the end of this file. The VLC-window/XComposite approach below is no longer in use.

The working setup is to play the MJPEG stream in a dedicated VLC window and then capture that window in OBS using **XComposite Window Capture**.

I originally tried pulling the stream directly into OBS as a Media Source, but it would silently stall and OBS provides no clean recovery hook when the upstream MJPEG feed hiccups. Capturing pixels off a VLC window sidesteps the problem entirely:

- VLC has aggressive built-in retry and buffering for HTTP-MJPEG
- A small `while true` watchdog around `cvlc` restarts it if the stream drops or VLC exits
- OBS just captures whatever the window is displaying, so it's immune to upstream issues

The flow:

1. `autovlc.sh` runs `cvlc` in a window and restarts it on failure
2. `autovlc.service` (systemd user-session service) starts the script when the desktop loads
3. In OBS, add an **XComposite Window Capture** source pointing at the VLC window

## Create VLC Watchdog Script

    nano autovlc.sh

Edit the file to look like this:

    #!/bin/bash
    while true; do
      cvlc --no-video-title-show --quiet --network-caching=1000 \
           --width=1280 --height=720 --no-autoscale \
           "http://admin:<YOUR_PASSWORD>@<pi-lan-ip>:8080/?action=stream"
      echo "[`date`] VLC crashed or stream ended. Restarting in 5s..."
      sleep 5    done

`cvlc` → runs VLC without the full GUI, just the video window.

`--no-video-title-show` → hides the filename overlay.

`--quiet` → suppresses extra console messages (still prints errors if something breaks).

 `--network-caching=1000` → 1 second buffer, helps smooth network hiccups.

 `--no-autoscale` → prevents automatic scaling to fit the window

Infinite `while true` loop → automatically restarts VLC if it exits/crashes.
`echo …` + `sleep 5` → Prints a timestamped message when VLC drops and it waits 5s before retrying.

Make the file executable and run the file:

    chmod +x autovlc.sh
    ./autovlc.sh

VLC will auto-retry  indefinitely in case the Raspberry Pi encounters any problems.

In OBS, add a new **XComposite Window Capture** source (Linux only) and pick the VLC window from the dropdown. The capture is direct from the X11 compositor, so there's no decoding overhead beyond what VLC is already doing.

## autovlc Service
For best resilience and most utility, make autovlc.sh a service:

    sudo nano /etc/systemd/system/autovlc.service
Edit the file like this:

    [Unit]
    Description=Auto VLC (user session)
    After=graphical.target
    
    [Service]
    Type=simple
    ExecStart=/home/macmini2012/autovlc.sh
    Restart=always
    Environment=DISPLAY=:0
    Environment=XDG_RUNTIME_DIR=/run/user/1000
    User=macmini2012
    
    [Install]
    WantedBy=default.target
**Description** → A short text describing what the service is. Useful for `systemctl status`.
    
**After=graphical.target** → Tells systemd to start this service **after the graphical environment (your desktop) has loaded**. This is important because VLC needs a running X/Wayland session to open a window.

**Type=simple** → Default type; systemd assumes the process started by `ExecStart` is the main service process.
    
**ExecStart** → The command to run. Here, it runs your VLC script.
    
**Restart=always** → If the script or VLC crashes, systemd will automatically restart it.
    
**Environment=DISPLAY=:0** → Tells VLC which X display to use. Usually `:0` is your main desktop session.
    
**Environment=XDG_RUNTIME_DIR=/run/user/1000** → VLC needs this to access session-specific resources like sockets. Replace `1000` with your user’s UID (`id -u macmini2012`).
    
**User=macmini2012** → Runs the service as your regular user (so it can access your X session).
**WantedBy=default.target** → Tells systemd when to enable/start this service. `default.target` is your normal user session target, so the service will start when you log in.

For auto-start on reboot:

    sudo systemctl enable autovlc

### Key points

1.  **This is a user-level GUI service**, not a system-level headless service. This is why  `DISPLAY` and `XDG_RUNTIME_DIR` are set.
    
2.  Running it as a system service under `/etc/systemd/system` without these environment variables causes VLC to fail (errors like `XDG_RUNTIME_DIR is invalid`).
    
3.  `Restart=always` + the autovlc.sh script loop ensures VLC keeps trying if the stream fails.
    
4.  The script still handles retrying if VLC exits normally or crashes — systemd just guarantees it’s automatically restarted even outside the terminal.

Note that there may be prompts for user authentications when the script starts the first time.

---

## 2026-06-20 Update — H.264 over WiFi → RTMP (supersedes the VLC-window capture)

The MJPEG + XComposite approach above worked but was fragile: OBS can't ingest raw MJPEG cleanly, screen-capturing a VLC window is a hack, and MJPEG's ~15–40 Mbps forced the Pi onto Ethernet. The C525 has no onboard H.264 (only `YUYV`/`MJPG`), **but the Pi 4 does** — the VideoCore `bcm2835-codec` exposes a hardware H.264 encoder through V4L2 (`h264_v4l2m2m`). So the Pi now encodes H.264 itself and pushes it straight into the Mac Mini's nginx-RTMP. OBS ingests it as a normal Media Source — no screen capture — and the ~3 Mbps stream rides 5 GHz WiFi with no bufferbloat.

```
C525 → ffmpeg h264_v4l2m2m (720p30, ~3–4 Mbps) → RTMP over 5 GHz WiFi
   → rtmp://<macmini-ip>/live/catcam (nginx-RTMP) → OBS rtmp://localhost/live/catcam → YouTube
```

### Why 5 GHz matters (and why the Pi 3 couldn't do this)
The Pi's onboard `brcmfmac` WiFi is a FullMAC chip — its queue management lives in opaque firmware, so Linux's anti-bufferbloat machinery (`fq_codel`/airtime fairness) can't help. On the Pi 3's congested 2.4 GHz that meant a catastrophic latency staircase under sustained upload. The Pi 4's BCM43455 is dual-band: on a **clean 5 GHz channel** at <1 % of the link rate, the firmware queue simply never builds. Measured under a sustained ~3 Mbps push: ping stayed ~7–30 ms, 0 % loss (vs. 1.7–18 s and 36 % loss on the Pi 3).

### Enable + pin WiFi (Pi 4)
WiFi had been disabled via `dtoverlay=disable-wifi` in `/boot/firmware/config.txt`. Comment that line out (keep `dtoverlay=disable-wifi-power-save`), reboot, then force 5 GHz on a clean non-DFS channel and kill power-save persistently:
```bash
sudo nmcli con modify preconfigured 802-11-wireless.band a \
     802-11-wireless.channel 36 802-11-wireless.powersave 2
```
While Ethernet is still attached as a maintenance lifeline, pin **just the stream** to WiFi so management traffic stays on eth0:
```bash
sudo nmcli con modify preconfigured +ipv4.routes "<macmini-ip>/32"
```

### H.264 RTMP push service
Retire `mjpg-streamer` and replace it with one ffmpeg → RTMP service reading `/dev/video0` directly.
`/etc/systemd/system/catcam-rtmp.service`:
```ini
[Unit]
Description=CatCam H.264 RTMP push (C525 -> macmini nginx-rtmp)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=<pi-user>
Group=<pi-user>
ExecStart=/usr/bin/ffmpeg -nostdin -hide_banner -loglevel warning \
  -f v4l2 -input_format mjpeg -video_size 1280x720 -framerate 30 -i /dev/video0 \
  -c:v h264_v4l2m2m -b:v 4000k -g 60 -pix_fmt yuv420p \
  -an -f flv rtmp://<macmini-ip>/live/catcam
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl disable --now mjpg-streamer.service
sudo systemctl enable --now catcam-rtmp.service
```

### Mac Mini side
nginx-RTMP already has an `application live { live on; }` block, and OBS ingests `rtmp://localhost/live/catcam`. Two things bit me (see `macmini-2012-log.md`): the Mac Mini's **UFW blocked 1935** (only localhost had ever used it — open it to the LAN), and the OBS Media Source had **reconnect disabled** so it sat black until the eye-icon was toggled off→on.

### Notes
- `h264_v4l2m2m` is hardware, so the Pi's CPU stays near idle.
- The C525's `mjpeg @ … unable to decode APP fields` warning is harmless.
- `iw` / `tc` / `rfkill` ship on Raspberry Pi OS but live in `/usr/sbin` (not on the non-login SSH `PATH`) — call them by full path.

---

## 2026-07-28 Update — WiFi watchdog (auto-recover from the brcmfmac wedge)

The Pi occasionally dropped off WiFi after AP flukes and never came back — only a power cycle fixed it. Known Pi 3/4 behaviour, and it's **not** (only) power-save: powersave has been off here since 2026-06-20 and it still happened. The real culprit is the `brcmfmac` FullMAC firmware wedging after a disconnect: `wlan0` still looks up to Linux, wpa_supplicant never receives a disassoc event, scans return empty, so NetworkManager sees nothing to reconnect to. An `ip link set wlan0 down/up` does *not* clear this state — only reloading the kernel module (or rebooting) does. Fix is three layers:

### 1. Stop NetworkManager from giving up
NM's default `connection.autoconnect-retries` is 4 — after four failed attempts it blocks the profile until "something" (often nothing, headless) triggers a rescan. `0` means retry forever:
```bash
sudo nmcli con modify preconfigured connection.autoconnect-retries 0
```
This alone fixes the cases where the radio is fine but NM stopped trying. It can't fix a wedged firmware, hence:

### 2. Escalating watchdog (files in `rbpi4-catcam/`)
`wifi-watchdog.timer` runs `wifi-watchdog.sh` every minute. It pings the **wlan0 connection's own gateway** (`nmcli -g IP4.GATEWAY device show wlan0`, not the default route — eth0 owns that when the maintenance cable is in) with `ping -I wlan0`, so it tests the WiFi path specifically. On consecutive failures it escalates:

| consecutive fails | action |
|---|---|
| 1 | log only — give NM its own chance |
| 2 | `nmcli device disconnect` → rescan → `nmcli connection up preconfigured` |
| 4 | `modprobe -r brcmfmac_wcc brcmfmac` → `modprobe brcmfmac` → reconnect (clears the wedge) |
| 6+ | reboot — skipped if uptime <10 min (boot-loop guard) |

Worst case is back on air in ~6 minutes with zero human involvement. Design notes:
- Counter lives in `/run` (tmpfs) so a reboot resets it.
- Stage 2 deliberately avoids `nmcli radio wifi off` — NM persists that flag in `/var/lib/NetworkManager/NetworkManager.state`, and a power cut mid-toggle would boot the Pi with WiFi permanently off. Instead every failure pass runs `rfkill unblock wifi` + `radio wifi on` as idempotent safety.
- `brcmfmac_wcc` is unloaded first: on kernels ≥6.1 it holds a reference that makes `modprobe -r brcmfmac` fail.
- `TimeoutStartSec=90` on the service: a truly dead firmware can hang `modprobe -r`; systemd kills the run and the counter keeps marching toward reboot.

Install (from this repo):
```bash
scp rbpi4-catcam/wifi-watchdog.* <pi-user>@<pi-lan-ip>:
ssh <pi-user>@<pi-lan-ip>
sudo install -m 755 wifi-watchdog.sh /usr/local/sbin/
sudo install -m 644 wifi-watchdog.service wifi-watchdog.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wifi-watchdog.timer
```
Verify and live-test:
```bash
sudo systemctl start wifi-watchdog.service   # one manual pass
journalctl -u wifi-watchdog -f               # then block the Pi's MAC at the AP and watch the ladder climb
```

### 3. Hardware watchdog for full kernel hangs (belt and braces)
Some "never came back" incidents are the whole kernel hanging, which no userspace script survives. The BCM2711 has a hardware watchdog; let systemd pet it:
```bash
# /etc/systemd/system.conf
RuntimeWatchdogSec=15    # bcm2835_wdt max is 15s
```
```bash
sudo systemctl daemon-reexec
```
If the kernel locks up, the SoC resets itself after 15 s instead of waiting for a human with a power plug.

### Bonus fix: `catcam-rtmp.service` could rate-limit itself to death
During a long network outage ffmpeg exits fast (connection refused), and systemd's default start limit (5 starts / 10 s) can put the service into permanent `failed` — stream stays dark even after WiFi recovers. Disable the limit:
```ini
# in [Unit] of catcam-rtmp.service
StartLimitIntervalSec=0
```

## SSH access corrected (2026-07-28)

The Mac's `~/.ssh` LAN entry for this Pi had been pointing at an address the Pi doesn't hold. Nothing
noticed because everything reaches it over Tailscale; the LAN alias is the shortcut for when the
tailnet is the thing being debugged, which is exactly when you don't want to discover it's wrong.

The real address came from `hostname -I` over Tailscale, cross-checked against a Raspberry Pi OUI in
the Mac's ARP table. AdGuard on the Mac Mini holds a DHCP reservation for this Pi, so the address is
pinned — the config entry simply predated the reservation.

Connecting then failed with `Host key verification failed`, which is just first-contact on an address
`known_hosts` had never seen. Rather than trusting it blind I pulled the host key over the
already-trusted Tailscale session and compared fingerprints before accepting it — same key, same
machine. The stale entry for the old address was removed.

Both the Tailscale and LAN entries now also answer to `catcam` alongside the `raspberrypi4` names, so
existing scripts are unaffected.

## 2026-08-03 — EEPROM update, and what a reboot does and doesn't do to the stream

`rpi-eeprom-update` had been reporting an update available for months and I'd been leaving it, on the
grounds that this box is a livestream that people watch and the update needs a reboot.

Worth knowing how it actually works, because it isn't what the command name suggests: it doesn't
flash anything when you run it. It **stages** files into `/boot/firmware` and the bootloader picks
them up on the next boot. So the update and the risk are two separate events, and you choose when the
second one happens. Afterwards, `vcgencmd bootloader_version` for the date it's actually running, and
`rpi-eeprom-update` again for "up to date" — check both, because the staged files are gone either
way.

Here that was a 2025-05 bootloader to a 2026-01 one. Boot came back in 11.8 s with no failed units,
and the camera was pushing again unattended.

### The part I got wrong about the consumer side

I'd planned around the idea that the OBS box would need attention afterwards — reopen the media
source, at minimum. It didn't, and the reason is worth writing down.

**OBS never dropped its ingest socket.** Same PID, same established connection to the RTMP server on
`127.0.0.1:1935`, straight through the reboot. Because the RTMP server holds the *application* open;
it's only the **publisher** that goes away and comes back. The consumer is talking to the server, not
to the Pi, and it has no idea the Pi rebooted at all.

So the whole customer-visible blackout is the Pi's own boot window — about half a minute — and
`Restart=always` on the push service covers the rest. No manual step on the other machine.

The generalisable bit, which has now bitten me twice from opposite directions: **publisher state and
consumer state are not the same thing, and neither is evidence about the other.** A dead publisher is
not a dead consumer socket. Check the side you're actually asking about.

