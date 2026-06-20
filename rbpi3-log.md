## 2026-06-19 — SOLVED: QVR Pro stream corruption (the 2-year mystery)

### The symptom

C920 → `ffmpeg` (publisher) → MediaMTX → QVR Pro, over RTSP. QVR Pro showed
progressive corruption: top ~15% of the image pixelates, magenta artefacts spread
downward over seconds/minutes, never recovers. CPU <5%, no USB/bandwidth issue.
The original publisher used `-c:v copy` of the camera's native H.264. The classic
red herring: **VLC/ffplay played the exact same stream perfectly** — so it "looked"
like the stream was fine and QVR was at fault, and 2 years of forum-searching led
nowhere.

### Root cause (the real one)

The C920's hardware H.264 stream carries **no in-band SPS/PPS**. The parameter sets
exist only in the RTSP **SDP** (`sprop-parameter-sets`). VLC reads them from the SDP
and decodes fine. **QVR Pro's decoder ignores the SDP and requires SPS/PPS in-band,
repeated before every IDR.** Without them, every keyframe decodes to garbage that
accumulates. Confirmed by capturing the raw camera stream — ffmpeg itself throws the
exact errors from the old logs:

```
[h264] non-existing PPS 0 referenced
[h264] decode_slice_header error
```

A NAL histogram of the native stream showed **0× SPS, 0× PPS** in-band. Two
secondary aggravators stacked on top:

* **10-second keyframe interval** (camera GOP 150 @ 15fps) — any glitch persists up
  to 10s. Verified: I-frame at t=2.19s, next at t=12.19s.
* **UDP transport** — QVR negotiated UDP with MediaMTX (`rtspTransports: [udp, tcp]`)
  and dropped packets on the LAN. VLC used TCP. Even after fixing the GOP, QVR over
  UDP still corrupted.
* **Multi-slice frames** — `-tune zerolatency` made libx264 emit ~4 slices/frame
  (sliced-threads on the quad-core); multi-slice + missing param sets compounds the
  decoder incompatibility.

The decisive isolation step: once QVR was forced onto TCP (lossless) it *still*
corrupted while VLC on TCP was clean → the only remaining difference was SDP-vs-in-band
parameter sets + slicing. Adding `repeat-headers=1` + `slices=1` fixed it instantly.
QVR overlay went from `@1.0 fps GOP 150` (only decoding keyframes) to `@15 GOP 15`,
clean.

### The fix

Re-encode in the publisher (can't `-c copy`, since changing GOP / inserting headers
requires re-encoding). Final `/etc/systemd/system/c920-publisher.service` ExecStart:

```
/usr/bin/ffmpeg -hide_banner -loglevel error -nostdin \
  -use_wallclock_as_timestamps 1 \
  -f v4l2 -input_format h264 -video_size 1280x720 -framerate 15 -i /dev/video0 \
  -map 0:v:0 -an \
  -vf scale=in_range=full:out_range=limited \
  -c:v libx264 -preset ultrafast -profile:v baseline -pix_fmt yuv420p -bf 0 \
  -g 15 -keyint_min 15 -sc_threshold 0 \
  -x264-params repeat-headers=1:sliced-threads=0:slices=1 \
  -b:v 2500k -maxrate 2500k -bufsize 2500k \
  -f rtsp -rtsp_transport tcp -pkt_size 1400 \
  rtsp://127.0.0.1:8554/c920
```

Load-bearing flags (do **not** remove without re-testing QVR):

| Flag | Purpose |
|------|---------|
| `repeat-headers=1` | SPS/PPS in-band before every IDR — **THE fix** |
| `slices=1` (+ `sliced-threads=0`) | single-slice frames |
| `-g 15 -keyint_min 15 -sc_threshold 0` | fixed 1s GOP |
| `-profile:v baseline` | Constrained Baseline = QVR-proven |
| `scale=in_range=full:out_range=limited` | C920 is full-range yuvj420p; QVR wants limited |
| `-pkt_size 1400` | stops MediaMTX re-fragmenting oversized RTP |

And in `/etc/mediamtx/mediamtx.yml`: `rtspTransports: [tcp]` (was `[udp, tcp]`) —
forces QVR onto lossless TCP; UDP now returns `461 Unsupported Transport`.

A regression-guard README was dropped at
`/etc/systemd/system/c920-publisher.README.md` summarising all of the above.

### Why not the Pi hardware encoder (h264_v4l2m2m)?

Investigated because CPU sits at ~1.3–1.5 of 4 cores (~37%). On this stack (mainline
`bcm2835-codec`, kernel 6.12.93, May 2026 firmware) the encoder is **stable and good
quality** — the old MMAL/OMX flakiness is gone. But:

* This FFmpeg build's `h264_v4l2m2m` exposes **no profile control** → locked to
  **High profile** (re-introduces QVR-compat risk). Forcing baseline needs a full
  GStreamer rewrite (`v4l2h264enc` + `extra-controls`).
* Chaining the hardware **decoder** for the V4L2 camera capture failed (empty output).
* The CPU win is only ~0.5 core and the encode itself is already nearly free; the real
  cost is the software H.264 decode of the camera feed.

Verdict: **keep libx264.** 37% on a quad-core Pi 3 runs cool and stable; not worth the
rewrite/risk on a system that just became stable. If CPU ever matters, drop 15→10 fps.

### Camera (C920) v4l2 controls

Were left in manual (manual exposure, manual focus @30, gain 0) from earlier debugging,
with no persistence (revert to auto on replug/reboot). First restored to auto defaults
for night. In daylight, **pinned focus** (manual, `focus_absolute=0` = infinity — sharp
for this far outdoor view) while **keeping auto-exposure** (Aperture Priority) and auto-WB,
since outdoor light swings day↔night and a fixed exposure would go black at dusk.

Persistence: done via **`ExecStartPost`** on c920-publisher, non-fatal (`-`), runs on
every start incl. boot; a camera replug → `Restart=always` → re-pins. **Must be two
separate `v4l2-ctl` calls** — AF off first, *then* `focus_absolute`:
`sleep 6; v4l2-ctl --set-ctrl=focus_automatic_continuous=0; v4l2-ctl --set-ctrl=focus_absolute=0`.
Setting both in one atomic call fails with `EACCES` on a cold boot, because while
autofocus is ON, `focus_absolute` is an inactive/read-only control and the whole
ext-ctrls call is rejected (only "worked" in testing because AF was already off then).
Avoid `ExecStartPre` for this: opening the device with v4l2-ctl immediately before
ffmpeg is a double-open that lengthens the camera's first-keyframe wait at startup
(floods the input decoder with `decode_slice_header` errors for several seconds, and
garbles the output until the first IDR). `ExecStartPost` sets the control on the
already-open device while ffmpeg streams — verified no stream disruption.

### pi-motion-detect.service (fixed, tuned, active)

Low-rate motion detector (`/usr/local/bin/pi-motion-detect.py`, opencv 4.6.0): reads
RTSP at 320×180/2fps grayscale, frame-diffs, curls QVR Pro's `logical_input.cgi` event
URL. **Purpose:** QVR Pro caps internal motion detection at 2 channels — offloading the
C920's detection to the Pi frees a QVR channel for another (cheap Chinese) IP cam.
Never tested before because of the corruption. Now that the stream is clean:

* Reader used `-c:v h264_v4l2m2m` (hardware decode) and **underperformed** (11 frames
  in 8s vs 15 with software decode) → **switched to software decode** (`.py.bak` kept).
  Decode cost is trivial at 320×180.
* Event URL **verified end-to-end**: QVR returned `{"success":true}` / HTTP 200.
* Night calibration: static-scene baseline = **0 changed pixels** (blur + threshold 25
  fully suppress sensor noise), so no false triggers and clean detection headroom.
* **Tuned** `MOTION_DEBOUNCE_SEC 10→1` and `MOTION_COOLDOWN_SEC 30→20`: the old 10s
  debounce required 10s of *continuous* motion (resets on any still frame) — nothing is
  visible that long at this angle, so people/animals passing through never triggered.
* `/etc/default/pi-surveillance` held the QVR event token **world-readable (644)** →
  hardened to `640 root:pi-admin66`. Pre-tuning config kept as `.bak`.
* Caveat: with auto-exposure now on, global brightness shifts may cause false triggers
  — another argument for fixed exposure on a CCTV view.
* **Gotcha (cost me a debug cycle):** unit had `Requires=c920-publisher.service`. Every
  publisher restart (e.g. the audio work) **stopped** this service via that dependency
  and never brought it back — so detection was silently dead. Changed to soft
  `Wants=` + `After=` (the script already retries the RTSP connection, so it self-heals
  across publisher restarts). `.service.bak` kept.
* **Verified end-to-end** (night walk-through): changed-pixels 500–2907 vs ~0 static
  baseline; service fired two real QVR events (`Triggered QVR motion event URL`),
  spaced by the 20s cooldown. Thresholds (25 / 500) left as-is — well separated.

### Audio (C920 mic → QVR Pro)

Stream was video-only (`-an`). Added the C920's USB mic (ALSA card 2,
`plughw:CARD=C920,DEV=0`; native S16_LE stereo 16k/32k; not muted, ~50 dB gain) as a
second ffmpeg input, encoded **AAC-LC 32 kHz mono 96k**, mapped alongside the existing
video (all video flags byte-identical — fix untouched). MediaMTX now serves
**2 tracks (H264, MPEG-4 Audio)**; verified audio flowing over RTSP (mean ≈ −36 dB).

Robustness notes baked into the unit:
* `-thread_queue_size 8192` on the ALSA input (1024 caused `Thread message queue
  blocking` → risk of audio drops).
* `-use_wallclock_as_timestamps 1` on **both** inputs + `-af aresample=async=1000` to
  keep A/V sync (separate V4L2 and ALSA clocks would otherwise drift).
* Tradeoff: audio capture is now coupled to the video pipeline — a USB-audio glitch
  restarts the whole publisher (≈5s blip). Acceptable; `Restart=always` recovers.
* CPU rose ~1.3 → ~1.6 cores (AAC encode + resample). If QVR won't play AAC, fall back
  to G.711 (`-c:a pcm_mulaw -ar 8000 -ac 1`).
* **QVR must re-add the channel** to pick up the new audio track (SDP changed), and
  enable Audio on the channel.

### WiFi re-test — verdict: stay on Ethernet (2026-06-20)

Since the corruption turned out to be SPS/PPS (not bandwidth), re-tested running the Pi
on WiFi only. Re-enabled WiFi (commented `dtoverlay=disable-wifi` in
`/boot/firmware/config.txt`, reboot). Box uses **NetworkManager** now (not the
`wpa_supplicant.conf` the old diary describes); saved conn "preconfigured", **wlan0
static .50**, eth0 .51. Access is over **Tailscale** (`100.121.233.34`, per-node, so it
survives an eth↔wifi switch — `ssh raspberrypi3` → that IP).

Result: **WiFi is unfit for the CCTV upload.** Signal was strong (−50 dBm, 0% loss on
short bursts), stream decoded clean — but under sustained ~2.6 Mbps upload the Broadcom
TX path developed massive **bufferbloat**: Pi→QVR latency climbed 15 ms → 1.7 s → and a
Mac ping showed a textbook draining staircase (18 s → 0.5 s, ~1 s/step) with 36% loss.
QVR's stream stopped intermittently. *Not* the classic `brcmf_proto_bcdc_msg failed`
hang (so `wifi-reset.sh` wouldn't have caught it — and that script targets the old
wpa_supplicant setup anyway, not NetworkManager).

**Lesson on the Pi 3 bus myth:** WiFi is on **SDIO**, separate from USB. It's **Ethernet**
that shares the single USB 2.0 bus with the camera (LAN9514). So WiFi-only doesn't add
camera-USB contention — but the Broadcom WiFi's own throughput/latency under load is the
real problem.

**Self-inflicted lockout:** bounced the WiFi connection (to apply `powersave=2`) while
eth0 was `nmcli disconnect`ed → no fallback → WiFi hung → needed a physical power-cycle.
Always restore eth0 *before* touching WiFi. (`nmcli device disconnect` does not survive
reboot, so eth0 auto-returns at .51 on boot.)

Final state: **Ethernet primary** (.51, ~3 ms to QVR). WiFi left **dormant**
(`nmcli connection modify preconfigured connection.autoconnect no`; driver still loaded,
won't connect/interfere). To fully revert to firmware-disabled: re-add
`dtoverlay=disable-wifi` + reboot. QVR repointed back to **.51**.

### Housekeeping

Pruned publisher unit backups to a single `c920-publisher.service.bak`; kept
`mediamtx.yml.bak.20260619-184033`. WiFi-only proved unusable; `config.txt.bak.*` and
`*.focusfix.bak` left as rollback points.

---

## 2025-12-08 — RBPi3 Surveillance Setup, Part 2

## Background

As outlined in Development > Python > rbpi3-surveillance > dev-diary.md, I am using an old Raspberry Pi 3 as a dedicated surveillance camera streaming video using mjpg-streamer. This follows earlier work documented in Development > dev-diary > rbpi4-cctv.md, where I experimented with different approaches on the Pi 3 and 4.

The Raspberry Pi 3 has a long-standing and well-known issue:
its Broadcom WiFi chipset (brcmfmac) can silently hang, especially under sustained throughput or marginal signal strength. When it hangs once, it usually never reconnects on its own — even with power-saving disabled (```iw dev wlan0 set power_save off```). This makes it a poor candidate for unattended surveillance unless additional reliability measures are added.

## WiFi Reliability Fix

To work around this, I wrote a small recovery script that periodically checks the kernel log (dmesg) for specific Broadcom driver failures — in this case:

```brcmf_proto_bcdc_msg failed```

Whenever this signature appears, it indicates that the driver is stuck and the WiFi stack can no longer transmit or negotiate. The script then:
	1.	Brings down the WiFi interface
	2.	Stops the wpa_supplicant@wlan0.service instance
	3.	Repeatedly attempts to unload the brcmfmac module (with retry loops, since the kernel doesn’t always release it immediately)
	4.	Reloads the module
	5.	Restarts wpa_supplicant
	6.	Brings the interface back up

This entire flow is driven by a systemd service and scheduled via a systemd timer, which checks for failures every few minutes. The timer is lightweight and survives reboots cleanly. A journal namespace is used for logging so failures and recoveries can be reviewed later in a structured way.

This workaround effectively “revives” the Pi’s WiFi without requiring a full reboot, allowing the Pi 3 to function as a semi-reliable IP camera despite its hardware limitations.

### Systemd files
✅ File 1 — WiFi Reset Script

Path
```/usr/local/bin/wifi_reset.sh```

Permissions
```sudo chmod +x /usr/local/bin/wifi_reset.sh```

Content:

```
#!/bin/bash
set -euo pipefail

LOGTAG="wifi-reset"
IFACE="wlan0"

# Log helper
log() {
    logger -t $LOGTAG "$1"
}

# Check for the Broadcom hang signature
if ! dmesg | grep -qi "brcmf_proto_bcdc_msg failed"; then
    exit 0
fi

log "WiFi hang detected on $IFACE — restarting driver..."

# Bring interface down
ip link set "$IFACE" down || log "Failed to bring $IFACE down"

# Stop wpa_supplicant@wlan0 if running
if systemctl is-active --quiet "wpa_supplicant@$IFACE.service"; then
    log "Stopping wpa_supplicant@$IFACE"
    systemctl stop "wpa_supplicant@$IFACE.service"
fi

# Try unloading brcmfmac repeatedly
for i in {1..5}; do
    if modprobe -r brcmfmac 2>/dev/null; then
        log "Unloaded brcmfmac driver"
        break
    fi
    sleep 1
done

# Reload driver
modprobe brcmfmac && log "Reloaded brcmfmac driver"

# Restart wpa_supplicant
if systemctl start "wpa_supplicant@$IFACE.service"; then
    log "Started wpa_supplicant@$IFACE"
fi

# Bring interface back up
ip link set "$IFACE" up || log "Failed to bring $IFACE up"

log "WiFi recovery process completed"
exit 0
```

This logs everything to /var/log/syslog under the tag wifi-reset.

✅ File 2 — Systemd Service Unit:

Path
```/etc/systemd/system/wifi-reset.service```

Content

```
[Unit]
Description=WiFi driver recovery for Raspberry Pi 3
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wifi_reset.sh
Nice=10

[Install]
WantedBy=multi-user.target
```

✅ File 3 — Systemd Timer Unit:

Path
```/etc/systemd/system/wifi-reset.timer```

Content:
```
[Unit]
Description=Check for Raspberry Pi WiFi driver hangs every minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=10s
Unit=wifi-reset.service
Persistent=true

[Install]
WantedBy=timers.target
```

## Network Security Hardening

Because this Pi runs mjpg-streamer’s HTTP interface, I locked it down with UFW so it is only reachable from:
	•	Local LAN (192.168.1.0/24)
	•	Any device on my Tailscale network (100.64.0.0/10)

All other incoming traffic is denied.

Final ruleset:

```
192.168.1.0/24    ALLOW IN
100.64.0.0/10     ALLOW IN
Default: deny incoming, allow outgoing
```

This ensures the Pi is no longer exposed publicly and can only be accessed from trusted networks or authenticated Tailscale nodes, which significantly reduces the risk of unauthorized access.

## Summary

Summary

By combining:
	•	a custom WiFi recovery script
	•	systemd automation
	•	firewall lockdown with UFW

…this old Raspberry Pi 3 now functions as a stable and relatively secure camera node. While its hardware is limited and WiFi issues persist, the automated recovery mechanism and restricted access model make it viable for long-term surveillance use.