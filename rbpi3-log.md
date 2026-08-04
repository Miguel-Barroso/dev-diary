# RBPi3 Surveillance — Consolidated Dev Diary

> Single source of truth for the rbpi3 + Logitech C920 surveillance camera (→ QVR Pro NVR).
> Consolidated 2026-06-21 from `dev-diary/rbpi3-log.md` and `Python/rbpi3-surveillance/dev-diary.md`. Newest entries first.

---

## 2026-06-21 — Full circle: H.264/MediaMTX → mjpg-streamer (MJPEG over HTTP)

### Symptom
QVR Pro showed a "sea of pixels" / macroblock storms on any movement — moving people/animals became impossible to identify, defeating the camera's purpose.

### Root cause
The `c920-publisher` ffmpeg config had drifted from the documented 2.5 Mbps to **4.5/6 Mbps** (`-b:v 4500k -maxrate 6000k -bufsize 9000k`). On a hot day that pushed the Pi3 to **82 °C and thermal-throttled the ARM clock** → libx264 couldn't keep up → frames delivered in bursts → QVR rendered the storms. Not a bandwidth/transport problem (link is wired, RTSP/TCP). Reverting bitrate to 2.5 Mbps cleared the throttle, **but H.264 still stormed on motion** — inter-frame compression at any Pi3-sustainable bitrate (≤2.5M; higher throttles) coarsely quantises motion residuals. The storms are intrinsic to H.264 here.

### Options explored (and why rejected)
- **MJPEG-in → H.264 re-encode** (A/B tested): *more* CPU (222% vs 172% of a core) — MJPEG decode is heavier than H.264 decode (bigger payload) — and still H.264 out ⇒ still storms. Wrong axis.
- **GStreamer HW pipeline** (HW decode+encode): the encoder `/dev/video11` *does* expose the QVR-critical controls (`h264_profile=1` Constrained Baseline, `repeat_sequence_header`, `h264_i_frame_period`) that ffmpeg's `h264_v4l2m2m` wrapper can't set — would need GStreamer `v4l2h264enc extra-controls`. Not pursued: still H.264 = still storms; big rewrite + re-opens QVR validation.
- **MJPEG passthrough over RTSP** (`-c:v copy` + AAC → MediaMTX): low CPU (25%, 68 °C) but the stream is **broken** — RTP/JPEG (RFC 2435) can't carry the C920's native JPEG (MediaMTX logged thousands of "received wrong fragment"); QVR blank.
- **MJPEG re-encode over RTSP** (`-c:v mjpeg`): packetises cleanly (MediaMTX serves M-JPEG + AAC) but costs ~2 cores (194%) and **QVR still rejects MJPEG-over-RTSP** (`unspecified size` — no SDP dimensions). QVR blank.

### Decisions / hard constraints learned
- **QVR ingests MJPEG only over HTTP** (mjpg-streamer), never RTSP.
- ∴ **MJPEG + audio is impossible with QVR** (HTTP-MJPEG carries no audio; audio only lived on the H.264/RTSP path). Chose **storm-free video over audio**.
- Went **full circle** to the original 2025-07 architecture: C920 hardware-JPEG **passthrough → mjpg-streamer `output_http` :8080 → QVR over HTTP**.

### Final state (verified)
- `mjpg-streamer.service` (new): `input_uvc.so -d /dev/video0 -r 864x480 -f 15` → `output_http.so -p 8080`. HW-JPEG passthrough, intra-only ⇒ **no pixel storms**. Focus-pinning (`focus_absolute=0` = infinity) carried over via `ExecStartPost`.
- **CPU ~1.4% (mjpg-streamer); ~65 °C; full 1200 MHz; load <1** (was 82 °C throttling).
- QVR source URL: `http://192.168.1.51:8080/?action=stream`.
- `pi-motion-detect.service`: repointed to the HTTP stream (`start_ffmpeg` made scheme-aware — `-f mpjpeg` for http, `-rtsp_transport tcp` for rtsp). **QVR motion events still wired** (`QVR_PRO_EVENT_URL` unchanged). Its leftover `Wants=/After=c920-publisher` (which *resurrected* the dead H.264 stack on restart) was fixed to depend on `mjpg-streamer`.
- **Removed the H.264 stack as bloat**: `c920-publisher.service` + its README, **MediaMTX** (59 MB binary + `/etc/mediamtx` + unit), the dead `snapshot-stream.service`, and all `*.bak`/scratch leftovers. Full H.264 rebuild recipe is preserved in the **2026-06-19** entry below.

### Known TODO / notes
- mjpg-streamer HTTP has **no auth** now (relies on UFW LAN+Tailscale). Original used `-c user:pass`; add if exposing wider.
- MJPEG storage on QVR is ~10–16× H.264 — lean on **motion-event recording** (what `pi-motion-detect` feeds).
- The motion-detect reader decodes the full 720p stream to make 320×180@2fps (~0.5 core); trimmable by polling `?action=snapshot` instead — fps can't be lowered (see addendum).

### Addendum (2026-06-21, later) — fps hardware-locked; powerline bufferbloat

- **C920 fps is stuck at ~15 fps for 720p MJPG.** Requesting 10 fps (mjpg-streamer `-f 10` / v4l2 `--set-parm=10`) is *accepted by the driver* (`--get-parm` reports `10.000`) but the **camera delivers ~15 fps regardless** — so **fps is not a usable bitrate lever**; resolution is the only one. Config set to `-f 15` to match reality.
- **QVR switched to motion-event recording only** (continuous retired now the on-Pi detector triggers events) → saves QNAP **disk**. Does *not* cut network load: QVR pulls the stream continuously, so ~30 Mbps flows 24/7 regardless of disk mode.
- **Powerline is the bottleneck (measured).** Path: Pi (100 M eth) → HomePlug → mains → HomePlug → eth → TS-453 Pro (QVR records *here*; stream never reaches the RBR50 / WiFi / internet, barring remote viewing). Ping Pi→QNAP: **idle 1.3/2.9/6.1 ms; under the 30 Mbps stream 115/258/443 ms, 90 ms jitter, 0% loss** — the stream **saturates the powerline ⇒ ~255 ms bufferbloat (~90×)**. No loss (QVR records fine) but it monopolises that segment with zero headroom (a powerline dip would stutter the stream).
- **Resolution is a weak lever — the C920 fills a ~fixed USB budget by varying fps** (measured): 720p→15 fps→30 Mbps (saturates, **258 ms** ping); 960×540→24 fps→29.4 Mbps (at the knee, 18 ms); **864×480→25 fps→24.7 Mbps→~3 ms** (idle-level, full headroom). Powerline knee ≈ 28–30 Mbps; bufferbloat is sharply nonlinear right there.
- **Chosen: 864×480** (`-r 864x480 -f 15`; camera actually delivers ~25 fps — fps is uncontrollable). Highest res that sits well under the powerline knee. ID trade-off: less resolution, more (unneeded) fps. To go lower: 640×360 ≈ 10–12 Mbps. To keep 720p: fix the powerline (AV2 adapters / better outlet — avoid power strips & distant circuits / real ethernet / MoCA).
- **The powerline is shared** — it also carries the **D-Link DCS-932L** cam and the **RBS20 Orbi satellite's WiFi backhaul** (serves the *kura*). So keeping this cam light protects kura WiFi + the other cam, not just the Pi. The measured 3 ms already includes the D-Link (always on); the only variable is kura WiFi when occupied (infrequent). This is *why* we hold ~25 Mbps instead of maxing the line — and why bumping to 720p was rejected even though it wouldn't touch the RBR50/main-LAN side. If kura WiFi ever lags while in use, drop this cam to 640×360 (~10–12 Mbps) for more headroom.

---
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
static .50**, eth0 .51. Access is over **Tailscale** (`<pi3-tailnet-ip>`, per-node, so it
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

---

# Earlier history — originally Python/rbpi3-surveillance/dev-diary.md

# 2025-07-04 RBPi3 Surveillance Setup

## Background  
I had an old Raspberry Pi 3 B and a Logitech C920 USB webcam lying around, and wanted a cheap headless surveillance solution. Unfortunately, the Pi 3’s single USB-OTG bus (which it shares between the four USB ports and Ethernet/Wi-Fi) chokes when you try to push a high-bitrate H.264 or MJPEG RTSP stream in real time — even at modest resolutions like 320 × 240@10 fps the kernel logs would show `dwc2_hc_halt() channel can’t be halted` and the camera would disconnect entirely (see ```sudo dmseg -w```).

Watching the same device locally under Raspbian (via VLC’s “Capture Device”) worked fine in full-HD, so I realized that continuous streaming was the problem. Instead, I needed to:

1. **Snapshot** frames at a controlled rate (≤ 25 fps)  
2. **Serve** them as a simple MJPEG HTTP stream with minimal buffering  

## Troubleshooting Attempts

- **v4l2rtspserver** (MJPEG / H.264) → green artifacts, dropped frames, USB bus resets  
- **ffmpeg / cvlc** pipelines → frequent resets, unsupported/YUYV codec errors, panics  
- **Alternative OS (Ubuntu 24.04)** → same USB bus faults under load  
- **Unplug peripherals** (headless) → no improvement  

## Final Solution: Flask + OpenCV MJPEG Snapshots
Approach: Instead of a continuous video stream, capture single JPEG frames at up to 25 fps and serve them as an MJPEG HTTP stream.

Built a tiny **Flask + OpenCV** snapshot server:

- **Auto-detect** first working `/dev/video*`  
- **Cap OpenCV buffer** to 1 frame → minimal latency  
- **JPEG encode** at configurable quality (default 30)  
- **Limit FPS** (default 25) via `time.sleep()`  
- **Stream over HTTP** as `multipart/x-mixed-replace` → ingestible by VLC, QVR Pro, web browsers, etc.  
- **Systemd service** for auto-start, restart on failure, headless operation  
- **Remote access** via Tailscale + SSH

Script: /usr/local/bin/snapshot_stream.py supports these CLI arguments:
```
--host: bind address (default 0.0.0.0)

--port: HTTP port (default 8080)

--fps: target frames per second (capped to avoid bus overload)

--quality: JPEG quality (e.g. 30–50)

snapshot_stream.py --host 0.0.0.0 --port 8080 --fps 25 --quality 30
```

### Repo Layout
```
rbpi3-surveillance/
├── snapshot_stream.py        # main Flask/OpenCV MJPEG streamer
├── requirements.txt          # Flask, opencv-python
├── snapshot-stream.service   # systemd unit (auto-restart, 1 sec delay)
├── README.md                 # install & usage instructions
└── LICENSE                   # GNU GPL v3
```

### Key Script Features

```python
#!/usr/bin/env python3
"""
snapshot_stream.py

- Finds & opens first UVC camera (/dev/video*).
- Serves `http://<pi>:8080/stream` as low-latency MJPEG.
- Args: --host, --port, --fps, --quality, --buffersize.
"""
import glob, time, signal, sys, argparse, logging, cv2
from flask import Flask, Response

# …[see full script in repo]…

Args:

    --fps 25 (max)

    --quality 30 (JPEG)

    --buffersize 1 (OpenCV CAP_PROP_BUFFERSIZE)

Logging for startup & frame-read failures

Graceful shutdown on SIGINT/SIGTERM
```

### Systemd Unit (snapshot-stream.service)

Auto-restarts on failure with a 1 s delay

Hardcodes default port 8080, but you can change it via ExecStart arguments or an EnvironmentFile

```bash
[Unit]
Description=MJPEG Snapshot Streamer
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/snapshot_stream.py \
    --host 0.0.0.0 --port 8080 --fps 25 --quality 30
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
```

Change to port 9090:
```bash
ExecStart=/usr/local/bin/snapshot_stream.py \
    --host 0.0.0.0 --port 9090 --fps 25 --quality 30
```


### Usage
```bash
sudo apt update
sudo apt install python3-opencv python3-flask
pip3 install -r requirements.txt
```

```bash
sudo cp snapshot_stream.py /usr/local/bin/
sudo cp snapshot-stream.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now snapshot-stream
```
Stream URL: http://192.168.1.50:8080/stream <-- Your RBPi's IP or Tailscale

Ingestors tested: VLC (desktop & mobile), QVR Pro (QNAP), web browsers

### Results

- Stable 640 × 480 JPEG stream at 25 fps

- No USB bus panics under sustained load

- Low CPU usage (~10–15 %), no audio

- Headless + remote management via Tailscale/SSH

### Lessons learned:

When the USB-OTG bus can’t handle a real-time encode & transport pipeline, switch to a snapshot-based MJPEG server.

Simple HTTP multipart streams can be surprisingly robust on constrained hardware.

A minimal Flask + OpenCV service is easier to tune & debug than full-blown RTSP or FFmpeg pipelines.

# Update 2025-07-05: Simplified Workflow
## Background

Why reinvent the wheel when the solution already exists?
I discovered that pure MJPEG frame capture and restreaming is a well-established approach. This is exactly how OctoPi manages to run smoothly on an RPi3 with a USB camera. It’s not “streaming” in the modern sense, but this is how webcams worked back in the day. Fun fact: one of the very first Internet use cases was watching a coffee pot drip!

## MJPG-Streamer

First, install the mjpeg-streamer-experimental fork, which works well with Raspberry Pi:

```git clone https://github.com/jacksonliam/mjpg-streamer.git```

You’ll also need the following libraries and cmake:

```apt install -y git build-essential libjpeg-dev libv4l-dev cmake```

Then build and install:

```
cd mjpg-streamer/mjpg-streamer-experimental
make
make install
```

Find your device ID (usually ```/dev/video0```). Then run mjpg_streamer to capture MJPEG frames. You can control the frame rate with ```-f``` and resolution with ```-r```.

Example:
```
mjpg_streamer \
  -i "input_uvc.so -d /dev/video0 -r 1280x720 -f 20 -q 80" \
  -o "output_http.so -w /usr/local/share/mjpg-streamer/www -p 8080"
```
Make sure port ***8080*** is available.

## Systemd Service

Create ```/etc/systemd/system/mjpg-streamer.service```:

```
[Unit]
Description=MJPG-Streamer webcam service
After=network.target

[Service]
# Make sure we respawn on crash
Restart=always
RestartSec=1

# Run as your mjpg-streamer user (replace 'pi' if different)
User=********
Group=********

# Point to the installed binaries & plugins
ExecStart=/usr/local/bin/mjpg_streamer \
  -i "input_uvc.so -d /dev/video0 -r 1280x720 -f 20" \
  -o "output_http.so -p 8080 -w /usr/local/share/mjpg-streamer/www -c admin:****************"

# Log to journal
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Then reload systemd and enable the service:

```
systemctl daemon-reload
systemctl enable mjpg-streamer
```

Check status and logs:

```systemctl status mjpg-streamer.service```

If you make changes, restart the service:
```systemctl restart mjpg-streamer```

## Summary

You now have a perpetually running service that captures JPEG frames from any webcam—even on low-powered devices like the Raspberry Pi 3—and serves them over the network. This simulates “modern” webcam streaming using simple, lightweight tools.

In other words: you can do this today with hardware you already have—no need to buy a CCTV system!

## SSH alias, and a box that stopped answering (2026-07-28)

Tidying the Mac's SSH config, this Pi's entry now answers to `cctv` as well as `raspberrypi3`, so the
alias says what the machine does rather than which board it happens to be. The old name still works —
both are on the same `Host` line — so nothing that already referenced it needs changing.

Open, and not a config problem: **this Pi has been off the tailnet for two days.** Tailscale reports
it last seen 07-26, and the address in the config is confirmed correct, so it isn't a routing or key
issue. Given the history in this log — the Broadcom WiFi chip on this board wedging hard enough to
need the recovery script — the likely candidates are that same wedge with the watchdog not catching
it, or power. Needs hands on the hardware, so it's noted here rather than solved.

## 2026-08-03 — Deleting the debris from a decision I'd already made

The box answers again, and I never established which of the two candidates above it was, so I'm not
going to pretend otherwise here. What follows is from the tidy-up afterwards, which turned out to be
the more useful half.

### What was still on the box

This Pi ran an RTSP stack for a while, and I ripped it out in June after it lost on grounds that had
nothing to do with configuration. Except I didn't rip it out. What was still there:

- **`v4l2rtspserver`, installed via dpkg.** Disabled and not listening — but installed, with a
  systemd override that had been *tuned*: explicit port, codec, resolution, framerate, device.
- A firewall rule holding its port open, on two interfaces, with a helpful comment.
- The motion-detection script's default stream URL, still `rtsp://…`.
- An ALSA alias in `/etc/asound.conf` that existed for exactly one reason: that server's device
  parser chokes on the comma in `hw:CARD,DEV`, so the device needed an alias with no comma in it.
  Nothing else on the box had ever referenced it. The current feed is MJPEG and carries no audio.
- A source tree and the `.deb` in the home directory, and a settings file on the desktop.

None of it was running. All of it read as a working setup that someone had merely forgotten to switch
on — one `systemctl enable` from live.

### The actual lesson: an artefact proves something was *tried*

I know it doesn't work here, because I'm the one who found out. And I still fell for it — twice, in
my own notes, which by this point had a paragraph pointing at the firewall rule and the `rtsp://`
default as evidence that "this box has been configured that way before", and recommending going back
to it. Both of those files now carry a retraction rather than a silent edit, because the wrong
reasoning is worth having visible next to the right one.

**The strength of the leftover is not evidence about the decision.** If anything it's the reverse:
nobody tunes a thing that never ran at all, so the most convincing debris collects exactly where a
hard problem was fought and lost. Which is the same place a fresh reader — including you, six weeks
later — is most likely to propose fighting it again. Before reading intent into a leftover file, two
questions settle it: is it actually *running*, and does anything say why it stopped?

So: when a decision closes, delete its debris in the same change. That's not tidiness, it's what
stops the next person re-deriving the wrong answer. History goes in a **dated archive directory**,
never as a stray `.bak` beside the live file — I found one of those sitting in `/etc/default/` still
holding the old `rtsp://` value, which is precisely the thing a future grep reads as current.
Live-config-versus-dated-archive is the distinction that matters, not whether a file mentions the
dead technology.

### Two gotchas from renaming the config key

The misleading key was `RTSP_URL`, in the script's defaults and in `/etc/default/`. Renaming it to
`STREAM_URL` is a two-line change with two ways to go quietly wrong.

**Rename both sides in the same change.** The script merges the env file over its defaults with
`if key in cfg` — so an unrecognised key in the env file isn't an error, it's ignored, and the
built-in default silently wins. Rename one side only and you get a service that starts, reports
healthy, and streams from the wrong URL.

**Don't tighten that file to `600 root:root` while you're in there.** It looks like an obvious
hardening win, and it isn't: the script opens the file *itself*, as its own service account, not only
via systemd's `EnvironmentFile=`. Under `600 root:root` it crashlooped on `PermissionError` — and
`systemctl is-active` still said `active` the whole time, because between restarts it genuinely is.
Group-read for the service account is what it needs.

Which generalises: for a service whose real work is done by a child process, **verify by the child,
not by the unit.** Here that means checking there's an `ffmpeg` under the main PID, and glancing at
`NRestarts`. `active` on its own tells you almost nothing.