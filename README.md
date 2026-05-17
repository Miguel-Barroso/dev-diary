# dev-diary

A working notebook of the systems I build, break, and fix at home.

Self-taught developer notes from a decade of running things on my own hardware — NAS, mini PCs, Raspberry Pis, laptops, and one extremely opinionated ThinkPad. The entries are written as I go, so they're not polished tutorials. They're the record of decisions, dead ends, and the fixes that actually worked. If something here helps you skip a few hours of debugging, that's the point.

---

## Index

### Workstations
- [`macbook-pro-m4.md`](macbook-pro-m4.md) — Flutter dev environment with FVM, debugging a 500 ms VPN-induced latency issue on macOS, VSCodium autocomplete recovery
- [`x1e-pop-os.md`](x1e-pop-os.md) — ThinkPad X1 Extreme on Pop!_OS: PIA and Tailscale coexistence, UFW hardening, fixing slow `sudo`, systemd-automounted NAS shares over Tailscale

### Self-hosted infrastructure
- [`qnapbox66.md`](qnapbox66.md) — Vaultwarden on a QNAP NAS with Caddy reverse proxy, Cloudflare DNS-01 certificates, and the hardening pass that came after I caught myself doing something dumb with secrets
- [`macmini-2012-log.md`](macmini-2012-log.md) — 2012 Mac Mini repurposed as a 24/7 cat-café livestream host and network-wide AdGuard DNS server, with OBS hardware encoding and AdGuard DHCP takeover

### Raspberry Pi
- [`rbpi3-log.md`](rbpi3-log.md) — Pi 3 surveillance camera with a custom systemd-driven recovery script that revives the Broadcom WiFi chip when it hangs
- [`rbpi4-catcam.md`](rbpi4-catcam.md) — Pi 4 with a USB webcam streaming MJPEG, captured into OBS via XComposite Window Capture for a public cat livestream
- [`rbpi4-cctv.md`](rbpi4-cctv.md) — migrating mjpg-streamer from Pi 3 to Pi 4, plus an FFmpeg-to-RTMP relay path

### Web and games
- [`miguelbarroso.com.md`](miguelbarroso.com.md) — `fswatch` and `rsync` continuous sync to a SiteGround WordPress install, and why I eventually abandoned the approach
- [`nekocafetime.com.md`](nekocafetime.com.md) — WooCommerce and WPML variation-translation troubleshooting
- [`astromeda-log.md`](astromeda-log.md) — running multiple Minecraft Bedrock servers in Docker on Windows, with automated backups via Task Scheduler

---

## How to read this

Entries are dated where it mattered to me at the time. Some are stream-of-consciousness, some are clean step-by-step writeups. Treat them as a journal, not a manual.

Everything that needs a real credential, real internal IP, or real account identifier has been redacted with angle-bracketed placeholders like `<YOUR_PASSWORD>` or `<pi-lan-ip>`. If you spot something I missed, please open an issue.
