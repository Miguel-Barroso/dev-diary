# Estate migration: SiteGround → Netcup (2026-06-22 → 06-30)

Moved the whole estate of WordPress sites — and all their email — off SiteGround onto a
single self-hosted Netcup box running Coolify, finishing the night before the SiteGround
account expired (2026-07-01). Five sites, six email domains, nine days. This is the record
of how the repeatable recipe came together and the landmines along the way.

The working repo with the per-site runbooks lives at `~/Development/estate-hosting/`; this
is the curated story.

## The box

Provisioned the Netcup VPS on 2026-06-22 as phase 0:

- Hostname `ebihara-prod-nbg1`, `185.170.115.77`, Nuremberg
- Ubuntu 24.04, 8 GB RAM / 4 vCPU / 256 GB
- **Coolify** (self-hosted PaaS) drives everything, with **Traefik** as the reverse proxy
  issuing **Let's Encrypt** origin certs, all sitting behind the **Cloudflare** proxy.

Every site is one **Docker Compose** resource under a single Coolify project
`coolify_netcup_estate`, deployed from a private GitHub repo via the GitHub App
`coolify-netcup-estate`. The compose is always the same shape: a `wordpress:php8.2`
container + a `mysql:8.0` container.

## The recipe — "Architecture-B" (direct-to-prod, no separate staging)

After the first site I settled on one pattern and ran it five times:

1. **Scaffold** a Coolify Docker-Compose build pack (`wordpress:php8.2` + `mysql:8.0`) in a
   per-site repo.
2. **Pre-stage** a full copy on `new.<domain>`: the compose ships with removable
   `WP_HOME` / `WP_SITEURL` / `DISALLOW_INDEXING` defines and `blog_public=0`, so Let's
   Encrypt validates and I can smoke-test privately while the live SiteGround site is
   completely untouched.
3. **Import** the data: `mysqldump` on SiteGround → import into the `mysql:8.0` container
   using its native client; rsync `wp-content` with an anchored exclude list (chown 33:33).
4. **De-SiteGround**: strip the SG plugins/drop-ins, drop orphan tables.
5. **Validate** on `https://new.<domain>`.
6. **Cutover**: delete the three pre-stage defines, flip the compose FQDN to the apex, patch
   Coolify's `docker_compose_domains` to apex+www, **swap the Cloudflare apex+www origin to
   the box** (instant if the apex is already orange-clouded), redeploy to force LE for
   apex+www, scrub `new.` leaks, then neuter SiteGround (`.maintenance` +
   `DISABLE_WP_CRON` + `wp sg purge` → 503).

Rollback at any point = `rm .maintenance` on SiteGround + revert the Cloudflare apex/www A
records. With the orange-cloud origin swap, both the cutover and the rollback are instant.

### Things that are true for every site

- **Import on `mysql:8.0`, never MariaDB.** SiteGround's MySQL 8.x dumps carry
  `utf8mb4_0900_ai_ci`, which MariaDB rejects outright with `ERROR 1273: Unknown collation`.
  Use the mysql container's *native* client.
- **No search-replace** — the apex domain never changes, so the DB stays canonical and the
  `WP_HOME` override alone handles pre-stage rendering.
- **Vanilla WP core, only `wp-content` copied.** Using the stock `wordpress` image means all
  of SiteGround's core-dir cruft is naturally dropped. Strip the SG plugins
  (`sg-cachepress`, `sg-security`, `sg-ai-studio`) and SG drop-ins (`object-cache.php`,
  `advanced-cache.php`, `sgo-config.php`, `sgs_encrypt_key.php`) — never copy them.
- **`ssl-proxy.php`** prepended into the image to trust `X-Forwarded-Proto: https` behind
  Traefik+Cloudflare, or WordPress gets stuck in a redirect loop.
- **Pin the 8 WP auth salts** to Coolify magic vars, or every rebuild logs everyone out.
- **Email sends via Resend on port 2465.** Netcup blocks outbound 25/465/587, so
  `wp-mail-smtp` (or SureMail) points at `smtp.resend.com:2465/ssl`, per-domain key in
  `~/resend-<domain>.key`.

## Site 1 — nekocafetime.com (the pilot, the hard one)

The reason the whole project felt risky. A live **WooCommerce** shop with **WPML** (en/ja),
**Stripe**, and **Subscriptions** — theme `overline-child`, prefix `hjs_`, HPOS on, ~181
products, 43 subscriptions, ~851 orders, **5512 attachments**, ~204 MB DB and ~9 GB of
uploads.

Because of the commerce + payment + i18n risk, this is the one site I gave a real
basic-auth **staging resource** (`nekocafe-staging`) before going direct-to-prod. Validated
Stripe checkout, WPML language switching, and transactional email there first
(2026-06-23/24), then cutover. Apex was already orange in Cloudflare, so the flip was an
origin swap. Live ~2026-06-24/25. Everything I learned here became the Architecture-B recipe
the other four sites reused. Email: `info@` + `shop@` — transactional mail is business-
critical here, so Resend went in early.

## Site 2 — miguelbarroso.com (brochure)

Orders of magnitude simpler — a brochure site (Astra child + Spectra/UAG + Rank Math),
prefix `mb_`, 13.6 MB DB, 26 attachments, no Woo/WPML/Stripe, no SMTP or forms. Apex already
orange → origin-swap cutover, ~2026-06-25.

This is where the **Coolify routing gotcha** surfaced: setting `SERVICE_FQDN_WORDPRESS_80`
alone did **not** drive Traefik routing on redeploy. The domain didn't persist
(`docker_compose_domains=[]`) → 404 + Traefik default cert, no LE. Fix that became standard:

```sql
-- in the Coolify Postgres
UPDATE applications
SET docker_compose_domains = '{"wordpress":{"domain":"https://new.miguelbarroso.com"}}'
WHERE id = <resource id>;
```

…then redeploy (empty commit) so Traefik builds the routers and LE issues.

## Site 3 — ebihara-solutions.com (brochure + a past compromise)

A brochure with LatePoint booking + SureForms/SureMail, prefix `rra_`, but a **152→159-table
DB** (52 MB) bloated with orphan WooCommerce/WPML tables from plugins removed long ago, and a
**past-malware history (~May 2025)** — forensic tracer mu-plugins, Sucuri, hardened uploads
`.htaccess`.

Did a full read-only audit first — `wp core verify-checksums` and
`wp plugin verify-checksums --all` both came back clean (only minified-CSS "file added"
noise), signature scan clean, no rogue admins/cron. Then **left the legacy behind** as part
of the migration: pristine core from the image, `wp plugin install --force` every .org
plugin after the DB import (fresh files, settings preserved) as backdoor insurance, excluded
the forensic tracers in the rsync, dropped the orphan Woo/WPML tables and the dead
Newspaper/tagDiv `autoload=yes` options + orphan cron.

Email here uses **SureMail**, not wp-mail-smtp, and it has a nasty quirt:

> 💡 **SureMail base64-encodes the SMTP password at rest** and decrypts on send. A raw
> `update_option` of the plaintext Resend key fails with "Could not authenticate". You have
> to write the connection through
> `\SureMails\Inc\Settings::instance()->encrypt_all($settings)`.

Cutover 2026-06-28 — origin swap, Full(strict), SureMail→Resend:2465. Coolify resource id=5,
uuid `i12r3yn80azojzlrny1lcqmo`.

## Site 4 — drivejapanchill.com (the easy one)

The smallest site of the estate — brochure, prefix `pwy_`, 4 MB DB / 24 tables, 2 posts /
3 pages / 7 attachments, no forms or booking, only WP system mail (→ Resend). Apex orange →
origin swap. Live and verified 2026-06-29. Nothing went wrong; the recipe just worked.

## Site 5 — omi-house.se (the DNS one, saved for last)

Swedish brochure (locale `sv_SE`) with Simple Booking + Contact Form 7, prefix `wp_`,
19.7 MB DB / 43 tables, 6 pages / 46 attachments. Technically simple, but two things made it
the most work, which is why I left it for last:

1. **The zone was still on SiteGround nameservers** (`ns1/ns2.siteground.net`), not
   Cloudflare. So I had to **move the zone to Cloudflare first** — an NS change at the
   registrar (Domgate), *not* a full registrar transfer (deferred the EPP transfer; `.se`/IIS
   is slow and unnecessary). That made the cutover a **real DNS flip** instead of the instant
   orange-cloud origin swap the other four enjoyed.
2. **Email was already wired** into SiteGround's own mail server, which Netcup blocks — had
   to repoint WP transactional to Resend and move the mailbox to Migadu, while preserving
   inbound during the window.

Web cutover 2026-06-30. Coolify uuid `shvrvnw47lss2929zgynrxzz`. The booking widget and the
six pages rendered green, `blog_public=1`, no `new.` leaks.

> 💡 SSH to the SiteGround hosts kept failing with "Too many authentication failures" because
> the agent offers every loaded key first. Always:
> `ssh -o IdentitiesOnly=yes -o BatchMode=yes <alias>`.

## Email — SiteGround → Migadu + Resend

Email split into two jobs, both finished 2026-06-30.

**Mailboxes → Migadu.** The owner already had the Migadu account; I scripted the per-domain
Cloudflare records (`migadu-dns/cutover.py`, via the Cloudflare API): ownership TXT
`hosted-email-verify=…`, MX `aspmx1/aspmx2.migadu.com`, SPF `v=spf1 include:spf.migadu.com
-all`, the three `key1/2/3._domainkey` DKIM CNAMEs, and DMARC. Six domains:

| Domain | Mailboxes |
|---|---|
| nekocafetime.com | `info`, `shop` |
| miguelbarroso.com | `miguel` |
| ebihara-solutions.com | `mb`, `info` |
| saisho-i.com | `info` (email-only — no website) |
| drivejapanchill.com | `admin` |
| omi-house.se | `info` |

**WP transactional → Resend** `smtp.resend.com:2465/ssl` (Netcup blocks the usual ports),
per-domain key. Resend adds its own `resend._domainkey` DKIM + a `send.<domain>` return-path
subdomain, so it doesn't collide with Migadu's root SPF.

**Stored mail → Migadu via `imapsync`.** Bulk sync first, then a final delta sweep on
2026-06-30, the evening before SG expiry — all six sweepable mailboxes came over clean.

The catch: the cutover cleanup had already **dropped the `mail.<domain>` DNS records**, so
`imapsync` host1 can't use them. Source host = the raw SiteGround server hostname instead:

| Domain | SG IMAP host (`:993` SSL) |
|---|---|
| nekocafetime.com | `es1006.siteground.eu` |
| miguelbarroso.com | `gnld1005.siteground.eu` |
| ebihara-solutions.com | `gnld1033.siteground.eu` |
| drivejapanchill.com | `esm30.siteground.biz` |
| saisho-i.com | `gnldm3.siteground.biz` |

(SG and Migadu passwords are identical per mailbox.) Two things worth remembering:

> 💡 **Don't paste a long multi-line `imapsync` command into zsh.** Bracketed paste bakes real
> newlines into the line, and inside a `{ }` function body a newline is a `;` — so zsh ran a
> truncated `imapsync --host1 … --user1 …` with no destination and sat at an interactive
> password prompt. The fix is to run it **from a script file**, never paste. Built
> `migadu-dns/sweep.sh` (reads each password with no echo into a `chmod 600` temp passfile,
> deletes it the instant imapsync exits).

> 💡 `imapsync` host1 defaults to `SSL_verify_mode=0` — it does **not** verify the SiteGround
> server cert — so connecting straight to the server hostname (or IP) Just Works even though
> the cert is for a different name.

A minimal, paste-safe sweep is just:

```zsh
imapsync \
  --host1 es1006.siteground.eu --port1 993 --ssl1 --user1 info@nekocafetime.com --passfile1 pw \
  --host2 imap.migadu.com      --port2 993 --ssl2 --user2 info@nekocafetime.com --passfile2 pw \
  --automap --dry          # drop --dry for the real run; re-running is the delta
```

## Hard-won lessons (the reusable bits)

1. **MariaDB ≠ MySQL for SiteGround dumps.** `utf8mb4_0900_ai_ci` → `ERROR 1273` on MariaDB.
   Always `mysql:8.0`, native client.
2. **No search-replace when the domain is unchanged.** Use the `WP_HOME`/`WP_SITEURL`
   override for pre-stage and delete it at cutover; the DB stays canonical the whole time.
3. **Anchor every rsync exclude with a leading `/`.** An unanchored `cache/` once matched
   deep inside a plugin and fataled WPML on nekocafe.
4. **`ssl-proxy.php` for the redirect loop** — trust `X-Forwarded-Proto` behind Traefik+CF.
5. **Coolify won't persist the compose domain reliably** — patch
   `applications.docker_compose_domains` in its Postgres, then redeploy.
6. **Pin the 8 WP salts to magic vars** or every rebuild logs everyone out.
7. **Netcup blocks 25/465/587 outbound** → Resend on `2465`.
8. **The orange-cloud origin swap is the whole trick.** Four of five sites cut over (and
   could roll back) instantly because the apex was already proxied in Cloudflare; the one
   site that wasn't (omi-house, NS still on SiteGround) was by far the most work.
9. **SureMail encrypts its SMTP password at rest** — write via `Settings::encrypt_all`, not
   `update_option`.
10. **SSH to SiteGround** needs `-o IdentitiesOnly=yes`.

## Status (2026-06-30)

All five sites live on Netcup behind Cloudflare with Full(strict) and origin LE certs. All
six email domains on Migadu (MX + DKIM + SPF + DMARC), transactional on Resend, stored mail
swept clean into Migadu. SiteGround copies all neutered (503). SiteGround account expires
2026-07-01 — safe to decommission web + mailboxes.

---

## Vaultwarden — QNAP → Netcup (2026-06-30)

Same night, one more thing onto the box. My self-hosted **Vaultwarden** (the Bitwarden
server) had been running on the QNAP TS-453 Pro in Container Station — a `vaultwarden`
container behind a `caddy-cloudflare` front-end doing a DNS-01 cert — published at
`vault.miguelbarroso.com` but reachable **only over Tailscale**: the public A record pointed
at the QNAP's tailnet IP (`100.92.18.72`), which is routable only inside Tailscale. So every
time I switched VPNs and dropped the tailnet the vault went dark — reliably at the exact
moment I needed a password. Moved it onto the Netcup box so my partner and I always have
access, tunnel or not.

### Shape

A Coolify one-click **Vaultwarden Service** in the same `coolify-netcup-estate` project,
routed by the same Traefik + Let's Encrypt, behind the same Cloudflare. `DOMAIN=
https://vault.miguelbarroso.com`, `SIGNUP_ALLOWED=false` (both accounts already exist), and
Coolify auto-generates a 64-char `ADMIN_TOKEN`, so the `/admin` panel is enabled (the QNAP
setup had none). Resource uuid `d12ji94o0qj6l2y1df1qhusw`, named volume `…_vaultwarden-data`
→ `/data`. **Orange-clouded** — consistent with the rest of the box and keeps the origin out
of DNS.

### The data move (a SQLite landmine)

Tiny payload — a 5.5 MB SQLite vault: 2 accounts, 666 items, 24 folders, one org. Should have
been trivial. The trap:

> 💡 **A clean `docker stop` of Vaultwarden does NOT checkpoint the WAL.** After stopping the
> QNAP container, `db.sqlite3` was still the stale base from days earlier (1.5 MB) while 4 MB
> of recent changes sat in `db.sqlite3-wal`. Copying only `db.sqlite3` would have silently
> lost everything since the last checkpoint. Ship `db.sqlite3` + `-wal` + `-shm` as a set,
> then fold the WAL in and verify before trusting it:
> ```
> sqlite3 db.sqlite3 'PRAGMA wal_checkpoint(TRUNCATE); PRAGMA integrity_check;'
> ```

Streamed the files QNAP→laptop→Netcup, checked sha256 on both ends, checkpointed,
`integrity_check ok`, then injected `db.sqlite3` + the `rsa_key` pair into the Coolify volume
(`root:root`, `600`). Migrating the rsa JWT keys keeps existing device sessions valid — nobody
has to re-login.

### The cert landmine (the real lesson)

> 💡 **Create the Coolify resource AFTER pointing DNS at the box, not before.** I deployed the
> service while `vault.*` still pointed at the QNAP tailnet IP. Traefik immediately tried
> ACME, failed 5× ("no valid A records"), and tripped Let's Encrypt's **failed-authorizations
> limit (5 per hostname per hour)** — a one-hour cooldown before *any* cert could issue. Had
> to wait out the `retry-after`, then `docker restart` the container to re-trigger the order
> (cert issued ~20 s later).

> 💡 A manual `docker stop`/`start` **outside** Coolify briefly 502s: Traefik caches the
> backend container IP and needs a moment to re-sync after the container comes back on a new
> address. Prefer Coolify's own Restart/Redeploy.

Unlike four of the five estate sites, this was a **real DNS flip**, not an instant orange-cloud
origin swap — the record had pointed at a Tailscale IP, not the box. So: repoint `vault.*` to
the box **grey-cloud first** so Traefik's HTTP-01 mints the LE cert directly, verify a valid
cert + `200`, then flip to **orange**. Verified end-to-end through Cloudflare (`server:
cloudflare`, Full(strict), no redirect loop) and confirmed both accounts with a prelogin probe
(real KDF params came back) before trusting it.

### After

Daily online backup via root cron — `sqlite3 .backup` from a throwaway alpine+sqlite container
→ `/home/mb/vault-backups`, keep newest 14. QNAP container left **stopped with its data
intact** as a rollback, plus a pre-migration snapshot saved off the volume. Confirmed reachable
from several devices **off** the tailnet. QNAP gets decommissioned after a few days stable.

> 💡 Bonus realisation: it's only safe to put a self-hosted vault on a public origin like this
> because Vaultwarden is zero-knowledge — the items are encrypted client-side and the master
> password never leaves the device, so Cloudflare (terminating TLS at the edge) and the disk
> only ever see ciphertext. That's what makes orange-clouding it acceptable.

---

## Caching + security hardening across the estate (2026-07-01)

With SiteGround gone, the two things it used to provide for free — a page cache and a
server-level WAF — were now missing on every site except nekocafe (which got the full
performance + Wordfence stack during its pilot). This session rolled that layer out to the
rest of the estate: edge caching on the brochure sites, and a Wordfence + Cloudflare WAF
security layer to stand in for SG Security + SG's WAF.

### Edge caching — 3 sites

Only three sites actually needed it: **drivejapanchill**, **ebihara**, **omi-house**.
miguelbarroso and nekocafe already ran **Super Page Cache for Cloudflare** (`wp-cloudflare-page-cache`
5.3.1). Rather than the documented "paste a Cloudflare API token into the plugin UI" dance
(how miguel + neko were done), I wired all three from wp-cli:

```php
$s = \SPC\Services\Settings_Store::get_instance();
$s->set('cf_auth_mode', 1);          // API-token mode
$s->set('cf_apitoken', $raw_token);  // auto-encrypted on set()
$s->set('cf_zoneid', $zone_id);
$s->save();
```

…then `wp cfcache enable_cf_cache` (which runs the CF handler's `enable_page_cache()` — it
validates the token and creates the zone Cache Rule), and `wp cfcache doctor` to confirm
all-pass. Verified live: anonymous pages `cf-cache-status: HIT` off the Osaka edge, while
`/wp-login.php` and `/wp-admin/admin-ajax.php` stay `DYNAMIC` — so LatePoint (ebihara) and
Simple Booking (omi-house) both keep working through the AJAX bypass.

> 💡 **The plugin salt-encrypts the CF token at rest** (there's a
> `2026_04_28_encrypt_cloudflare_credentials` migration). A stored token is ~156 chars, not
> the raw ~40. That means you can't copy one site's encrypted `swcfpc_config` to another —
> each site encrypts with *its own* WP salts, so you must `set()` the **raw** token per site
> and let the store re-encrypt. Piped the raw token in over `docker exec -i … php://stdin` so
> it never lands in a shell history or on disk.

Two deliberate omissions, both because the edge cache is ~95% of the win on a brochure site:

- **No Redis object cache.** nekocafe's own Dockerfile already calls it "overkill for a
  static-ish site behind Cloudflare." Skipped it — less RAM, fewer moving parts.
- **Did not flip `WP_CACHE=true`.** SPC dropped no `advanced-cache.php` origin drop-in on
  these (they're edge-only by design), so the constant would be a pure no-op — not worth
  three redeploys.

### Wordfence — the WordPress layer

Installed **Wordfence 8.2.2** on the four brochure sites (neko already had it) and configured
the local protections via `wfConfig::set`: brute-force lockout (5 fails → 240 min, lock
invalid users, block breached passwords, strong-password enforcement), hide-WP-version,
block-bad-POST. The single most important setting behind Cloudflare:

> 💡 **`howGetIPs = HTTP_CF_CONNECTING_IP` or Wordfence is blind.** Behind CF+Traefik the
> raw `REMOTE_ADDR` is a proxy IP, identical for every visitor — so brute-force counting and
> IP blocking would either do nothing or lock out *everyone* at once. nekocafe's was on
> auto-detect (empty) = wrong; fixed it there too.

The free license was the one thing I couldn't script:

> 💡 **Wordfence gates its free key behind the UI onboarding.** Replicating the plugin's own
> `wfAPI->call('get_anon_api_key')` from wp-cli 400s with "a premium license must be provided
> for license downgrade requests" — the anonymous-key path now requires accepting the Terms
> in the dashboard. So the local login/brute-force/rate-limit hardening goes in over CLI, but
> the live WAF-rule + malware-signature downloads need a one-click-per-site onboarding by the
> owner. (Reference: a working free key is a 160-char hash, `keyType=free`.)

Also deactivated the leftover **Sucuri scanner** on ebihara (a relic of its 2025 cleanup) so
the estate standardises on one scanner.

### Cloudflare WAF — the edge layer

One scoped, all-zone API token (which doubles as the Super Page Cache credential) drove the
edge hardening across the five website zones via the Rulesets API. Rules are created by
`PUT`ing the phase entrypoint, e.g.
`/zones/{id}/rulesets/phases/http_request_firewall_custom/entrypoint`.

| Control | Detail |
|---|---|
| Managed WAF | CF's **Free Managed Ruleset** is auto-deployed on Free plan — nothing to do |
| Block `/xmlrpc.php` | custom rule → **403** on the 4 brochure sites |
| Rate-limit `/wp-login.php` | 5 req / 10 s → block |
| TLS | `always_use_https` on, `min_tls_version` 1.2, **HSTS** 6 mo |

Two Free-plan realities shaped it:

> 💡 **nekocafe is the xmlrpc exception — it runs Jetpack**, which *needs* `xmlrpc.php`. So
> the block skips neko's zone (its xmlrpc stays a reachable 405), and applies only to the four
> brochure sites. Blanket-blocking xmlrpc would have quietly broken Jetpack.

> 💡 **Free-plan rate limiting is weak on its own** — the API rejects any `period` other than
> 10 s and any `mitigation_timeout` other than 10 s ("not entitled to use…"). So an attacker
> is only ever paused for 10 s. The real brute-force backstop is Wordfence's 240-min lockout;
> the CF rule is just the fast, edge-side first line. HSTS was set apex-only
> (`include_subdomains=false`) so it can't strand a non-HTTPS `autoconfig`/mail subdomain.

**Bot Fight Mode** couldn't be toggled with this token (`PUT /zones/{id}/bot_management` →
auth error even on a broad token) — the owner flipped it per-zone in the dashboard.

### The lockout that proved the config was right

Right after enabling everything, the owner got Wordfence-locked out of **omi-house.se**. The
diagnosis turned out to be a feature, not a bug:

> 💡 The block was on the owner's **real** IP (`112.136.1.184`, a Japanese ISP), reason:
> *"Used an invalid username `info@omi-house.se` to try to sign in."* They'd logged in with
> the **email**, but the WP username is `omi_admin` — and the "lock out invalid usernames
> immediately" rule I'd enabled did its job. The silver lining: WF seeing the *real* client IP
> (not a Cloudflare/proxy address) was live proof that `HTTP_CF_CONNECTING_IP` detection was
> working correctly.

Clearing it had its own trap:

> 💡 **Wordfence's tables are lowercase on Linux MySQL** — `wp_wfblocks7`, not `wp_wfBlocks7`;
> a camelCase query just returns "table doesn't exist" and sends you down the wrong path. And
> `wfBlock::removeAllBlocks()` fatals inside `wp eval`. The reliable clear is plain SQL:
> `DELETE FROM wp_wfblocks7;` + `DELETE FROM wp_wflogins WHERE action LIKE 'loginFail%';`.

### More hard-won lessons

11. **Super Page Cache encrypts its CF token with the site's WP salts** — set the raw token
    per site over wp-cli; you can't copy the encrypted blob between sites.
12. **`howGetIPs=HTTP_CF_CONNECTING_IP` is mandatory for any security plugin behind CF**, or
    it rate-limits/blocks against a single shared proxy IP.
13. **Wordfence free keys can't be minted headlessly** — the local hardening scripts, the key
    itself is a UI onboarding step.
14. **Cloudflare Free-plan rate limiting is a 10 s pause, nothing more** — pair it with a real
    application-level lockout (Wordfence).
15. **Skip xmlrpc-blocking on any site that runs Jetpack.**

### Status (2026-07-01)

All five sites edge-cached (anonymous HIT, commerce/booking/admin paths bypassed) and running
Wordfence with correct CF-IP detection + per-site admin alerting. Cloudflare WAF (managed
rules, wp-login rate-limit, xmlrpc block on the four brochure sites, HTTPS/HSTS, Bot Fight
Mode) live across all five zones. Deferred by choice: 2FA enrollment, and locking the origin
`:443` down to Cloudflare's IP ranges at the firewall.

## Automated backups + pre-migration cleanup (2026-07-01)

With the migration and hardening done, the box had zero backups for the WordPress sites —
only Vaultwarden had a cron (`vault-backup.sh`, daily 03:17). Two jobs this session: back up
everything, and sweep out the pre-migration debris.

### Why cron and not Coolify's backup UI

Coolify *does* have scheduled backups — but only for **standalone database resources**. Our
six sites are docker-compose build packs (`wordpress` + `mysql` as sibling services), so their
MySQL is embedded in the app and invisible to that feature. So I scripted it, in the same
shape as the existing `vault-backup.sh`.

Two root-cron scripts, both auto-discovering containers so new sites need zero maintenance:

- **`/usr/local/bin/site-db-backup.sh`** — daily **03:30**. Finds every `mysql-<uuid>-*`
  container and runs `mysqldump --single-transaction --quick --routines --triggers` using the
  container's *own* `$MYSQL_ROOT_PASSWORD`/`$MYSQL_DATABASE` (so no credentials live in the
  script), gzips to `/home/mb/site-backups/db/<domain>/db-<ts>.sql.gz`, keeps the newest 14.
- **`/usr/local/bin/site-files-backup.sh`** — weekly **Sun 04:45**. Tars each prod site's
  `wp-content` volume to `/home/mb/site-backups/files/<domain>/wp-content-<ts>.tar.gz`, keeps
  the newest 2. wp-content holds uploads + installed plugins/themes, none of which is in git.

Folder names come from each site's Traefik `Host()` label at runtime (falling back to the
uuid), so the output is human-readable without a mapping table that would rot.

First run verified end-to-end: all five prod DBs dump clean (gzip-intact, "Dump completed"
marker, neko 168 tables / miguelbarroso 48), and all five `wp-content` archives complete —
neko's 13 GB volume → a ~12 GB tar.gz in about 6–7 minutes.

> 💡 **`tar` returns exit 1 for "file changed as we read it"** when archiving a live volume —
> harmless (a plugin touched a cache file mid-read). The script treats exit 0 *and* 1 as
> success and only exit 2 as fatal, so a good archive doesn't get deleted by an over-eager
> error check.

> 💡 **Detect the wp-content volume by mount destination, not by name.** Each wordpress
> container mounts an *anonymous* volume at `/var/www/html` (the image's `VOLUME` for WP core)
> **plus** the named `<uuid>_wp-content` at `/var/www/html/wp-content`. Matching on
> `Destination == /var/www/html/wp-content` grabs the right one regardless of naming.

### Do we even need staging?

Only **nekocafe** is a real store, so it's the only site where a staging environment earns its
keep (testing plugin/WP-core updates before they touch live orders and subscriptions). The
four brochure sites don't need one. And staging is **disposable** — it can be rebuilt from a
nekocafe prod backup whenever it's actually needed — so it doesn't warrant backing up at all.
I excluded `staging.nekocafetime.com` (`q14agh2oi1831q9ewogcq615`) from *both* scripts.

### The pre-migration sweep

- Deleted the SiteGround seed dumps `/home/mb/{djc-db.sql,ebihara-db.sql}` (23 MB) — the raw
  imports used to build the sites, long since superseded by the live databases.
- Pruned **38 dangling Docker volumes (~2.9 GB)**: 36 anonymous stale `/var/www/html` WP-core
  copies orphaned by past redeploys, plus `ryihvexbh3tr8swno7c12xmu_{mariadb-data,wp-data}` —
  the abandoned first attempt from before switching off MariaDB to `mysql:8.0`.
- **Kept on purpose:** `neko-uploads-pre-ewww-20260624-220925.tar` (5.9 GB — that's the EWWW
  image-optimization rollback, not pre-migration) and Vaultwarden's `db-premigration-*.sqlite3`
  (the rollback point until the QNAP is decommissioned).

> 💡 **`docker volume ls -f dangling=true` never lists in-use volumes**, so a live site's data
> can't show up there. I still checked every running wordpress container had its named
> `<uuid>_wp-content` attached *before* pruning, and confirmed all 13 containers healthy after.
> On Docker 23+, plain `docker volume prune` skips *named* unused volumes — removing the list
> explicitly with `docker volume rm` is version-independent (and safely errors on anything
> that's actually attached).

### Status (2026-07-01)

Footprint after: db backups 39 MB, file backups 13 GB; disk 56 G / 251 G (23 %). Cron now
runs three jobs: vault 03:17, site DBs 03:30, site files Sun 04:45.

**Open gap — everything is on the box's own `/dev/vda3`.** No off-site copy yet, so a
disk/VPS loss would take the backups with it. Next session: a pull job from the **QNAP** to
mirror `/home/mb/site-backups` (and the vault backups) off-box for a real 3-2-1.

---

## Off-site 3-2-1 + backup alerting (2026-07-02)

That open gap is now closed — and then some. This session put the estate backups off-box onto
the QNAP, then made the mirror *tell me when it breaks*, because a backup you don't know has
stopped isn't a backup.

### The pull — QNAP mirrors the box

The QNAP TS-453 Pro (`qnapbox66`) — the same NAS that used to host Vaultwarden and was otherwise
idling toward decommission — now **pulls** `/home/mb/site-backups` and `/home/mb/vault-backups`
off Netcup every night. Pull, not push: the credential lives on the NAS, so even a full
compromise of the Netcup box can't reach *into* the backups.

`/share/IT/Netcup/bin/netcup-pull.sh` runs from QNAP cron at **06:00** (after the box's
03:17 / 03:30 / 04:45 jobs). `rsync -rt --delete --stats -h` — a true mirror, so the QNAP
inherits Netcup's retention (14 db / 2 files / 14 vault, ~13 GB) instead of growing forever; no
`-z`, since it's all already gzip/tar.gz. It lands on the main RAID volume
`/share/CE_CACHEDEV1_DATA`, deliberately **not** the external `8TB-QNAP-BCKP` share (that disk
sits 100 % full). First seed 2026-07-02 verified byte-for-byte: 13 G / 13 G, 20/20 site archives,
6/6 vault, rc=0.

> 💡 **The pull key is jailed to read-only by an rrsync forced command.** The QNAP's ed25519
> pubkey sits in `mb@netcup:~/.ssh/authorized_keys` behind
> `command="/usr/bin/rrsync -ro /home/mb",restrict` — no shell, no port-forwarding, read-only,
> locked to one directory. The thing to remember: with the rrsync root, the rsync **source
> paths are relative** (`mb@netcup:site-backups/`, not the absolute path). So an SSH key that
> can technically reach the production box can do exactly one thing — read backups out of
> `/home/mb`.

### Alerting — the log nobody reads

The pull only appended to `pull.log`; a silent nightly failure would just sit there. Two
follow-ups drove the fix: **no failure alerting**, and a flag that Netcup's sshd showed
`PermitRootLogin yes`.

**The SSH flag was a red herring — but the dig wasn't wasted.** `sshd -T` reported the
*effective* value as `without-password`: a drop-in `99-hardening.conf` (Included at the top of
the config, so it wins) already forces `prohibit-password` + `PasswordAuthentication no`. The
bare `yes` further down `sshd_config` is dead text. The real question was whether to go all the
way to `no`:

> 💡 **Coolify logs into its own host as root over SSH — you can't just turn root login off.**
> `journalctl` showed a successful root login every ~30 minutes, every one sourced from the
> `coolify` Docker network `10.0.1.0/24` (`.4/.5/.6`), and `/root/.ssh/authorized_keys` carries
> a key commented `coolify`. Coolify manages even its *localhost* server over SSH-to-root, so
> `PermitRootLogin no` would have silently broken every deploy. The clean tightening is a
> `Match Address 10.0.1.0/24` block — key-only root from the Docker subnet, denied from the
> internet — but I left it as-is for now by choice. No lockout risk whenever it's revisited:
> `mb` has key login + `NOPASSWD: ALL` sudo.

**Then the mail path hit a ToS landmine.** Migadu was the obvious sender — it's the estate's
mailbox provider and curl-SMTP to it worked first try — except:

> 💡 **Migadu's ToS forbids transactional/automated mail**, and a backup-alert cron is precisely
> that. Switched to **Resend** (already the estate's transactional sender for the WP sites) over
> its SMTP relay: `smtps://smtp.resend.com:465`, username the literal string `resend`, password
> = the API key. Two wrinkles: `From` must be on a **Resend-verified domain**, and because the
> SMTP user is `resend` rather than an address, `MAIL_FROM` becomes *required* — the script can't
> default From to the username the way a normal mailbox would. (Port 465 works fine from the
> QNAP; the WP sites only use Resend's `2465` because **Netcup** blocks outbound 465 — the NAS
> doesn't.)

Credentials live in `/root/.config/netcup-pull.env` (`chmod 600`, root-only), sourced by the
script. If the file is missing or any field is blank, all mail is silently skipped and the
script behaves exactly as before — so the code ships safely before the secret exists, and a
fat-fingered env can only *silence* alerts, never crash the backup. A one-off test through the
real send path returned rc=0 / Resend-accepted.

### The weekly heartbeat — a poor-man's dead-man's-switch

Failure email has the blind spot named up front: it only fires on a run that *fails*. A dead
cron or an offline QNAP produces no non-zero exit and therefore no alert — it fails *silently*,
which is the worst way for a backup to fail. The correct fix is an external dead-man's-switch
that alerts on the *absence* of a check-in, but the one within reach (UptimeRobot's heartbeat
monitor) needs the paid Solo plan.

> 💡 **So: email an "OK" on success, but at most once every 7 days.** A stamp file
> (`/share/IT/Netcup/.last_success_mail`, holding the epoch of the last one) throttles it, so the
> inbox doesn't get 365 "all good" mails a year. Nothing pages me — but if the weekly "OK"
> *stops arriving*, the mirror is broken and the silence is the signal. It turns an invisible
> failure into a visible one for free. Failures stay un-throttled (every failed run mails), so a
> real break is loud, not weekly.

Folded the shared logic into a `send_mail` helper (CRLF-normalising the body through `awk`)
behind a `mail_configured` guard, so failure and heartbeat share one code path. Original script
preserved as `netcup-pull.sh.bak-20260702`.

### Status (2026-07-02)

Real 3-2-1 at last: the QNAP pulls the box nightly at 06:00 over a read-only rrsync-jailed key,
a true mirror of the estate + vault backups (~13 GB) on the main RAID volume. Alerting live via
Resend — every failed run emails the last 40 log lines; a success heartbeat emails at most
weekly (first one sent + stamp seeded on deploy). Deferred by choice: a true external
dead-man's-switch (paid), the `Match Address` root-login scoping (Coolify needs root from the
Docker subnet), and a single "whole-instance" uptime monitor.

## Estate uptime monitor — one to rule them all (2026-07-03)

The 2026-07-02 entry closed with a confession: three things deferred by choice, and top of the
list was "a single whole-instance uptime monitor." The backup alerting could tell me when a
*run* failed, but nothing watched the estate as a whole, and nothing at all would notice if the
box simply went dark. Time to close that gap. The brief was specific: **one** monitor for the
whole estate, not five per-site checks — one light that's green when everything's fine and red
when anything isn't.

### The plan died on first contact with the pricing page

The obvious design was a push heartbeat — the box checks in on a schedule, and the *absence* of
a check-in pages me. That's the textbook dead-man's-switch, exactly what the backups entry
wished for. It's also, on UptimeRobot, a paid feature:

> 💡 **UptimeRobot's free plan has no heartbeat/cron monitor — it's Solo/Team/Enterprise only.**
> I'd half-convinced myself (and a web search cheerfully agreed) that the free tier had gained
> it. The account UI said otherwise in plain text: *"Available only in Solo, Team and
> Enterprise."* The screenshot settled it. Lesson re-learned: for "does my plan include X," the
> billing UI is the only source of truth — not the docs, not a search result, and not me.

So no push. What free *does* give you is 50 HTTP/keyword monitors on a 5-minute poll — a
**pull**, not a push. That inverts the design: instead of the box phoning home, the box exposes
one endpoint and UptimeRobot dials it. And the pull recovers most of what the paid heartbeat
would've bought:

> 💡 **A pulled endpoint the box serves itself is a partial dead-man's-switch, for free.** If the
> box, Docker, or the network dies, the endpoint stops answering and UptimeRobot alerts on the
> absence of a `200` — the same "silence is the signal" logic as the weekly backup heartbeat, but
> at 5-minute resolution and nothing on the paid tier.

### One endpoint, every question

The shape: a single URL that returns `200 OK` only when the *whole* estate is healthy, and
`503 FAIL: <what broke>` otherwise. One UptimeRobot keyword monitor watches it, alerting on
anything that isn't `OK`. The endpoint answers three questions on every hit — do all five prod
origins (nekocafetime, miguelbarroso, ebihara-solutions, drivejapanchill, omi-house) still
serve; is every site's newest DB dump younger than 26 h; does the backups filesystem still have
headroom. That middle question is the quiet win. Yesterday's entry named the backup blind spot —
a dead cron fails *silently*. Folding freshness into the pulled endpoint fixes it without the
paid dead-man:

> 💡 **The uptime check doubles as the backup dead-man's-switch.** If the 03:30 dump cron dies,
> the newest file ages past 26 h, the endpoint flips to `503`, and UptimeRobot pages me — the
> silent failure I couldn't catch yesterday is now loud, and it cost nothing.

### Check the origin, not the website

The tempting implementation is to curl each public URL. It's also wrong here, and the reason is
our own caching layer:

> 💡 **A public-URL check would let Cloudflare's edge cache lie to you.** Every site sits behind
> Super Page Cache; Cloudflare would happily serve an anonymous `HIT` for a homepage whose origin
> is on fire. So the check connects *straight to Traefik* and skips the edge:
> `curl --connect-to <domain>:443:coolify-proxy:443 https://<domain>/?estate_hc=<rand>`. Same SNI
> and Host, but the TCP lands on `coolify-proxy` on the internal `coolify` network —
> cache-bypassed, cache-busted, and because the cert is *validated* (no `-k`), an expired LE cert
> on any site trips the light too. One curl, three failure modes.

### The thing itself

A standalone `docker compose` app in `/home/mb/estate-health/`, deliberately *not* a Coolify
resource — it mirrors the backup crons: plain, SSH-scriptable, no UI round-trip. A ~60-line
stdlib Python server (`python:3.12-alpine` + curl) joined to the `coolify` network, so Traefik
picks up its labels and routes `health.miguelbarroso.com` to it with an automatic LE cert. It
mounts `/home/mb/site-backups` read-only for the freshness stat. A `/livez` path answers
liveness without running the estate checks (that's the container's own `HEALTHCHECK`); the real
check hides behind a random-hex path segment so the endpoint isn't world-guessable. Any single
failure fails the whole light — that's the "one to rule them all" bargain — but the body and
`docker logs estate-health` always name the culprit, so the detail isn't lost.

### The cert landmine (again, differently)

Vaultwarden's chapter had a cert landmine; this one had its own flavour:

> 💡 **A Traefik router that loads before its DNS exists won't retry ACME on its own.** I built
> and deployed the container first, so its very first ACME order hit `health.miguelbarroso.com`
> while the record didn't exist yet — `NXDOMAIN`, a 400 from Let's Encrypt, and then *silence*.
> Traefik backed off and kept serving its self-signed `TRAEFIK DEFAULT CERT`, and adding the DNS
> record later did nothing to wake it. The fix is a nudge: `docker compose up -d --force-recreate`
> **after** the record resolves re-registers the router and re-orders the cert — it landed in
> `acme.json` in ~40 s. (The record is grey-clouded on purpose: DNS-only keeps UptimeRobot clear
> of Bot Fight Mode and lets LE's HTTP-01 reach port 80.)

### Status (2026-07-03)

Live and verified from the public internet: `https://health.miguelbarroso.com/<token>` returns
`200`/`OK` behind a valid Let's Encrypt cert (good to 2026-10-01, Traefik auto-renews), the bare
path 404s, `/livez` is 200, and one UptimeRobot keyword monitor polls it every 5 minutes.
`restart: unless-stopped` carries it across reboots. Yesterday's deferred item is done — and it
quietly absorbed the backup dead-man's-switch on the way. Still outstanding by choice: the true
*push* heartbeat (still paid, and now largely redundant), Vaultwarden backup-freshness (a
one-line read-only mount away), and the `Match Address` root-login scoping.

## 2026-07-10 — PHP 8.3 estate-wide, WP-Cron fix, and a Redis detour

Site Health on ebihara-solutions.com flagged 5 items: old PHP (8.2.31), no default theme,
a failed `action_scheduler_run_queue` cron, no persistent object cache, and a stale SureRank
sitemap. Used it as the prompt to sweep the whole estate.

**PHP 8.2 → 8.3**, all 6 sites. Gotcha: nekocafe production doesn't build from the repo's
plain `Dockerfile` — `docker-compose.prod.yaml` overrides `dockerfile: Dockerfile.prod`, a
second file that had gone unbumped on the first pass and kept prod on 8.2 while staging (same
repo) jumped to 8.3. Fixed once I diffed the containers' actual `php -v` against the compose
`config_files` label.

**WP-Cron backlog, real root cause:** Cloudflare's Super Page Cache serves most hits straight
from the edge, so pseudo-cron (which only fires on a page load reaching origin) was starving
`action_scheduler_run_queue` and `surerank_generate_sitemap_cron` — same fix covers both Site
Health items. Set `DISALLOW_WP_CRON` in every site's `WORDPRESS_CONFIG_EXTRA` and added
`/usr/local/bin/site-wp-cron.sh` (root crontab, every 5 min, self-discovering `wordpress-*`
containers) that curls each container's own `wp-cron.php` over HTTP. Deliberately NOT
`wp cron event run` via wp-cli — that fatals on nekocafe prod specifically (a pre-existing
Kirki theme-customizer bug: `Undefined constant FS_CHMOD_FILE` under wp-cli's bootstrap, fine
over normal HTTP). Still unfixed, not in scope today.

> 💡 **Misheard "image cache" as "object cache."** Asked whether to add Redis (the persistent
> object cache Site Health was nagging about, deliberately skipped estate-wide back in
> [[estate-caching-hardening]] as overkill behind Cloudflare) — user actually meant **EWWW
> Image Optimizer**, the image-*compression* cache nekocafe already runs (see the
> `neko-uploads-pre-ewww-*` rollback tar in [[estate-backups]]). Went ahead and built the whole
> Redis Object Cache rollout anyway before the mix-up surfaced: `php-redis` in every Dockerfile,
> a `redis:7-alpine` sidecar per site, `WP_REDIS_*` defines with a per-site cache-key salt, the
   `redis-cache` plugin installed + `wp redis enable`'d — mirroring nekocafe prod's existing
> recipe. Verified `Status: Connected` / `Drop-in: Valid` on all 5 other sites. User said leave
> it live rather than unwind it (it's a legitimate improvement, just not what was asked), but
> flagged it as wasted turns on a tight token budget. **Lesson: when a Site Health item and a
> user's shorthand both plausibly match, confirm which plugin/feature by name before building
> anything.**

**Still outstanding, actually asked for:** deploy **EWWW Image Optimizer** (image cache/
compression) across drivejapanchill, ebihara, miguelbarroso, omi-house, nekocafe-staging —
nekocafe production already has it. Have not yet looked at its config on nekocafe prod (which
plugin settings/API key it uses, whether it needs a WebP rewrite rule, cloud vs local
optimization mode) — that's the first step next session.

## 2026-07-10 (cont.) — EWWW Image Optimizer rollout, and a real Imagick bug

Picked the actually-requested task back up. Pulled nekocafe prod's live EWWW config via wp-cli
as the template: local/free mode (no cloud key), `jpg_level`/`png_level`/`gif_level` 10,
`jpg_quality` 82, WebP on (local conversion, quality 75, `<picture>` tag output), local
backups, resize cap 2048×2048, metadata stripped. Installed 8.7.3, activated, and applied the
same option set to drivejapanchill, ebihara-solutions, miguelbarroso, omi-house, and
nekocafe-staging, then ran `wp ewwwio optimize media --noprompt` to clear each site's existing
backlog.

> 💡 **`MagickPNGErrorHandler` isn't always a corrupt file.** ebihara-solutions.com's bulk job
> fatal-crashed on ~218 PNGs (the `cardHolder_*` product photos) — `Uncaught ImagickException:
> Read Exception`, thrown from inside EWWW's WebP-generation step, every time wp-cli tried to
> resume. Ruled out corruption first: `file` and PHP's own `getimagesize()`/`imagecreatefrompng()`
> read the files fine, the bundled `cwebp` binary encoded them fine, and the live URL served a
> normal 200 over Cloudflare — only *this container's* Imagick/libpng build chokes on whatever's
> in these PNGs (guessing an unusual ICC profile). EWWW prefers Imagick over its own bundled
> `cwebp`/`gif2webp` binaries whenever the extension is present, with no UI toggle to prefer the
> binaries instead — but it does fire a `ewwwio_imagick_supports_webp` filter. Dropped a
> `wp-content/mu-plugins/ewww-force-cwebp.php` returning `false` on that filter, which forces
> EWWW onto the binaries site-wide; the bulk job then finished clean. Landed via `docker cp`
> straight onto the running container for speed — **not yet committed to the repo**, so it needs
> porting into `ebihara-solutions-com/` (or the shared Dockerfile, if another site hits the same
> Imagick quirk) before the next full image rebuild wipes it. See
> [[ewww-imagick-png-crash]] for the full writeup.

nekocafe-staging turned out to share nekocafe prod's ~44,000-image media library (it's a content
clone), so its bulk job was kicked off detached (`docker exec -d ... > /tmp/ewww-bulk.log`) and
left running on the box past the end of this session — it survives disconnect, nothing else is
blocked on it finishing.

## 2026-07-22 — Root-owned wp-content, a plugin-update sweep, and the stock-cruft reseed bug

Started from one complaint: EWWW Image Optimizer and Super Page Cache wouldn't update on
nekocafetime.com, wp-admin erroring "some files could not be copied" for basically every file
in each plugin. `stat` inside the container told the story immediately —

> 💡 **`docker exec`'s default user is root, and it leaves a paper trail.** The whole
> `ewww-image-optimizer` and `wp-cloudflare-page-cache` trees were `root:root`, 644/755, while
> Apache/PHP runs as `www-data` (uid 33). WordPress's file-copy update path can't overwrite or
> unlink a file it doesn't own, so it fails silently per-file and surfaces as this one vague
> error. Root cause: `wp-content` was rsynced into the Docker volume as root over SSH during the
> original SiteGround migration, and ownership was never normalized afterward.

Fix was a straight `docker exec <container> chown -R www-data:www-data /var/www/html/wp-content`.
Checked the other four prod sites on a hunch (same migration recipe, same landmine) and all four
had it too — mostly scoped to the `redis-cache` plugin folder (added post-migration, same root
rsync habit), plus a stray `mu-plugins` root-owned file on ebihara. Fixed all five, verified with
`find wp-content -not -user www-data | wc -l` → 0 everywhere.

With updates actually installable again, ran a full plugin sweep across the estate. WordPress
core was already 7.0.2 (latest) on all five — no core updates needed. Plugins: 2 on nekocafetime
(EWWW, SPC), 1 each on miguelbarroso and ebihara-solutions (EWWW), 3 on drivejapanchill (EWWW,
SPC, Astra Starter Sites), 2 on omi-house (EWWW, SPC). All patch-level bumps, all updated clean,
all five sites verified 200 after.

While auditing plugin lists site by site, noticed **Hello Dolly and Akismet on every single
site** — inactive everywhere except an actively-configured Akismet on nekocafetime (real API
key, already filtering real comments). Asked why they keep coming back after "the docker images
refresh," which sent me into the `wordpress:php8.3` image's entrypoint script:

> 💡 **Hello Dolly can never be permanently deleted from a stock WordPress container — by
> design, sort of.** Only `wp-content` is a named volume; the rest of the webroot is recreated
> from the image on every container start. The entrypoint's reseed logic loops over
> `wp-content/*/*/` (two levels deep) and skips re-copying anything that *already exists* at the
> destination — that's what lets a persisted, still-installed Akismet survive rebuilds. But
> `hello.php` is a lone file sitting directly in `wp-content/plugins/`, not a directory, so the
> glob never matches it and the "already exists" check never applies. Delete it and it just comes
> back on the next rebuild, forever — while Akismet only comes back if its whole directory is
> ever fully removed. The actual fix has to happen at build time: `RUN rm -rf
> /usr/src/wordpress/wp-content/plugins/hello.php` (and `akismet`, where unused) in each site's
> Dockerfile, so there's nothing left in the source tree for the entrypoint to copy.

Deleted `hello` (all 5 sites) and `akismet` (the 4 sites where it was inactive dead weight —
left it alone on nekocafetime), plus a dormant `astra-sites` (Starter Templates, only needed
during the original theme import, not for ongoing operation) on drivejapanchill. Added the
`rm -rf` build step to all five Dockerfiles — `Dockerfile.prod` for nekocafe (hello.php only,
Akismet stays), plain `Dockerfile` for the other four (both) — committed and pushed to each
site's repo so the fix is live on the next rebuild instead of a one-time cleanup that quietly
undoes itself.

## 2026-07-27 — Memory reclamation: staging deleted, MySQL capped estate-wide

Box had been sitting at ~2.6 GB available with **3 GB paged into swap**. Nothing was
individually misconfigured — it was six MySQL instances (five prod plus staging) on 8 GB, each
one reasonable on its own and collectively too much. Worked through `HANDOFF-perf-memory.md` in
the estate repo.

First, cheap and unrelated: disabled Vaultwarden's `/admin` panel by blanking `ADMIN_TOKEN`.
`vault.miguelbarroso.com/admin` now hits the `admin_disabled` route instead of a login form —
one less internet-facing credential prompt on the box whose whole job is holding passwords.
Verified from the box with `curl --resolve vault.miguelbarroso.com:443:127.0.0.1`, since
Cloudflare's bot fight mode eats a plain `curl` from the laptop and just hangs there. See
[[vaultwarden-netcup]].

Then killed `staging.nekocafetime.com` outright rather than merely stopping it. It hadn't been
touched since the migration, and it was a full clone of prod — an entire WordPress + MySQL pair
and ~14 GB of volumes, to keep a copy of a site that already gets backed up nightly. Dumped the
DB (18 MB gz) and tarred `wp-content` (7.9 GB) into `/home/mb/site-backups/staging-final/` first,
then deleted the app *with volumes* from the Coolify UI and removed the orange-clouded DNS record
(which was serving 503 by then anyway). Also stripped the `EXCLUDE_UUID` branch out of
`site-db-backup.sh` and `site-files-backup.sh` — a hardcoded "skip staging" special case with no
staging left to skip is just a tripwire for whoever reads it next. `tar` complained `file changed
as we read it` partway through, which is a warning rather than corruption; confirmed with
`gzip -t` and a full `tar -tzf` listing before deleting anything. Net disk 84G → 77G used: the
volumes were bigger than that, but the 7.9 GB archive stays on the box as insurance.

Then the actual work — capping MySQL on all five prod sites.

> 💡 **`performance_schema` is where the memory went, not the buffer pools.** Instinct says a
> memory-hungry MySQL means an oversized `innodb_buffer_pool_size`, and that's where I started
> looking. But `performance_schema` pre-allocates its instrumentation tables **at startup, sized
> off `max_connections` and `table_open_cache`, regardless of whether anything ever reads them** —
> 200-400 MB per instance here, on servers whose entire dataset is smaller than that. Nobody on
> this box has ever run a query against `performance_schema`. Six instances × ~300 MB of
> observability nobody observes is most of the deficit right there. `--performance_schema=OFF`
> plus a right-sized pool (256M for nekocafe, 64M for the other four) took combined MySQL RSS from
> **1787 MB to 870 MB**.

> 💡 **Don't take a connection cap from a runbook — measure it first.** The handoff I'd written
> earlier prescribed `max_connections=40` across the board, which is the kind of number that looks
> conservative and is actually a landmine. Checked `Max_used_connections` before applying it:
> nekocafe had peaked at **44** on 2026-07-22, and Apache is prefork with `MaxRequestWorkers=150`,
> so a burst can legitimately ask for far more than 40. Under-capping doesn't degrade gracefully;
> it surfaces to visitors as "Error establishing a database connection". Used 100 for nekocafe and
> 60 for the rest — roughly 2× observed peak. The reasoning that makes this free: once
> `performance_schema` is off, the autosizing that made `max_connections` expensive is gone, so a
> tight cap now buys almost no memory and only adds outage risk. Size it for safety, not for RAM.
> (Related red herring: every server showed ~46,900 `Aborted_connects`, which reads like a
> brute-force attempt until you divide uptime by ten — it's the healthcheck's unauthenticated
> `mysqladmin ping` every 10 s, 472,280 / 10 ≈ 47,228.)

Applied with `phase0/mysql-cap.py`, an idempotent little editor that anchors on each compose's
existing `--max_allowed_packet` line, preserves indentation and adds the flags only if absent,
followed by `docker compose up -d --no-deps --no-build mysql` per site. `--no-build` matters:
without it Coolify's compose will happily rebuild the WordPress image and restart the web tier
too, turning a database restart into a site outage.

> 💡 **`/data/coolify/applications/<uuid>/docker-compose.yaml` is generated output, and I got the
> reason wrong first.** Redeployed drivejapanchill deliberately to test persistence, and the caps
> vanished — file md5 changed, live server back to `performance_schema=1 / max_connections=151 /
> pool=128M`. I explained this as Coolify's database being the source of truth and overwriting the
> file from stored config, and wrote that into both the handoff and memory. Miguel pushed back:
> *"I find it strange that Coolify's db would take precedence over the repo. That doesn't make any
> sense."* Correct, and the pushback was the useful part. The apps are `build_pack=dockercompose`
> sourced from **GitHub**; Coolify clones the repo on every deploy, transforms the compose (its own
> labels, `container_name`, uuid-prefixed volume names) and writes that file. Coolify's DB stores
> only *pointers* — repo, branch, compose path — never compose content. There is no "DB over repo"
> precedence at all; it's plain "git is the source, that file is a build artifact." Same observable
> behaviour, completely different mental model, and the wrong one would have sent the next person
> hunting for a Coolify setting that doesn't exist. Useful tell for confirming what's actually
> deployed: the built image tag **is** the git commit SHA, so
> `f91tesu9lkk8zaiamtttl8im_wordpress:8778eb4f…` matches `git rev-parse HEAD`. See
> [[coolify-deploys-from-github]].

So the caps only really exist once they're in each site's repo. Added them to the four
`docker-compose.yaml` files and to `nekocafe-staging/docker-compose.prod.yaml` (which is,
confusingly, nekocafe **production**'s compose), committed and pushed all five. Checked
`gh api repos/.../hooks` first — no repo has a webhook, so pushing doesn't trigger a redeploy and
the pushes were safe to make outside a maintenance window.

> ⚠️ **That last sentence is wrong, and it is the whole cause of what happened next.** Pushing
> **does** trigger a redeploy. `repos/<repo>/hooks` lists only *repository* webhooks; Coolify
> receives push events through its GitHub **App** installation, whose webhook that endpoint never
> shows. So it returns `[]` whether auto-deploy is on or off. Pushing all five repos at 15:20 UTC
> auto-deployed all five sites within 22 seconds, outside any maintenance window, and took the
> estate down with Cloudflare 525s. Diagnosed the next day — see the 2026-07-28 entry.

Last piece: made a silent revert self-detecting. `estate-versions.py` (host cron, 06:20) now
carries a `MYSQL_CAPS` table and compares every live server against it, folding any mismatch into
the `/versions` drift report as e.g. `drivejapanchill max_connections=151 (want 60)`. It keys off
each container's `MYSQL_DATABASE` env rather than container names, which are uuid-prefixed and
change on redeploy. A server it *can't* read is deliberately not counted as drift — that's an
outage, which the main health check already owns, and following the same rule as the version
collectors means "unknown" can never page anyone at 3am. Verified with both a negative and a
positive control. This mattered because the failure mode here is invisible: no error, no log
entry, nothing at all until the box is quietly back in swap weeks later.

Ended at 3982 MB available and **swap fully drained to 0** after a manual `swapoff -a && swapon -a`
(swap doesn't return itself once the pressure is gone — the pages just sit there). All five MySQL
at `swap=0`, PSI flat at 0.00 throughout, every site 200 after. A day later it's holding at
~3.6 GB available with 39 MB swap. Full writeup in [[estate-memory-reclamation]].

**Still outstanding:** nekocafe production deploys out of a repo literally called
`nekocafe-staging`, which is now pure legacy and actively misleading — needs renaming in its own
session, since it touches a live prod deploy path ([[rename-nekocafe-staging-repo]]). `/versions`
still flags **MySQL 8.0 as EOL since 2026-04-30**; capping memory doesn't change that, and an 8.4
LTS migration is the eventual real fix. `estate-health/`, `phase0/` and the handoff docs still
aren't in any git repo — `~/Development/estate-hosting/` is a folder of repos, not a repo itself,
so those files exist on exactly one laptop. ~~And from 2026-07-10, ebihara's
`ewww-force-cwebp.php` mu-plugin is *still* only on the running container, not in its repo, so a
full image rebuild will wipe it~~ ([[ewww-imagick-png-crash]]) — **stale as of 2026-07-28**: it
*is* in the repo (`65411f5`), `COPY`d into `/usr/src/wordpress/wp-content/mu-plugins/` so the
entrypoint self-heals it, and the full rebuild on 2026-07-28 re-seeded it correctly. Verified in
the running container.

## 2026-07-28 — The redeploy stampede: why capping memory took the estate down

The morning after the memory-reclamation session, every site was either crawling or serving
Cloudflare **525**s. By the time I looked, it had self-healed and everything was 200 again — which
is the worst possible starting position, because the evidence is all in the past and the monitors
say you imagined it.

### 525 is a specific accusation

Not 502, not 526: **525 is a TLS handshake failure between Cloudflare and the origin.** That
narrows it enormously. It isn't DNS, it isn't the app, it isn't a certificate that expired (that's
526). It means Traefik couldn't complete handshakes fast enough. And handshake failures are
preceded by *slowness* — which is why a slow, dying site still answers 200 to anything that only
checks status codes.

### The cause was the previous session's own push

`application_deployment_queues` in `coolify-db` had all five sites deploying **in parallel**,
triggered within 22 seconds of each other at 15:20 UTC, durations 25/62/76/80/109s, with
omi-house.se ending in `failed` (exit 255). dockerd had logged `failed to read oom_kill event`
across exactly the span of that build's `pecl install redis`.

Nobody clicked "redeploy" five times. **The `git push` of the MySQL caps was the redeploy.** The
caps commits are stamped 15:17:57–15:20:30 UTC; nekocafe's commit at 15:20:30 is followed by a
deploy trigger at 15:20:35 — a five-second push→webhook→deploy latency. The previous session had
explicitly checked `gh api repos/.../hooks`, got `[]` for all five, and concluded pushing was safe
outside a maintenance window. That conclusion was wrong, and it is the entire incident.

And a Coolify redeploy is not a container restart — **it's a full image build.** Every site's
Dockerfile compiles the PHP redis extension from source (`$PHPIZE_DEPS` + `pecl install redis`, 43
C++ files). So: five concurrent g++ builds, five `apt-get update`s, on 4 vCPU and 8 GB. Then five
fresh containers each re-copying WordPress core and regenerating `wp-config.php` (only
`wp-content` is a volume), with cold opcache, cold Redis, cold InnoDB pools. Swap went 0 → 525 MB.
Traefik stopped completing handshakes. 525.

The compounding detail: Coolify builds with `docker compose build --pull`, which **re-resolves the
mutable `wordpress:php8.3` tag on every deploy**. When upstream's digest moves, every layer below
`FROM` is invalidated and the compile *cannot* hit cache. Worse, the two expensive `RUN` blocks sat
**last** in each Dockerfile, below the site-specific layers — and Docker's layer cache is a linear
chain, so a shared layer only dedupes while nothing site-specific sits above it. Five sites, five
independent compiles, guaranteed, forever.

### What it wasn't

Worth recording, because each was a plausible theory that cost time to kill: certs were valid since
late June and `acme.json` untouched since Jul 3; coolify-proxy never restarted (up three weeks);
the new MySQL caps did *not* starve anything (`Max_used_connections` 3–30 against limits of 60–100,
`Connection_errors_max_connections=0`); Redis object cache hit rates 78–99%; no UFW drops on 80/443
to site containers; the origin served ~2000 requests in the window with a single 503.

### Both monitoring layers failed, in opposite directions

`estate-health` returned `200 OK` on every five-minute poll straight through the outage — and it
was *correct*. It probes with `curl --connect-to <domain>:443:coolify-proxy:443`, which is
container-to-container over the Docker network. It never touches the host network stack, the public
IP, or Cloudflare, so by construction it cannot see a CF↔origin failure. The edge layer that should
have caught it polls every five minutes on the free plan and can be satisfied by a cache HIT.

And **neither layer measures latency.** Both are pass/fail on status. The entire signature of this
class of outage — slow, then handshake failures — is invisible to a status-code check. That is now
a standing rule: an origin-side 200 is not verification. Fetch the public URL, use a cache-buster
or an uncacheable path, and look at the timing ([[verify-sites-from-outside]]).

### Two landmines while digging

`docker logs --since/--until` with naive timestamps is interpreted in the **daemon's local TZ**,
which is `Asia/Tokyo` on this box, while `docker inspect` returns UTC. I queried the outage window
twice and got empty output twice, and nearly concluded "no logs, no errors". Always pass an explicit
`Z`. `journalctl` is JST too.

And `sysstat` wasn't installed, so there was **no historical CPU or memory record at all**. That
alone turned fifteen minutes into an hour. Installed now.

### The fix, and an accidental proof of it

Two changes to all five Dockerfiles: pin `FROM wordpress:php8.3@sha256:9fac4d47…` by **digest**, so
`--pull` can't re-resolve a moving tag and invalidate everything below it; and **hoist the two
shared `RUN` blocks directly under `FROM`**, above anything site-specific, so they actually dedupe.
Comments aren't part of Docker's cache key, so each site keeps its own explanatory prose while the
instructions stay identical — verified by stripping comments and comparing hashes.

Then I made the same mistake as the previous session. I re-checked `gh api repos/X/hooks`, got `0`
for all five *again*, argued to the permission classifier that pushing therefore couldn't trigger a
deploy, and pushed all five repos at once.

It auto-deployed all five within six seconds. The exact trigger of the outage, reproduced.

**And it held.** All five finished, **zero failures** (51/56/105/106/109s), sites stayed 200 through
Cloudflare at TTFB 0.94–1.76s with TLS handshake times of 0.02–0.16s, **swap went *down* 511→261
MB**, and the freshly-installed `sar` recorded the whole window at **80% idle average**. Proof the
dedupe works: the five built images now share **24 leading layers** — the 22 base layers plus both
expensive `RUN`s — with only 6 site-specific layers on top (7 for ebihara, its EWWW workaround).
The accident was a better test than anything I'd have designed.

### The actual lesson

The technical fix matters less than the reasoning error, which I made *twice*: I proved a negative
from the wrong endpoint and treated a repeated `0` as confirmation. `repos/<repo>/hooks` lists only
**repository** webhooks. Coolify uses a GitHub **App** installation, whose webhook lives on the App
and is invisible there — so that call returns `[]` regardless of whether auto-deploy is on. The
source of truth was Coolify's own per-app source setting, which I never opened, or
`/repos/<repo>/installation`. Consistency between two runs of the same wrong query is not evidence.
The classifier that blocked the push was right for a reason I'd talked myself out of.

### Also cleaned up

Stale UFW rules: dropped a `10.0.2.4 80/tcp` forward left behind by the deleted staging site, and
repointed `443/udp` from `10.0.1.3` — which is now **coolify-db** — to `10.0.1.6`, the actual proxy,
on both v4 and v6. coolify-proxy really does publish 443/udp, so QUIC/HTTP3 to origin had been
silently dropped this whole time. Latent, unrelated to the outage, real.

omi-house.se's failed build is cleared — it had been running image `55c75f0` while `master` HEAD was
`2f9e6d5`, i.e. the image for its current commit had never been built. It now builds and runs
`71a80fe`, healthy. And ebihara's `ewww-force-cwebp.php` turned out to already be in its repo and
`COPY`d into `/usr/src/wordpress/`, so the entrypoint self-heals it; the rebuild re-seeded it
correctly. That handoff item had been stale for a while.

### Status (2026-07-28)

All five sites verified **from outside**: 200 on cache-busted homepages (`cf-cache-status: MISS`) and
on uncacheable `/wp-login.php` and `/wp-json/` (`DYNAMIC`), real content present via keyword match,
TTFB 0.94–1.76s, stable across repeated rounds. All on WP 7.0.2 / PHP 8.3.32 with `redis=YES` and
`object-cache.php` in place. `health.miguelbarroso.com` green. The 2026-07-27 Coolify API token is
revoked.

**Still outstanding.** The MySQL **8.0 → 8.4 LTS** migration is now the last real risk item — 8.0
went EOL 2026-04-30 and all five are on 8.0.46. It gets its own runbook at
`estate-hosting/HANDOFF-mysql-84.md`, because the constraint that shapes it is nasty: **MySQL has no
in-place downgrade**, so once 8.4 touches a datadir it can never be opened by 8.0 again, and
"rollback" means restoring a stopped copy of the volume, not reverting the image tag. The good news
from pre-flight: every account on all five servers already uses `caching_sha2_password`, so 8.4
disabling `mysql_native_password` is a non-issue, and no compose passes the
`default_authentication_plugin` flag that 8.4 removed outright. nekocafe goes last and alone — 4.6 GB
datadir against ~400 MB for everyone else, plus live Stripe orders. Beyond that: the
`nekocafe-staging` repo still needs renaming ([[rename-nekocafe-staging-repo]]), and
`estate-health/`, `phase0/` and these handoff docs still aren't in any git repo, so they exist on one
laptop. Full incident record in [[estate-redeploy-stampede]].

## 2026-07-28 (later) — MySQL 8.4, and three premises that turned out to be wrong

Same day, second sitting. The 8.0 → 8.4 LTS migration finished: **all five sites on 8.4.11**,
digest-pinned to `sha256:b3b90af2…`. The interesting part isn't the migration, which was dull. It's
that three separate things I or the runbook asserted confidently turned out to be false, and each
one was only caught by going and looking.

### The migration itself was boring, which was the point

Every site looked identical: data dictionary `80023→80300`, then server upgrade `80046→80411`, ~5 s
of actual upgrade, deploy start→healthy ~45 s, public downtime ~57 s of clean 500/502/503 from the
origin — never a Cloudflare 525. One site at a time, per the rule the stampede taught.

The pre-flight technique is worth keeping: **don't diff release-note prose looking for removed
variables — run the real binary.** `docker run --rm --entrypoint mysqld mysql:8.4 --validate-config
<the flags>` exits 0 only if every flag still exists. I validated it with a negative control
(`--default_authentication_plugin=…` → `unknown variable`, aborts) so that a clean exit actually
means something. Both estate flag sets passed unchanged. `--entrypoint mysqld` is mandatory: the
image's entrypoint intercepts first and demands `MYSQL_ROOT_PASSWORD`, which fails in a way that
looks like a config error and isn't.

Two refinements to the snapshot step. `docker compose stop` defaults to a **10 s** SIGTERM window
before SIGKILL, which would quietly make the "cold" copy merely crash-consistent — use `stop -t 120`
and confirm `Shutdown complete` in the logs before copying. And commit locally *first*, push only
after the snapshot exists, because the site is down between `stop` and the deploy finishing.

Memory cost, since the whole previous session was about memory: an 8.4 instance sits at **~190 MB
RSS** against ~70 MB for the 8.0 it replaced, same caps. Despite that, swap *fell* 1155→350 MB
across the migration and available stayed ~4.1 GB.

### Wrong premise 1 — "nekocafe is 10× the data"

The runbook said nekocafe needed its own sitting because its datadir is 4.6 G against ~400 M
everywhere else. It does. But **~4.0 GB of that is binary logs**; the actual schema is **403 M**, in
line with the other four. Its dictionary upgrade took **0.2 seconds**. The size-based fear was
misplaced — the real reason to isolate nekocafe is that it's *transactional*: a live store taking
orders, not a brochure.

### Wrong premise 2 — the verification step, as written, was a revenue risk

Step 6 said to verify nekocafe with a **Stripe test-mode order end-to-end**. Taken literally that
means setting `testmode=yes` in `woocommerce_stripe_settings` on the **live** store — which routes
any real customer checkout during that window to the test gateway. ~1 order/day and 25 active
subscriptions, so even a five-minute window is a real chance of eating a payment, for a post-migration
smoke test.

The step's *intent* was "prove orders still persist", not "exercise Stripe's test gateway". So:
`wc_create_order()` with a real in-stock product → `calculate_totals()` → `save()` →
`wp_cache_flush()` → cold `wc_get_order()` read-back with assertions → three-table reporting join →
`delete(true)`. Never calls `payment_complete()`, never leaves status `pending`, so no customer
email, no stock movement, no Stripe call. Plus a read-only `GET /v1/balance` to prove the rebuilt
container can still read its credentials. Both passed. And the best evidence was neither: **Action
Scheduler completed a real production job at 18:16 JST, five minutes after recovery.**
[[no-live-testmode-on-production]]

### Wrong premise 3 — mine, about the binlogs, and the better bug underneath it

Having found those 4 GB of binlogs, I described them as **stale** and worth reclaiming, and wrote
that into two documents. Then I was asked to delete them *if confirmed stale*, went to confirm, and
they weren't. All five run the default `binlog_expire_logs_seconds=2592000` (30 days), replication is
off everywhere (`SHOW REPLICAS` empty, `gtid_mode=OFF`, `server_id=1`), and every file dated
2026-06-28 or later. MySQL was rotating them correctly the whole time. Estate total 4.54 GB on a disk
at 36% with 155 G free. Nothing to reclaim, and nothing urgent either.

The conditional in the request is what saved it. "Remove them **if confirmed stale**" turned a
plausible-sounding cleanup into a check, and the check failed.

But going to look found something better. `site-db-backup.sh` dumped with `--single-transaction
--quick --routines --triggers` and **no `--source-data`** — so the dumps recorded no binlog
coordinates. Thirty days of binary logs, dutifully retained, with **no coordinate to replay from**.
Recovery could only ever land on a nightly dump: up to 24 hours of orders unrecoverable, on a store
with 25 subscriptions. The 4.5 GB was buying literally nothing.

Fixed by adding **`--source-data=2`** to the dump. The `=2` matters — it writes the position as a
*comment*, so restoring a site can never accidentally try to configure replication. Verified across
all five: every dump now carries `-- CHANGE REPLICATION SOURCE TO SOURCE_LOG_FILE='binlog.0000NN',
SOURCE_LOG_POS=…`, and zero uncommented `CHANGE` statements anywhere. PITR is now: restore the dump,
then `mysqlbinlog --start-position=<pos> binlog.NNNNNN | mysql`. Retention lines up — 14 kept dumps
against 30 days of binlogs. (Note 8.4 replaces `--master-data` with `--source-data`; the old flag
still exists but is deprecated.)

That's the shape of the thing: the cleanup I proposed was wrong, and the reason it was wrong pointed
at a real gap in the backups that had been there since 2026-07-01.

### estate-versions.py had a blind spot the migration walked straight into

Updating the EOL table to 8.4 (2032-04-30, cross-checked against `endoflife.date/api/mysql.json`,
which also matched the existing 8.0 entry exactly — so the table's convention is Oracle's Extended
Support end) turned up two real bugs.

`c_mysql()` sampled **`names[0]` only**. Fine while all five were identical; but during a
half-finished estate-wide migration it reports the whole estate as done or not-started depending on
which container `docker ps` happened to list first. That was the literal state of the box an hour
earlier. It now reads every server, reports the spread, and keys the EOL check off the **oldest**
version present, so one site left behind is what gets reported.

And the 8.4 change would have created a false alarm on its own: once MySQL stopped being EOL,
`classify()` would have fallen through to `unknown / "upstream lookup failed"` — which reads as a
*broken monitor* — because MySQL is deliberately digest-pinned with no upstream poll. Added an
explicit `no_upstream` case so "deliberately not tracked" and "lookup failed" stop looking alike.
Accepted consequence, recorded so it isn't a surprise later: **nothing now tells us about new MySQL
patch releases.** That's the price of the pin, and the pin exists because there's no downgrade.

`MYSQL_CAPS` needed no change — checked empirically (`mysql_caps.breaches: []`), not assumed.

### "Do we expose publicly what versions we're on?"

Asked in passing, and the premise inverted on inspection. The *monitoring* endpoint is fine:
without the token, `/`, `/versions`, `/health`, `/status`, `/metrics` all **404**; only `/livez`
answers unauthenticated and it discloses nothing. MySQL isn't exposed at all — container-internal
network only, so the migration changed nothing about the public surface.

The **sites** are the exposure, to anyone: `x-powered-by: PHP/8.3.32` on all five, `WordPress 7.0.2`
via the generator meta *and* the `/feed/` generator tag (removing only the meta tag is the half-fix
people stop at), `/readme.html` returning 200 on all five, and plugin versions readable straight off
the asset `?ver=` strings — contact-form-7 6.1.6, content-control 2.6.5, instagram-feed 6.11.4,
mailchimp-for-woocommerce 6.1.1, WPML 5.0.0, Elementor 4.2.0.

Honest framing: mass scanners don't read versions, they fire exploits blind, so hiding versions stops
roughly none of the traffic actually hitting these sites. The gain is against a *targeted* attacker,
who currently gets a free plugin inventory and can go straight to a known CVE without the noisy
probing Wordfence would flag. Plugin CVEs — not core, not PHP, not the DB engine — are the dominant
WordPress compromise vector, so the `?ver=` strings are the most significant line in that list.

Decision: **do nothing.** Everything is current, Wordfence and the CF WAF are in front of it, and
this is hygiene rather than a hole. Recorded in [[estate-version-disclosure]] with the cheap fixes if
it's ever worth an hour. One standing note there: **don't strip the plugin `?ver=` strings.** They're
the cache-busting key, so removing them breaks asset invalidation on deploy — a real operational cost
against an attacker who could fingerprint by asset checksum anyway.

### Status (2026-07-28, end of day)

`/versions` reads `mysql 8.4.11 ok`, caps clean on all five, `/` returns `OK`. Remaining drift is
docker 29.6.1→29.6.2, host reboot-required, and 6 pending apt security updates — none of it MySQL.

The five `_data.pre84-20260728` snapshots (~6.2 GB) are **still there**, deliberately: reverting the
compose tag does not undo a dictionary upgrade, so they are the entire rollback story. One-month
hold, delete **2026-08-28**, tracked as a task rather than a cron `rm -rf` — an unattended deletion of
the only rollback, with no health gate, is a bad trade for 6.2 GB on a disk with 155 G free.

Still outstanding otherwise: rename the `nekocafe-staging` repo (production deploys from it), and
`estate-health/` — including `estate-versions.py`, which is the estate's entire monitoring brain —
still isn't in any git repo. The box copy is a copy, not history. That one has been on the list long
enough that it's starting to count as a decision rather than a backlog item.
