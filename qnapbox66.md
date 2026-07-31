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
3. Paste the following docker-compose YAML, replacing `your_cf_token_here` with your actual Cloudflare API token.

> ⚠️ **This is the original deployment as it happened — kept as a faithful record.** The token sitting inline in the compose YAML is exactly the anti-pattern I had to fix two months later. See the **"Caddy Failure, Cloudflare Token Cleanup, and Container Hardening"** entry further down for how I moved the token into an `.env` file. If you're following this guide today, jump to that section first and use `env_file` from the start.

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

## Backup

Vaultwarden data is located at `/share/CE_CACHEDEV1_DATA/vaultwarden/data` and contains:

- `db.sqlite3` — the entire vault database
- `rsa_key.pem` / `rsa_key.pub.pem` — the server key pair
- `config.json` — admin panel configuration (if modified)

A QNAP shared folder was created pointing to `/share/CE_CACHEDEV1_DATA/vaultwarden` making it visible to QNAP backup tools. It has been added to the main backup job in Hybrid Backup Sync.

The Caddy data at `/share/CE_CACHEDEV1_DATA/vaultwarden/caddy/data` contains the SSL certificate but does not need to be backed up — Caddy will re-obtain it automatically from Let's Encrypt if lost.

# Dev Diary — Caddy Failure, Cloudflare Token Cleanup, and Container Hardening

## Date
2026-05-15

## Context
A Vaultwarden setup behind a Caddy reverse proxy on a QNAP NAS started behaving unexpectedly: Caddy was repeatedly stopping and failing to restart properly. This broke HTTPS access to the service and required investigation into both container behavior and TLS configuration.

---

## Initial Symptom

Caddy was in a restart loop or failing to stay up consistently. Logs indicated repeated startup attempts without stable operation.

At first glance, this looked like a runtime or configuration issue inside Caddy itself.

---

## Investigation

During troubleshooting, the following key issues were identified:

### 1. Cloudflare API token exposed in plain text

The Cloudflare API token used for DNS-01 challenge authentication was found directly inside the `docker-compose.yml` file.

This presented two problems:
- Security risk (secret stored in plaintext in versioned config)
- Poor secret management practice

---

## Remediation — Secret Rotation

Once the exposure was identified:

- The existing Cloudflare API token was **revoked (rotated)**
- A new token was generated
- The new token was moved into a `.env` file instead of being stored in the compose file

This ensured:
- No secrets stored in version control or static YAML
- Better separation of configuration and credentials

---

## Docker Compose Updates

The `docker-compose.yml` was updated with several improvements:

### 1. Removed inline secret usage
- Cloudflare token removed from service definition
- Replaced with `env_file: .env`

### 2. Added proper port exposure for Caddy

```yaml
ports:
  - "80:80"
  - "443:443"
```

This ensured:

* HTTP traffic properly handled for redirects / ACME validation
* Standard TLS + HTTP accessibility

3. Added restart policy
```restart: unless-stopped```

This improved resilience so that:

* Caddy automatically recovers after reboots or crashes
* Manual intervention is not required for service restoration

Caddy Configuration Update

The Caddyfile was updated to correctly reference the environment variable:

```
tls {
    dns cloudflare {env.CF_API_TOKEN}
}
```

This ensured:

* Cloudflare DNS challenge uses injected runtime secret
* No hardcoded credentials in configuration files

Result After Fixes

After applying the changes and recreating the stack:

* Caddy started reliably
* No more restart loops
* Cloudflare DNS authentication succeeded
* TLS certificates were issued automatically
* Vaultwarden became reachable via HTTPS again

⸻

Key Learnings

* Never store API tokens directly in docker-compose.yml
* Secrets must be rotated immediately if exposed, even in local environments
* Docker Compose environment changes require full container recreation
* Caddy DNS-01 Cloudflare integration depends strictly on runtime env injection
* Basic hardening (restart policies + proper port mapping) significantly improves stability

⸻

Final State

✔ Secrets rotated and secured
✔ Cloudflare token moved to .env
✔ Caddy properly configured with env injection
✔ Restart policy added for resilience
✔ HTTP/HTTPS ports correctly exposed
✔ Vaultwarden accessible via secure HTTPS

⸻

# The off-site pull key, and how wide it reaches (2026-07-28)

Context: Vaultwarden itself moved off this box to Netcup back on 06-30. What the QNAP does now is
hold the off-site copy of the estate — it pulls from Netcup over SSH on a cron.

While splitting up SSH keys on the Netcup side, I edited that box's `authorized_keys`, which meant
proving this machine could still reach it afterwards.

## An error that looks like a failure and isn't

Testing the pull key interactively returns:

```
rrsync error: SSH_ORIGINAL_COMMAND does not rsync
```

That is the key working exactly as intended. It's restricted with a forced `rrsync` command, so it
refuses interactive shells by design. A real authentication failure says `Permission denied
(publickey)` instead. Worth knowing which is which before assuming the backups are broken.

To actually prove the path I ran a read-only `rsync --list-only` over the key, which returned a real
file listing from Netcup. That's the test that means something — the same lesson as the `--dry-run`
trap that nearly had me file a broken backup leg as healthy.

## What the listing showed

Two things, both queued as work rather than fixed in this sitting — see the resolution note below,
which is why they're written up at all:

1. **The rrsync root is the whole home directory.** The listing includes `.bash_history`, `.bashrc`,
   `.profile` — none of which are backups. The key only needs the backup trees. Narrowing it is the
   same least-privilege move as splitting the keys was, and it carries a specific risk: too narrow a
   root breaks the pull *silently* on the next cron run rather than failing at change time, so every
   path the pull touches (including the Vaultwarden leg) has to be enumerated and dry-run first.

2. **A 6.3 GB `neko-uploads-pre-ewww-*.tar` from 06-24 sits inside that root**, so it's standing on
   both sides of the mirror. The EWWW rollout it predates completed on 07-10 and has been stable
   since, so it's very probably obsolete — but the pull mirrors with `--delete`, which means removing
   it at the source also removes the only off-site copy. That's a decision to make deliberately, not
   a side effect to discover later.

> 💡 **Resolved 07-30, before this entry went public.** Both items above are closed. Each leg of the
> pull now has its own key jailed to its own rrsync root — one for the site backups, one for the
> vault — instead of the two of them sharing the home directory. That also settles item 2 as a
> security question: the rollback tar sits outside both roots now, so the pull key can't see it at
> all. Whether to delete the tar is still open, but it's a housekeeping call about disk, not an
> exposure. Writing up an open hole on a public repo is the thing to avoid; writing up a closed one
> is the point of keeping the diary.

Key and env file remain under `/share/...`, not `/root` — see the 07-28 entry in `netcup.md` for why
that rule exists and what it cost to learn.

---

# Key-only SSH, and the second password door I didn't know was open (2026-07-31)

The house edge is sealed — no forwards, nothing answering from outside — so everything I can reach, I
reach over the Tailscale mesh instead. Which means the mesh *is* the attack surface now, and a
personal tailnet defaults to **allow-all**: every device can reach every other device on every port.
This NAS holds the off-site copy of everything, so it's the box with the most to lose in that picture.

Two changes, deliberately in this order: key-only SSH first, because it's independently revertible,
and the mesh access policy last, so a failure is never two changes deep.

## `PermitRootLogin no` would have locked me out of the box

The obvious hardening line is the wrong one here. On QTS the `admin` account **is uid 0** — `id`
returns `uid=0(admin) gid=0(administrators)` — and it's the only account sshd will accept. So
`PermitRootLogin no` doesn't remove *root* login, it removes *all* login, and it removes it from the
box you'd need to log into in order to undo it.

The pair that actually does the job:

```
PermitRootLogin prohibit-password      # key allowed, password refused
PasswordAuthentication no
```

## The part I got wrong, and only caught by asking the server

With both lines in and sshd reloaded, I checked it the way that's worth checking — from a **new**
connection, with the client forbidden from using a key, so the server has to say what else it will
take:

```bash
ssh -vv -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=0 <host> true
```

```
debug1: Authentications that can continue: publickey,keyboard-interactive
```

Still a password door open. `keyboard-interactive` is the PAM path, and it carries a password just as
well as the one I'd just shut. It's a **separate directive**:

```
KbdInteractiveAuthentication no
```

The Pop!_OS box I hardened in the same sitting needed only `PasswordAuthentication no` — but purely
because its shipped `sshd_config` already set the kbd-interactive line, which I'd never have noticed
if I hadn't run the same check on both. **Nothing in either file tells you which default you're
getting.** That's the lesson worth keeping: reading the config tells you what you wrote, not what the
server accepts. Ask the server. Both boxes now answer:

```
debug1: Authentications that can continue: publickey
```

A related thing that can't be tested from the server side at all: whether some client out there still
logs in *with* a password. sshd can tell you what it would accept; it cannot tell you what a client
*would have* offered. That question only has a human answer, and getting it wrong means finding out
when something breaks.

## Editing sshd on a box whose only door is sshd

The risk here isn't the config being wrong, it's the config being wrong *and* taking away the means to
fix it. So the change went in behind a dead-man's switch: a backgrounded script that sleeps, and then
restores the backup and reloads sshd **unless** a fresh session has touched a flag file first.

```sh
setsid sh -c 'sleep 180; [ -f /tmp/ok ] && exit 0; cp -a "$CFG.bak" "$CFG"; kill -HUP <sshd-pid>' &
```

Open a new connection, confirm it works, touch the flag, kill the sleeper. If instead I'd locked
myself out, the box would have quietly undone it three minutes later. It never fired, but it's the
difference between a mistake and an outage that needs physical access.

Reload was `kill -HUP` on the sshd master rather than restarting the service — sshd re-execs and
rereads its config without touching sessions that are already established, so the session I was
sitting in was never at risk. QTS's `login.sh` restarts more than sshd, so HUP is the smaller hammer.

Two QNAP-specific notes for anyone doing the same: `nohup` and `timeout` **don't exist** in that
shell, so `setsid` and a manual kill are the way. Entware fills most of the other gaps.

## Persistence on QTS is better than I'd assumed

I'd written this box off as one where `/root` doesn't survive a reboot, which is true — but
incomplete. `/etc/config` is a symlink to `/mnt/HDA_ROOT/.config`, i.e. flash, and `/root/.ssh` is a
symlink into that same place. So the sshd config **and** the authorized keys both persist; it's only
the directory around them that gets recreated.

What isn't guaranteed is a firmware update, which can rewrite service configs. So I keep a
checksum-matched copy of the live file elsewhere — after an update, the question "did QTS put my
config back the way it found it" is a diff instead of a memory test.

## What the NAS accepts now

The mesh policy is deny-by-default, and the NAS's grants come out as:

- **My admin machines** — everything.
- **The family laptop** — every service the NAS offers **except a shell**. There's no reason for a
  laptop to hold a session on a box whose only account is uid 0.
- **The public-facing web server** — *nothing*. It's the machine most likely to be compromised and it
  had no business reaching the backups; nothing legitimate used that path, because the off-site pull
  runs the other way round and doesn't use the mesh at all.

The family-laptop grant is the one where I changed my mind mid-review. My first pass gave it the media
ports and deliberately withheld file sharing, which felt like good least-privilege — until I remembered
her Time Machine backups run to a share on this box. **A blocked backup fails quietly and stays
broken**, and you find out about it on the day you need it. That's a worse outcome than the port being
reachable from a laptop I already trust, so it's granted. Least-privilege is a default, not a rule to
follow off a cliff.