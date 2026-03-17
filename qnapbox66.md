# QNAP NAS — Vaultwarden Self-Hosted Password Manager

**Date:** 2026-03-17
**Host:** QNAP TS-453 Pro (qnapbox66)
**Status:** ✅ Running

---

## Background

1Password was getting too expensive for personal use. The core features needed were:

- Sync across multiple devices (Android, macOS, Windows)
- Password sharing with wife (shared business credentials)
- TOTP/2FA code generation inside the password manager
- Reliable backup and redundancy

After researching open source alternatives, **Vaultwarden** was chosen — a lightweight, unofficial Bitwarden-compatible server written in Rust. It is self-hostable, unlocks all premium features (including TOTP) for free, and the official Bitwarden clients connect to it seamlessly.

The QNAP TS-453 Pro was the natural choice for hosting due to its RAID 10 configuration, providing both redundancy and good read performance. Data is stored on the main volume at `/share/CE_CACHEDEV1_DATA`.

---

## Architecture

```
Devices (Android / macOS / Windows)
          ↓ Tailscale (WireGuard encrypted)
QNAP TS-453 Pro — Container Station
  ├── vaultwarden   (Vaultwarden server, port 80 internally)
  └── caddy         (Reverse proxy + SSL termination, port 443)
          ↓ DNS-01 challenge (no public exposure needed)
    vault.miguelbarroso.com  →  QNAP Tailscale IP
```

The QNAP firewall only allows LAN and Tailscale connections — no public internet exposure. SSL is handled via Let's Encrypt DNS-01 challenge through the Cloudflare API, meaning the server never needs to be publicly reachable to obtain or renew certificates.

---

## Prerequisites

- QNAP NAS with Container Station installed
- Tailscale installed and running on the QNAP
- Domain managed by Cloudflare (in this case `miguelbarroso.com`)
- SSH access to the QNAP

---

## Step 1 — Cloudflare: Create API Token

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Go to **My Profile → API Tokens → Create Token**
3. Use the **"Edit zone DNS"** template
4. Scope it to `miguelbarroso.com` only
5. Save the token securely — you will need it in the compose file

---

## Step 2 — Cloudflare: Add DNS Record

1. Go to your domain in the Cloudflare dashboard
2. Navigate to **DNS → Records → Add record**
3. Add an **A record**:
   - Name: `vault`
   - Value: your QNAP's Tailscale IP (e.g. `100.x.x.x`)
   - Proxy: **DNS only** (grey cloud — do NOT proxy, Cloudflare cannot proxy a Tailscale IP)

---

## Step 3 — QNAP: Create Directory Structure

SSH into the QNAP and create the required directories and Caddyfile:

```bash
ssh admin@<qnap-lan-ip>

mkdir -p /share/CE_CACHEDEV1_DATA/vaultwarden/data
mkdir -p /share/CE_CACHEDEV1_DATA/vaultwarden/caddy/data

cat > /share/CE_CACHEDEV1_DATA/vaultwarden/caddy/Caddyfile << 'EOF'
vault.miguelbarroso.com {
    reverse_proxy vaultwarden:80
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
}
EOF
```

Verify the Caddyfile:

```bash
cat /share/CE_CACHEDEV1_DATA/vaultwarden/caddy/Caddyfile
```

---

## Step 4 — Container Station: Deploy the Application

1. Open **Container Station** in the QNAP web UI
2. Click **Create → Create Application**
3. Paste the following docker-compose YAML, replacing `your_cf_token_here` with your actual Cloudflare API token:

```yaml
version: '3'

services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    volumes:
      - /share/CE_CACHEDEV1_DATA/vaultwarden/data:/data
    environment:
      - DOMAIN=https://vault.miguelbarroso.com
      - SIGNUPS_ALLOWED=true
    restart: unless-stopped

  caddy:
    image: serfriz/caddy-cloudflare:latest
    container_name: caddy
    dns:
      - 1.1.1.1
      - 8.8.8.8
    ports:
      - "443:443"
    volumes:
      - /share/CE_CACHEDEV1_DATA/vaultwarden/caddy/Caddyfile:/etc/caddy/Caddyfile
      - /share/CE_CACHEDEV1_DATA/vaultwarden/caddy/data:/data
    environment:
      - CLOUDFLARE_API_TOKEN=your_cf_token_here
    depends_on:
      - vaultwarden
    restart: unless-stopped
```

> **Note:** The explicit `dns` entries (1.1.1.1 / 8.8.8.8) on the caddy service are required because QNAP's internal Docker DNS resolver does not reliably resolve external hostnames inside containers, which would otherwise prevent Caddy from reaching Let's Encrypt.

4. Click **Deploy** and watch the logs. Caddy will perform the DNS-01 challenge and obtain a Let's Encrypt certificate automatically. Look for:

```
certificate obtained successfully — identifier: vault.miguelbarroso.com
```

This typically takes 30–60 seconds.

---

## Step 5 — Initial Vaultwarden Setup

1. Open `https://vault.miguelbarroso.com` from any Tailscale-connected device
2. Create your admin account
3. Create your wife's account
4. Once both accounts exist, **lock down signups** by editing the compose YAML and setting:
   ```
   SIGNUPS_ALLOWED=false
   ```
   Then redeploy the application.

---

## Step 6 — Sharing Setup (Organization)

To share a subset of passwords (e.g. business credentials):

1. In the Vaultwarden web vault, go to **Organizations → New Organisation**
2. Create the organisation (free on Vaultwarden, no limits)
3. Invite your wife via her email
4. Create a **Collection** inside the organisation for shared passwords
5. Move relevant items into the shared collection

Both users keep their own private vaults and additionally have access to the shared collection.

---

## Step 7 — Import from 1Password

1. In 1Password, go to **File → Export** and export as `.1pux` format
2. In the Vaultwarden web vault, go to **Tools → Import Data**
3. Select **1Password (1pux)** as the format
4. Upload the file — all items, folders, and structure are preserved

---

## Step 8 — TOTP / 2FA

Since Vaultwarden unlocks all premium features, TOTP generation is available natively in the Bitwarden clients. To add a TOTP code to a login item:

1. Edit the item in the vault
2. Paste the TOTP secret (or scan the QR code in the mobile app)
3. The client will generate rotating 6-digit codes automatically

---

## Notes

- **Backups:** Vaultwarden data lives at `/share/CE_CACHEDEV1_DATA/vaultwarden/data`. Include this path in your regular QNAP backup job. The RAID 10 array provides hardware redundancy but is not a substitute for backups.
- **Certificate renewal:** Caddy renews the Let's Encrypt certificate automatically before expiry. No manual action needed.
- **Tailscale dependency:** The vault is only reachable over Tailscale. Ensure Tailscale is running on all client devices before expecting access.
- **Container Station edits:** The GUI does not allow editing the YAML after deployment. To make changes, delete the application and recreate it with the updated YAML. Vaultwarden data persists on disk and is unaffected by container recreation.
