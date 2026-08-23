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

---

# The reboot that left no crash to find (2026-08-22)

The NAS dropped off the network at about 11:24 and was back by 11:34. Nothing else in the house so
much as flickered. I went in certain of one thing: **it can't have been power**, because the box sits
behind an EcoFlow Delta 2 and a battery that big doesn't just blink.

That premise was wrong, and the way it was wrong is the useful part of this entry.

## Three places to look, and the one that mattered

QTS says plainly what it thinks happened:

```
2026-08-22 11:29:43  [Power] The system was not shutdown properly last time.
2026-08-22 11:26:54  first post-boot event (RAID resync)
```

So: unclean. That narrows it to "crashed" or "lost power", and those two want very different fixes, so
the whole job is telling them apart.

The kernel log is persisted to flash at `/mnt/HDA_ROOT/.logs/kmsg`, and because it only rotates on
size, the live file still reached back past the event:

```
2026-08-22 02:03:37  [975649.875824] EXT4-fs (device dm-11): ext4trim finish
2026-08-22 11:33:04  [    0.000000] Linux version 5.10.60-qnap ...
```

Nine hours of silence, then the boot banner. No panic, no oops, no OOM kill, no soft lockup, no I/O
error, no NIC reset. The kernel didn't complain on the way out. It stopped mid-sentence.

Silence is suggestive but not proof — a box that hard-hangs also goes quiet, and rsyslog can't flush
what it never got. The thing that actually decided it was **the crash buffer being empty**.

## Why an empty log is the loudest evidence in the room

QTS boots with ramoops configured, a 2 MB region pinned at a fixed physical address:

```
ramoops.mem_address=0x8000000   ramoops: using 0x200000@0x8000000
pstore: Registered ramoops as persistent store backend
```

The kernel console is mirrored into that RAM as it runs. On the next boot `/etc/init.d/init_check.sh`
mounts pstore, and if `console-ramoops-0` is there it rotates the saved copies and writes a new one:

```sh
/bin/mount -t pstore - /sys/fs/pstore
if [ -f /sys/fs/pstore/console-ramoops-0 ]; then
    ...rotate pstore_1 -> pstore_2 -> pstore_3...
    /bin/cp /sys/fs/pstore/console-ramoops-0 /mnt/HDA_ROOT/.logs/$pslog1
fi
```

Two things follow, and I only trusted the conclusion once I'd checked both.

**One: this fires on every boot, not just bad ones.** The three files on disk are dated 07-25 and
08-10 ×2, and one of those lines up with a perfectly ordinary reboot I did myself. So a saved dump is
the *normal* outcome, which makes its absence meaningful rather than unremarkable.

**Two: it wasn't skipped.** The branch is gated on a loop that waits up to three seconds for
`/mnt/HDA_ROOT/.logs` to exist. That's flash, mounted early, always there — so the guard passes and
the extraction genuinely ran and genuinely found nothing. Worth reading the guard before leaning on a
negative result; "the log is missing" and "the thing that writes the log never ran" look identical
from the outside.

And that's the answer. **ramoops survives a warm reset** — that is the entire point of it. A kernel
panic, a watchdog reset, a `reboot`: all of those leave the DRAM contents intact and the record turns
up on the next boot. What ramoops does *not* survive is the RAM losing power.

The buffer was empty. The RAM went dark. That isn't a crash, it's a power event.

## What that let me rule out

| Suspect | Evidence against |
|---|---|
| Thermal | CPU 54 °C, system 43 °C, disks 47–49 °C, fan 2471 RPM — all unremarkable |
| Disk / RAID | `md1` clean `[UUUU]`, resync done by 11:39; all four disks 0 reallocated / 0 pending / 0 uncorrectable |
| UPS-triggered shutdown | UPS integration is `Enable = FALSE`, `AC Power = OK` — and a Delta 2 has no UPS data port to signal over anyway |
| Scheduled or graceful reboot | No `shutdown.log` entry for the day at all |
| Software crash | Empty ramoops, silent kernel log, silent event log |
| House-wide outage | Both Pis had multi-day uptimes and never blinked |

It came back on its own because `Power_Recovery_Mode = 2` — the box is set to resume its previous
state rather than stay off. Which is why I'd never had to think about any of this before: the failure
mode and the recovery cancel out, and all you notice is a ten-minute hole.

## It's been getting worse for two years

`[Power] The system was not shutdown properly last time.` is greppable, and the event log goes back to
2021. Counting by year:

| Year | Unclean shutdowns |
|---|---|
| 2021 | 2 |
| 2022 | 2 |
| 2023 | 1 |
| 2024 | 1 |
| 2025 | 4 |
| 2026 | **7** (to August) |

The times of day are scattered across the whole clock — 05:39, 10:15, 13:02, 16:10, 20:57 — so it
isn't tracking a schedule, a backup window, or an afternoon heat soak. And 2026-02-16 produced three
in one evening, which is the shape of either a supply failing under stress or a grid throwing repeated
transfer events.

I'd seen every one of these as a one-off. Each was individually forgettable; the trend is not. **The
log had been telling me this for a year and I'd never once asked it the aggregate question.**

## Reconciling it with the battery

So how does a box on a 1 kWh battery lose power while nothing else does?

Because a Delta 2 is not an online UPS. It's pass-through with a transfer to battery measured in
milliseconds, and during that gap every device is running on whatever its own power supply can hold
up. Most things ride it out invisibly. Something with a decade-old supply and tired electrolytics may
not — and the hold-up time gets shorter as the capacitors age, which fits an accelerating failure rate
better than anything else I can point at.

Both halves of the contradiction are true at once: the battery did take over, *and* the NAS lost
power. It just lost it for the few milliseconds before the battery arrived.

That's the reframe worth keeping. **"It's on a UPS" is not the same claim as "it cannot lose power."**
I had been treating the first as if it entailed the second, and that assumption is exactly what stopped
me looking at this properly the previous six times.

Still open, and honestly labelled as such: I have not yet confirmed a grid event at 11:24. The Delta 2
has no shell and no local login, so that correlation has to come from EcoFlow's own telemetry — a cloud
API, which means the logger can live on any always-on box rather than anything wired to the battery.
The Mac Mini gets the job. Until that lands, "brief sag on transfer" is the best-supported story and
not a proven one.

With one caveat I want on the record before I lean on it: a transfer measured in milliseconds may
never appear in that telemetry at all. The battery reports state periodically, so the logger will catch
a *sustained* outage cleanly and may be entirely blind to the sub-second sag that is the leading
hypothesis. **A quiet log will not be evidence of innocence**, and if I forget that I'll misread the
next one badly. The competing explanation — a failing adapter or a marginal DC jack, with no grid event at all —
predicts exactly the same evidence and is fixed the same cheap way, which is why the power brick gets
replaced regardless.

## Two things I found while I was in there

**Bay 4 is the only drive with a dirty link record.** Mapping device nodes to physical bays is worth
doing explicitly, because they do not come out in order:

```
Port 1 -> /dev/sdb    Port 2 -> /dev/sda
Port 3 -> /dev/sdc    Port 4 -> /dev/sdd
```

`sdd` — **bay 4** — carries `UDMA_CRC_Error_Count = 11` and `Command_Timeout = 11`, worst normalized
value down to 094. The other three are clean zeros. CRC errors are link-layer, which usually means
cable or seating rather than platter, and its media stats are spotless. Not related to the reboot, but
it's the one drive to reseat next time the lid is off. It's also the odd one out by model — an
`ST8000NT001` where the others are `ST8000VN004` — so it went in as a replacement at some point.

**The encryption is costing more than it's protecting.** Load average sits near 10 while the CPU is
28% idle, which is the signature of threads blocked rather than busy — and the processes in `D` state
are `dmcrypt_write` and a `dm` kworker. The volume is encrypted (`/share/CE_CACHEDEV1_DATA`,
`/dev/mapper/ce_cachedev1`, `aes-cbc-plain`) and this box's J1900 has **no AES-NI** — I checked the
flag rather than assuming it. Every write goes through software AES on a 2014 Celeron.

The part that changes the calculus is where the key lives:

```
/etc/config/.externalkey/<uuid>.key
```

`/etc/config` is a symlink into flash, so the key is saved on the NAS and the volume unlocks itself at
boot. That's not a misconfiguration — it's the only way an unattended box comes back from a 03:00
power blip with its shares intact, and this morning it's exactly what got everything running again by
11:34 with nobody at the console.

But it does bound what the encryption is worth. **A key stored on the machine protects the drives, not
the machine.** Pull a disk out of this box and it's noise. Carry the whole box out of the house and it
unlocks itself on the new desk. The threat it defends against is bare-drive disposal or a single-disk
theft; it does nothing about the NAS walking. I'd been carrying it in my head as "the backups are
encrypted", full stop, which is a stronger claim than the setup supports.

Which leaves a real trade to make rather than an obvious fix: permanent crypto tax on every QVR Pro
write, in exchange for protection against one fairly narrow scenario. Worth noting QTS has no in-place
decrypt — encryption is chosen when the volume is created and the only way out is destroy and rebuild,
which with 9 TB on a 12.7 TB volume is a long restore. **Not a job to run on a box that browns out
every few weeks.** Fix the power first; that ordering isn't optional.

## What I'd tell myself

- A missing crash dump is a finding, not a dead end — but only after you've checked that the thing
  which writes it actually ran.
- Warm reset versus cold reset is a question DRAM can answer, and on QTS it already has.
- Grep the event log for the aggregate before diagnosing the instance. Seven this year reads very
  differently from one this morning, and it's the same log either way.
- "It's on a battery" is a claim about *outages*. It says nothing about *transfers*, and the gap
  between those two words is where this whole thing lived.

---

# A loop with only one cable in it, and a lease pinned to a dead adapter (2026-08-23)

I plugged an Orbi satellite into the NAS and the house network started coming apart. QuLog filled with
gateway reconfigurations, Adapter 2 and Adapter 3 flapping up and down, and the VPN client tearing
down and redialling in a loop. The cabling I'd done looked like this, and looked fine:

```
RBR50 router ──▶ QNAP Adapter 1
QNAP Adapter 3 ──▶ Sat1
```

A straight line. Two cables. I spent a while insisting to myself that a straight line cannot be a
loop, which is true, and which is also why it took me so long to see it.

## The second leg wasn't a cable

The QNAP runs its four NICs as a QTS **Virtual Switch**, which underneath is a plain Linux bridge —
not Open vSwitch, `ovs-vsctl` isn't even installed. All four adapters sit in one flat L2 domain:

```
bridge name   bridge id           STP enabled   interfaces
qvs0          8000.00089b:xx:xx:9d   no         eth0 eth1 eth2 eth4
```

`STP enabled: no`. Four ports, one broadcast domain, no loop prevention. That's the loaded gun; the
satellite was the trigger.

Sat1 is an RBR50 — a *router* pressed into service as a satellite — and an Orbi satellite does not
choose one backhaul and commit. It brings up Ethernet and it keeps its radio associated to the router
while it works out which one it prefers. So the actual topology, for as long as that decision took,
was:

```
RBR50 ──cable──▶ eth0 ──qvs0 bridge──▶ eth2 ──cable──▶ Sat1 ──radio──▶ RBR50
```

Three legs, and the one that closes the ring is made of air. It never appears in any cable trace,
which is exactly why my "it's a straight line" reasoning felt so solid and was so wrong. The bridge
was doing precisely what a bridge does — forwarding frames between two ports — and those two ports
happened to be two ends of the same network.

The kernel said so in as many words, 100 times:

```
[73973.400163] qvs0: received packet on eth0 with own address as source address
               (addr:00:08:9b:xx:xx:9d, vlan:0)
```

That message is the bridge receiving a frame it originally sent. There is no innocent reading of it.

## The log had already told me it was over

Here is the part I got wrong, and it's a more useful mistake than the topology one.

I read the QuLog screenshot as an emergency in progress and started planning an urgent cable pull. It
wasn't in progress. The whole thing was a **transient**, confined to the window in which Sat1 was
making up its mind:

| Time | Event |
|---|---|
| ~11:50 | Sat1 cabled to Adapter 3 |
| 11:54:07 | First loop burst (~5 s) |
| 12:56–12:58 | Link flapping on eth1/eth2 — 39 transitions |
| 13:03:02–13:03:07 | Second loop burst, then silence |
| 17:43 | I take the screenshot |

Five hours of quiet before I even looked. And the evidence was *in the screenshot* — its newest entry
was timestamped 13:02, taken at 17:43. Four hours and forty-one minutes of nothing, sitting right
there in the image I was using as proof of an ongoing fault. I'd looked straight past it because I was
reading the log for *what it said* and not for *when it stopped saying it*.

A log's last timestamp is data. If the newest line is hours old, the thing is not happening now, and
that changes the fix from "pull the cable this second" to "understand it, then do it properly."

## Reading the direction of a loop out of the counters

Before the rewire, `ethtool -S` on each NIC was unusually eloquent:

| NIC | Adapter | rx_broadcast | tx_broadcast |
|---|---|---|---|
| eth0 | 1 (router) | 274,653 | 31,197 |
| eth1 | 2 (homeplug) | 15,788 | 289,607 |
| eth2 | 3 (Sat1) | 1,432 | 250,381 |

Broadcast comes *in* on eth0 and goes *out* everywhere else, which is just a bridge flooding normally.
The useful asymmetry is eth2: 1,432 received against 250,381 sent. Sat1 was being shouted at and
barely answering — consistent with a satellite whose Ethernet side was up but which wasn't yet using
it as its path home.

Two things worth writing down about `brctl showmacs`, because both cost me time:

**Bridge port numbers are not adapter numbers.** They're assigned in the order interfaces joined the
bridge, and on this box they land scrambled:

```
eth0 (Adapter 1) -> port 1      eth1 (Adapter 2) -> port 4
eth2 (Adapter 3) -> port 2      eth4 (Adapter 4) -> port 3
```

I read "port 2" as "Adapter 2" for a good few minutes and drew confident conclusions from it.

**A dead link still holds a bridge port.** Adapter 2 had a HomePlug adapter in it that I'd stopped
using — high jitter, periodic drops, which I put down to the wiring in an old kominka. A 20-second
counter delta settled whether it mattered:

```
eth0  +36,982 packets      eth2  +39,909 packets      eth1  +2 packets
```

Two packets. Its powerline partner was gone and it had nothing to bridge to. Not a suspect — but still
a full member of `qvs0`, which becomes important further down.

## STP was the reflex, and it was the wrong fix

My first instinct was to switch on Spanning Tree in the Virtual Switch UI, which is the textbook answer
to a bridging loop and which I talked myself into and back out of twice.

Against it: STP can only ever fix this by blocking a port, and the only candidates were the uplink to
the router or the cable to Sat1 — both of which I actually want forwarding. That reasoning is correct
for a *permanent* loop.

For a *transient* one it's backwards. Blocking eth2 during backhaul negotiation is the right call, and
STP re-converges on its own once the radio drops out. So STP would have worked here.

It's still not what I did, because it treats the symptom. STP is what you turn on when you have a loop
you can't eliminate. I could eliminate this one. The costs are real too — roughly 30 seconds of
listening and learning on every link event before a port forwards, on a box that already reboots more
than I'd like — and consumer mesh gear is not reliable about passing BPDUs through, so an STP domain
that stops at the Orbi is a false sense of safety.

The rule I'd rather hold: **STP is a seatbelt, not a topology.** Fix the topology.

## What I changed

The one arrangement in this house with a clean track record is Sat2, which has been wired straight to
the router the whole time without a single incident. So: both satellites onto the router, everything
else behind a spare Linksys LGS108, and the NAS reduced to a single cable so its bridge becomes a
**leaf** and can't be a transit path for anything.

```
fiber modem ──▶ RBR50 WAN (port 1)
RBR50 port 2 ──▶ Sat1 ethernet backhaul
RBR50 port 3 ──▶ Sat2 ethernet backhaul
RBR50 port 4 ──▶ LGS108 port 1
                 LGS108 port 2 ──▶ QNAP Adapter 1   (only cable in the NAS)
                 LGS108 port 3 ──▶ Mac Mini 2012    (AdGuard DNS + DHCP)
                 LGS108 port 8 ──▶ HomePlug         (single adapter, no partner)
```

Cables moved at 18:33; by 18:36 eth1 and eth2 were down and stayed down. The forwarding table is the
proof it worked — every remote address is now learned on the single uplink:

```
port 1: 25 macs      port 2: 1 mac (local)      port 3: 1 mac (local)
```

Sat1's address moved from port 2 to port 1, meaning the NAS now reaches it via the switch and the
router rather than down a private cable, and its two clients followed it across. Loop message count
frozen at 100 with none since. eth0 clean: `rx_crc_errors: 0`, `rx_missed_errors: 0`.

The HomePlug is the one thing left that could re-create this, and it's worth being explicit about why.
A powerline adapter is a transparent L2 bridge — pair two and their Ethernet ports are the same
broadcast domain, with the mains as an invisible cable between them. On the switch with no partner
it's inert. It becomes a loop the moment its partner's Ethernet side touches the LAN again: a
satellite's spare LAN port, another switch, anything. Identical shape to the Orbi loop, over copper
instead of air. And HomePlug adapters **auto-pair on the default network key**, so that can happen
because somebody plugged a spare into a wall socket, with no decision made by anyone.

## The lease was pinned to the adapter I'd stopped using

The near-miss. Before moving anything I checked how `qvs0` gets its address, expecting static:

```
option dhcp-client-identifier 1:0:8:9b:xx:xx:9d
option dhcp-server-identifier <macmini-ip>
fixed-address <qnap-lan-ip>
```

DHCP, from the Mac Mini, keyed to `…9d`. That's **eth1's MAC — Adapter 2, the port with the dead
HomePlug in it.** A Linux bridge takes the lowest MAC among its members, eth1 sorts below eth0's
`…9c`, and so the NAS's entire network identity had quietly attached itself to the one adapter I'd
written off as useless.

My plan had been to strip the Virtual Switch back to Adapter 1 only. That would have dropped the
bridge MAC to `…9c`, changed the DHCP client identifier, and presented AdGuard with what looks like a
brand new device — moving the NAS off its address and taking every hardcoded reference with it.

In the end I moved cables and left the Virtual Switch membership alone, so the address never moved.
Worth being clear that this was luck rather than judgement: a bridge keeps a member's MAC even with
the carrier down, so `…9d` survived a dead port.

That leaves the config in a state I should name honestly. Adapters 2, 3 and 4 are **still bridge
members** with STP still off. Physically the box is a leaf and cannot loop. But plug a cable into any
of those three ports and it silently rejoins `qvs0`, and if that cable has another way back to the
LAN, this entry happens again. The safety is in the cabling, not the configuration. Cleaning it up
means staging a reservation for `…9c` on the Mac Mini first, and that has to happen *before* the
membership change, not after.

## What the fix didn't fix

Load average before the rewire was 10.71. An hour after, on a demonstrably loop-free network: 10.46.

The loop was never what was pinning this box. It's QVR Pro — the motion-detection workers, and a
`mongod` sitting on 2.2 GB of surveillance log database. I'd have happily filed all of it under "must
have been the network" if the number had moved, and the number didn't move.

I first wrote that up as QuLog Center churning against an unconfigured destination volume, which was
wrong and is worth correcting rather than quietly editing out. **There are two things on this box
called "the log service" and I picked the wrong one.** The hot `mongod` declares `dbPath: "/storage/
mongodb/"`, which reads like a system path and isn't — its open file descriptors resolve to
`QVRProDB/QVRProDB/Log/mongodb` on the data volume. QuLog's own database is MariaDB, 1.6 MB, on
flash, and it isn't grinding through anything at all. Resolving a config path through `/proc/<pid>/fd`
rather than trusting what the config file says is what separated them.

Also worth noting the VPN, which produced the loudest and most alarming lines in the original log,
never had a problem at all. The bridge loop caused the gateway to be re-elected, re-election tore down
the default route, and the tunnel dropped because its next hop vanished. It was the most visible
symptom and the furthest thing from the cause.

## What I'd tell myself

- A loop needs two paths, not two cables. Radio backhaul, powerline, a second SSID, anything
  transparent at L2 — if you're only auditing things you can physically trace, you're auditing the
  wrong set.
- Check when a log *stopped* before reacting to what it says. Newest timestamp versus wall clock is
  one subtraction and it reframes the entire job.
- STP is what you enable when you can't remove the redundant path. If you can remove it, remove it.
- Bridge port numbers are assignment order, not adapter numbers. Read the mapping, don't infer it.
- Before changing bridge membership, find out which member's MAC the bridge is wearing. On a DHCP box
  that MAC is your identity on the network, and it may well belong to a port you think is dead.
- When a fix lands, check the metric you were blaming *before* it. A number that doesn't move is
  telling you that you just fixed a different problem than the one you noticed.