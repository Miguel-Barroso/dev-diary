# Early macOS setup (2024-12 → 2025-01)

First weeks after migrating to the M4. A handful of recurring landmines and the workarounds that stuck.

## Chromium and Gatekeeper

After installing Chromium via Homebrew, macOS flagged the app as "damaged" and refused to open it. The usual "Open Anyway" path in System Settings → Privacy and Security was not available either.

Strip the extended attributes Gatekeeper uses to quarantine the binary:

```bash
xattr -cr /Applications/Chromium.app
```

This has to be repeated after every Chromium update, so a shell alias makes it painless:

```bash
alias fixchromium='xattr -cr /Applications/Chromium.app'
```

Later migrated to ungoogled-chromium when upstream Chromium was deprecated on Homebrew Cask. Did not need the same fix - worked out of the box!

## External monitor at 60 Hz

Anything above 60 Hz on the external display (Samsung CJ79 family) produced visible artifacts on the M4 — practically unusable across the whole UI. Forcing 60 Hz (or dropping resolution) resolved it.

Installed MonitorControl to drive external-display brightness and volume from macOS's native UI:

```bash
brew install --cask monitorcontrol
```

Imperfect (depends on the monitor's DDC/CI implementation) but a real productivity win.

## .zshenv vs .zshrc

When setting up Ruby for CocoaPods, I tried to export the Homebrew Ruby path in `~/.zshrc`. That clobbered the default `PATH` and made the shell effectively unusable — most system commands stopped resolving.

The original lesson was that persistent path exports belong in `~/.zshenv`, but years of adding development tools with `export PATH=…:$PATH` in both files led to ordering problems and duplicate entries. The approach was rethought in 2026-07 when the shell environment was cleaned up for AI development work (see "GNU/Linux compatibility layer for AI development", below).

### Current state (2026-07-14)

Shell responsibilities are now intentionally separated:

* `.zshenv` — environment variables required by **every** zsh process (interactive and non-interactive). Minimal, no PATH manipulation, no aliases, no plugins.
* `.zshrc` — interactive shell configuration: PATH ordering, Oh My Zsh, plugins, completions, aliases, AI tooling environment variables.

This separation makes troubleshooting easier and creates a cleaner environment for Claude Code, DeepSeek, Opus, Headroom, Serena, Flutter, and future Linux development environments.

Current `~/.zshenv`:

```bash
export CHROME_EXECUTABLE="/Applications/Chromium.app/Contents/MacOS/Chromium"
```

`.zshenv` now contains only the single environment variable required by every zsh process. PATH modifications, Cargo's `~/.cargo/env` sourcing, the Ruby gems path, the Flutter SDK path, and `setopt INTERACTIVE_COMMENTS` were all intentionally removed. `INTERACTIVE_COMMENTS` only affects interactive shells and now lives in `.zshrc`. Cargo executables are exposed via the explicit `~/.cargo/bin` entry in `.zshrc`'s `path` array — no startup sourcing required.

## CocoaPods: skip `gem`, use Homebrew

Related lesson from the same week. Following the official `sudo gem install cocoapods` route on macOS led straight into Ruby dependency hell — manually installing pinned versions of `securerandom`, `drb`, `activesupport`, and `zeitwerk` before giving up.

What worked:

```bash
brew uninstall --force cocoapods    # clear any half-installed remnants
brew install cocoapods
```

Homebrew bundles the Ruby runtime and gem dependencies into a single package, so no version drift and no manual gem juggling.

---

# Home network rebuild (2025-01-07 → 2025-01-19)

Both the MBP and the QNAP NAS have ethernet headroom that the WiFi-only home network was wasting. The goal was a dedicated high-speed MBP-to-NAS path that didn't touch the rest of the LAN.

## First attempt — direct ethernet subnet

Manual IPs on the dedicated link:

- MBP USB-C-hub ethernet: `192.168.10.2`
- QNAP NAS, Adapter 1: `192.168.10.1`
- Netmask `255.255.255.0`, gateway blank on both ends

Direct LAN transfers (rsync, SMB browsing) ran at full ethernet speed without ever crossing the router.

## The collision saga

Tried to also route internet traffic through this same interface, hoping to combine speed with normal browsing. That broke things badly:

- High ping and packet loss
- The Asus RT-AC86U logged multicast errors and eventually kernel-panicked
- The Docomo 5G router also lost stability
- Network unusable end-to-end

Mixing a dedicated point-to-point link with a router-managed broadcast domain caused arp/multicast collisions that confused both routers. Lesson: a direct NAS subnet has to stay isolated.

## 2025-01 topology

Rebuilt the home network around an Orbi mesh:

- Docomo 5G router (HR02) moved back to the top shelf in the tatami room
- Astromeda PC connected directly to the Docomo router's 2.5 Gbps port
- 1 Gbps port on Docomo → WAN port on a Netgear Orbi RBR20 in **Access Point mode** (avoids double NAT)
- Orbi RBR20 LAN port → Nexus Link power-line adapter
- Second Nexus Link adapter behind the computer desk → Orbi RBS20 satellite (ethernet backhaul)
- Orbi satellite → QNAP NAS, Adapter 2
- QNAP NAS, Adapter 1 → USB-C hub on the MBP (preserves the 192.168.10.x direct link)
- Adapters 1 and 2 split in the QNAP virtual switch — internet traffic only exits via Adapter 2

The power-line backhaul caused intermittent dropouts that the Orbi mesh interpreted as link failures. Removed the power-line and let the satellite use 5 GHz wireless backhaul instead. Stable since.

## Plex over Tailscale

Same week, added the MBP, Astromeda, QNAP, and Nothing Phone (2) to a Tailnet so Plex and Plexamp work from outside the house without opening ports or paying for Plex Pass remote streaming.

Plex ran on the QNAP at the time, so in Plex's network settings I registered the QNAP's Tailscale IP as a custom server access URL — a plain `http://100.x.x.x:32400`. It worked: clients resolved the server over Tailscale whether the device was on the home LAN, on cellular, or on hotel WiFi abroad.

> ⚠️ **Superseded (2026-08).** Both halves of that are now wrong, so don't copy
> it. Plex no longer runs on the QNAP — it moved to Astromeda — and more to the
> point, **a dotted CGNAT address is no longer accepted as a custom access URL
> at all.** plex.tv sits behind Cloudflare, and the `PUT` that publishes your
> connection list is rejected with **403** if any URI in it contains a dotted
> `100.64.0.0/10` address. The failure isn't partial, which is what makes it
> nasty: the *whole* update is refused, so the LAN address stops being
> republished too and the server quietly goes stale on plex.tv while looking
> perfectly healthy from the couch.
>
> What works instead is a **`plex.direct` hostname that encodes the tailnet
> address**. `plex.direct` is Plex's own public wildcard DNS —
> `<ip-with-dashes>.<cert-hash>.plex.direct` resolves to the address embedded in
> the name, and it returns CGNAT space quite happily. So it is still plain
> IP-based routing with no MagicDNS dependency, but it is a *hostname*, which
> the WAF accepts, and TLS validates because the hash is the server's own
> certificate CN (`*.<hash>.plex.direct`). Read the hash off the server with
> `openssl s_client -connect <plex-host-ip>:32400`.
>
> Three things I'd have wanted to know going in:
>
> - **Set it via the container's `ADVERTISE_IP`, never in the Plex UI.** The
>   image's `/etc/cont-init.d/40-plex-first-run` rewrites `customConnections`
>   from `ADVERTISE_IP` on *every* container start, so edits made in the UI
>   silently revert on the next restart. Keep the LAN URL in the same
>   comma-separated list.
> - **MagicDNS (`<host>.<tailnet>.ts.net`) belongs last, not first.** It breaks
>   on this MacBook whenever Tailscale and PIA are up together, and a client
>   with broken MagicDNS can't resolve `*.ts.net` at all. It earns a place as a
>   third fallback only because it survives certificate rotation.
> - **The `plex.direct` name is fragile in exactly one way:** re-claiming the
>   server regenerates its certificate, which changes the hash, which leaves the
>   hostname pointing at nothing.
>
> Check it took, rather than assuming — `grep -a "response from PUT
> https://servers.plex.tv/devices/"` in `Plex Media Server.log` should show
> `200`, not `403`.

## What's changed since (2026 update)

The 2025-01 topology lasted about a year before iterative upgrades brought it to its current form:

- **Orbi RBR20 + RBS20 → RBR50 + RBS50.** Upgraded both router and satellite for noticeably better backhaul throughput and a more capable processor. Same Access Point mode, same mesh layout.
- **Asus RT-AC86U retired entirely.** Once everything stabilised on Orbi, the Asus was no longer doing useful work and came out of the rack.
- **Docomo 5G router returned.** 5G connection was not reliable enough out here. Fortunately, could switch to fiber for cheap from ZTV and they even paid the installation fees. All devices are routed through Orbi still.
- **Both Raspberry Pis moved to ethernet.** Their WiFi links broke down under sustained streaming load — the Pi 3's Broadcom hang is documented in `rbpi3-log.md`, and the Pi 4 had similar (less frequent) dropouts. Wired connections eliminated the issue entirely.

Current device map:

| Device           | Connection                                                       |
| ---------------- | ---------------------------------------------------------------- |
| QNAP TS-453 Pro  | Direct ethernet to Orbi RBR50                                    |
| Mac Mini 2012    | Direct ethernet to Orbi RBR50                                    |
| Raspberry Pi 3   | Ethernet → home-plug → home-plug → Orbi RBR50                    |
| Raspberry Pi 4   | Ethernet to Orbi RBS50 satellite                                 |
| Everything else  | WiFi via Orbi mesh                                               |

Hardware footnote: the QNAP TS-453 Pro itself replaced a TS-451a that broke down — predates this diary.

---

# Dev Environment Setup — Flutter Workstation (2026-03-09)

Today I configured my macOS machine as a full Flutter development environment for cross-platform mobile apps.

## Goals

* Build Android and iOS apps from a single codebase
* Ensure reproducible builds
* Avoid global version conflicts
* Maintain a clean and ergonomic developer shell

---

# Core Framework

## Flutter

Installed the Flutter SDK to develop cross-platform applications using Dart.

Flutter allows a single codebase to target:

* Android
* iOS
* macOS
* Web

The Flutter CLI provides tools for building, running, and debugging applications.

Example commands:

flutter create app_name
flutter run
flutter doctor

---

# Version Isolation

## FVM (Flutter Version Manager)

Installed FVM to manage multiple Flutter SDK versions.

This solves the problem of projects requiring different Flutter versions.

Each project can pin its own SDK:

fvm install stable
fvm use stable

The global Flutter command now points to:

~/fvm/default/bin/flutter

This prevents conflicts between projects and makes builds reproducible.

### Legacy SDK migration (2026-07-14)

The machine has fully migrated to FVM. The old standalone Flutter SDK path (`~/development/flutter/bin`) was removed from all shell configuration, and the legacy SDK directory was deleted — reclaiming approximately **9.2 GB** of disk space.

Verification:

- `which flutter` returns nothing — no global Flutter command is exposed on `PATH`.
- `fvm flutter --version` and `fvm flutter doctor` succeed from `apps/mobile` and other projects.
- The project's `.fvm/flutter_sdk` symlink → `/Users/mb/fvm/versions/stable` is valid.
- No remaining symlinks, `local.properties` files, or shell configuration reference `~/development/flutter`.

This is an intentional workflow decision: no global `flutter` command is exposed. Flutter and Dart should always be invoked through `fvm` (e.g. `fvm flutter ...`, `fvm dart ...`) so the project's pinned SDK is always used. This avoids ambiguity and makes the active SDK explicit for both developers and AI coding agents.

---

# Platform Toolchains

## Android Development

Installed Android tooling via Android Studio, which provides:

* Android SDK
* Build tools
* Emulator
* ADB (Android Debug Bridge)

These tools allow Flutter to compile and deploy Android applications.

Android builds rely on Java and Gradle.

---

## iOS Development

Configured Apple’s toolchain via Xcode.

Installed CocoaPods to manage iOS native dependencies used by Flutter plugins.

Flutter automatically generates a Podfile in iOS projects and runs:

pod install

to fetch native libraries.

---

# Build Dependencies

## Java (OpenJDK)

Installed OpenJDK via Homebrew.

Java is required for Android builds because Gradle and Android tooling run on the JVM.

JAVA_HOME was configured so Android tools can locate the runtime.

---

# Developer Shell Environment

## Oh My Zsh

Configured an improved shell environment with plugin support.

Used to manage shell configuration and improve developer ergonomics.

---

## fzf

Installed fuzzy finder for fast command history and file searching.

Example usage:

CTRL + R

to search command history interactively.

---

## Watchman

Installed Watchman for efficient filesystem watching.

Flutter uses it to detect source code changes and enable fast hot reload.

---

# Final System State

Verified environment using:

flutter doctor

Result:

✓ Flutter
✓ Android toolchain
✓ Xcode
✓ Chrome
✓ Connected devices

All toolchains are functioning correctly.

---

# Development Workflow

Typical workflow now:

1. Create project

flutter create my_app

2. Enter project directory

cd my_app

3. Pin Flutter version

fvm use stable

4. Run application

flutter run

---

# Outcome

The system is now a fully operational Flutter development workstation capable of building:

* Android apps
* iOS apps
* macOS apps
* Web apps

from a single codebase.

The environment is version-controlled, reproducible, and optimized for developer productivity.

# 🛠️ Dev Diary --- Debugging 500 ms Latency (Discord / Network Routing)

## 📅 Date

2026-03-17

## 🎯 Problem

Experienced extremely high latency (\~500 ms) in Discord voice calls
between Japan (me, Shiga) and Sweden (Malmö).

Even basic network tests showed abnormal behavior: - `ping 1.1.1.1` →
\~300 ms ❌ - Local ping (`192.168.1.1`) → \~3 ms ✅

------------------------------------------------------------------------

## 🔍 Initial Hypothesis

-   Discord server selection issue (region mismatch)
-   ISP routing problem (ZTV, Japan)
-   VPN interference (Tailscale / WireGuard)

------------------------------------------------------------------------

## 🧪 Investigation

### 1. Traceroute revealed immediate latency

``` bash
traceroute 1.1.1.1
```

Result: - \~300 ms from first hop (10.x.x.x)

👉 Indicated local routing issue, not external network.

------------------------------------------------------------------------

### 2. Verified local network

``` bash
ping -c 6 192.168.1.1
```

Result: - \~3 ms ✅

👉 LAN healthy

------------------------------------------------------------------------

### 3. Checked routing table

``` bash
netstat -rn
```

Key findings: - Active utun interfaces (utun0--utun6) - IPv6 default
routes via utun - Suspicious IPv4 split (0/1 and 128.0/1)

👉 Indicates a full-tunnel VPN still active.

------------------------------------------------------------------------

## 💥 Root Cause

Combination of:

1.  Stale VPN tunnel (utun6)
2.  Broken IPv6 routing via utun interfaces (macOS prefers IPv6)

👉 Result: traffic misrouted → \~300 ms latency

------------------------------------------------------------------------

## 🔧 Fix

### Disable utun interfaces

``` bash
sudo ifconfig utun0 down
sudo ifconfig utun1 down
sudo ifconfig utun2 down
sudo ifconfig utun3 down
sudo ifconfig utun6 down
```

### Remove IPv6 default routes

``` bash
sudo route -n delete -inet6 default -interface utunX
```

------------------------------------------------------------------------

## ✅ Result

``` bash
ping -c 6 1.1.1.1
```

Output: - \~15--17 ms 🎉

------------------------------------------------------------------------

## 📊 Before vs After

  Test                 Before     After
  -------------------- ---------- ---------------
  Local (LAN)          \~3 ms     \~3 ms
  Internet (1.1.1.1)   \~300 ms   \~16 ms
  Discord call         \~500 ms   \~120--180 ms

------------------------------------------------------------------------

## 🧠 Key Learnings

-   macOS prioritizes IPv6, even when broken
-   VPNs can leave stale utun interfaces and routes
-   Full-tunnel configs are dangerous for latency-sensitive apps
-   Always inspect routes with `netstat -rn`

------------------------------------------------------------------------

## ⚡ Best Practices Going Forward

-   Use split tunneling for VPN
-   Avoid full-tunnel unless necessary
-   Verify routes after VPN usage
-   Use Singapore region for Japan ↔ Europe Discord calls

------------------------------------------------------------------------

## 🏁 Conclusion

Issue was not: - Discord ❌ - ISP ❌

It was: 👉 Local routing corruption caused by stale VPN interfaces +
IPv6 preference

# VSCodium Flutter Tab Autocomplete Fix

**Date:** 2026-03-25
**Project:** evol
**Environment:** VSCodium 1.96.4, macOS, Flutter 3.41.4 (FVM), Dart 3.11.1

---

## Symptom

Tab and Enter did not accept autocomplete suggestions in `.dart` files. The suggestion widget would appear and could be navigated with arrow keys, but pressing Tab or Enter did nothing. The Dart analysis server also did not appear in the Output panel dropdown.

---

## Root Cause

Three compounding issues, all of which needed to be fixed:

### 1. Wrong SDK path in `.vscode/settings.json`

The project-level settings file had an incorrect `dart.flutterSdkPath`:

```json
// ❌ Wrong — this path doesn't exist locally
"dart.flutterSdkPath": ".fvm/versions/stable"

// ✅ Correct — points to the FVM symlink
"dart.flutterSdkPath": ".fvm/flutter_sdk"
```

### 2. Bad file permissions on `.vscode/settings.json`

The file was owned by root, so VSCodium could not read it:

```bash
# Was owned by root — VSCodium couldn't read it
sudo cat .vscode/settings.json  # required sudo to read
```

### 3. `dart.enableCompletionCommitCharacters` was false

This Dart extension setting controls whether Tab and Enter act as "commit characters" to accept a selected completion. It was disabled (the default), which meant the suggestion widget displayed correctly but Tab/Enter were silently ignored at the LSP level — regardless of keybindings.

---

## Fix

### Step 1 — Correct the SDK path

```bash
cat > .vscode/settings.json << 'EOF'
{
  "dart.flutterSdkPath": ".fvm/flutter_sdk",
  "dart.enableCompletionCommitCharacters": true
}
EOF
```

### Step 2 — Fix file permissions

```bash
sudo chown $USER:staff .vscode/settings.json
chmod 644 .vscode/settings.json
```

### Step 3 — Remove conflicting user-level setting

In `~/Library/Application Support/VSCodium/User/settings.json`, remove any `dart.flutterSdkPath` entry. This setting should only live in the project's `.vscode/settings.json`, since it uses a relative path that only resolves correctly from the project root.

### Step 4 — Clean up keybindings

With `dart.enableCompletionCommitCharacters: true` handling Tab/Enter at the extension level, no custom keybindings are needed. Set `keybindings.json` to:

```json
[]
```

### Step 5 — Restart

Fully quit VSCodium (Cmd+Q), reopen into the project root, and confirm "Dart" appears in the Output panel dropdown.

---

## Verification

- "Dart" entry appears in the Output panel dropdown
- Flutter/Dart SDK version shown in the status bar bottom-right
- Tab and Enter accept completions in `.dart` files

---

## Notes

- **FVM symlink** at `.fvm/flutter_sdk` → `/Users/mb/fvm/versions/stable` was valid throughout; the SDK itself was never the problem.
- The Dart analysis server was actually running correctly the whole time — it just wasn't logging to the Output panel because VSCodium wasn't capturing extension output. Adding `"dart.analyzerLogFile": "/tmp/dart_analyzer.log"` to user settings confirmed LSP was healthy.
- The missing "Dart" entry in the Output panel was a red herring caused by the bad `.vscode/settings.json` permissions/path, not a server crash.

---

# Small fixes and aliases

## Enabling SSH from the CLI (2025-02-21)

The GUI route is System Settings → General → Sharing → Remote Login, but the one-line CLI equivalent is faster and scriptable:

```bash
sudo systemsetup -setremotelogin on
```

## fixaudio alias (2026-04-07)

Audio devices on macOS occasionally get into a state where the wrong input or output is stuck selected and the UI can't switch. Killing `coreaudiod` forces a clean rebuild of the device list:

```bash
echo "alias fixaudio='sudo killall coreaudiod'" >> ~/.zshrc
source ~/.zshrc
```

`fixaudio` now reliably recovers stuck audio without a reboot.

# GNU/Linux compatibility layer for AI development (2026-07-14)

This Mac is now configured to present a Linux-like shell environment for AI coding agents (Claude Code, DeepSeek, Opus, etc.) while remaining a native macOS workstation.

## Why

AI coding agents frequently assume GNU/Linux utilities. macOS lacks `timeout` entirely and ships BSD variants of `sed`, `grep`, `find`, and other core tools — flags differ, regex engines differ, and scripts that work on Linux silently break here. The compatibility layer reduces unnecessary agent failures and makes development more portable.

## Installed GNU packages

Via Homebrew:

- `coreutils` — provides `gtimeout`, `gls`, `gsort`, and the full GNU coreutils suite
- `findutils` — provides `gfind`, `gxargs`, `glocate`
- `gnu-sed` — provides `gsed`
- `grep` — provides `ggrep`

## Compatibility shims

`~/bin` contains symlinks that map familiar Linux command names to their GNU counterparts:

| Symlink   | Target                    |
| --------- | ------------------------- |
| `timeout` | `/opt/homebrew/bin/gtimeout` |
| `sed`     | `/opt/homebrew/bin/gsed`     |
| `grep`    | `/opt/homebrew/bin/ggrep`    |
| `find`    | `/opt/homebrew/bin/gfind`    |

`~/bin` is intentionally first in `PATH` so these override the macOS versions. The host operating system is unchanged — only the shell command lookup order is affected.

## PATH cleanup

`.zshrc` was refactored to use zsh's native `path` array instead of repeatedly modifying `$PATH` with `export PATH=…:$PATH`. Duplicate entries are removed by `typeset -U path`.

Current priority order:

1. `~/bin` — GNU compatibility shims
2. `~/.local/bin` — Claude Code, Headroom, tokensave, etc.
3. `/opt/homebrew/bin` — Homebrew packages
4. `/opt/homebrew/opt/openjdk/bin` — Java
5. `~/fvm/default/bin` — Flutter (FVM)
6. `~/.pub-cache/bin` — pub-cache
7. `~/.cargo/bin` — Rust/Cargo
8. `/Users/mb/Library/Android/sdk/…` — Android SDK
9. `~/.gem/bin` — Ruby gems (Homebrew-managed)
10. System paths (appended via `$path`)

This produces a deterministic command lookup order and is easier to maintain than scattered `export PATH` statements. The old approach of repeatedly adding to `PATH` from both `.zshenv` and `.zshrc` is superseded — `.zshenv` is now reserved for environment variables that every zsh process needs (see ".zshenv vs .zshrc" above).

Cargo's `~/.cargo/env` sourcing was also intentionally removed from `.zshenv` in favour of the explicit `~/.cargo/bin` PATH entry. This keeps all interactive PATH configuration visible in one place and eliminates an unnecessary startup action.

`ANDROID_SDK_ROOT` is exported alongside `ANDROID_HOME` in `.zshrc` — newer Android tooling prefers `ANDROID_SDK_ROOT` while Flutter still supports `ANDROID_HOME`, so providing both ensures maximum compatibility.

## AI development rationale

Development takes place across:

- macOS (this machine)
- Linux (Docker, dev containers, CI)
- future local AI inference machines (likely Linux)

The goal is to allow AI agents to assume a mostly Linux-like shell environment without forcing macOS-specific instructions into project documentation. When an agent writes `timeout 30 ./some-test.sh` or uses GNU-specific `sed -E` syntax, it works here without translation.

## Verification

```bash
$ timeout --version
timeout (GNU coreutils) 9.11
```

`type -a` confirms the shims are resolved first:

```bash
$ type -a timeout sed grep find
timeout is /Users/mb/bin/timeout
timeout is /opt/homebrew/bin/timeout
sed is /Users/mb/bin/sed
sed is /usr/bin/sed
grep is /Users/mb/bin/grep
grep is /usr/bin/grep
find is /Users/mb/bin/find
find is /usr/bin/find
```

PATH ordering verified with:

```bash
$ echo $PATH | tr ':' '\n'
```

`~/bin` appears before all system paths.

# 2026-05-24 Dev Diary Entry

## Network Latency Investigation (Orbi Mesh + MBP M4)

Today I investigated severe latency and jitter issues affecting my 2024 MacBook Pro M4 and QNAP NAS access.

### Network Topology

MBP M4
→ Thunderbolt cable
→ Samsung CJ79 monitor
→ Anker USB-C Ethernet adapter (AX88179A)
→ Netgear Orbi RBS50 satellite
→ dedicated 5 GHz wireless backhaul
→ Orbi RBR50 router

Astromeda PC was connected to the same RBS50 satellite and simultaneously downloading games from Steam and Epic.

### Observed Symptoms

- Extremely high latency to internet and local QNAP NAS.
- Speedtest on MBP showed:
  - Idle latency around 306 ms
  - Large jitter spikes
- Even a Mac mini directly connected to the main router showed elevated jitter, though less severe.

### Key Discovery

The issue was primarily caused by network congestion / bufferbloat on the Orbi mesh backhaul.

Important observations:

- MBP over Ethernet adapter:
  - ~100 ms latency to router
- MBP over Wi-Fi:
  - ~300 ms latency to router

This indicated:
- the AX88179A Ethernet adapter was not the primary problem
- the Orbi wireless mesh/backhaul was saturating under load

### Mitigation

Limiting both Steam and Epic downloads on Astromeda to 50 Mbps dramatically improved network responsiveness and reduced latency.

This strongly confirmed:
- mesh backhaul saturation
- queue/buffer congestion
- classic consumer-router bufferbloat behavior

---

# Automated QNAP Backup Setup (SSH + rsync)

To avoid unreliable SMB/Finder behavior over the mesh network, I switched to rsync over SSH for automated backups from the MBP to the QNAP NAS.

## Why SSH + rsync

Advantages over SMB:
- More resilient over unstable Wi-Fi
- Better resume behavior
- No Finder dependency
- Lower protocol overhead
- Easier automation
- Incremental syncing

SSH host already existed in ```~/.ssh/config```:

```ssh qnapbox66```

## QNAP Path Decision

Both of these paths worked:

```/share/Businesses/AICLOSE/Backups/Flutter/apps```

and

```/share/CACHEDEV1_DATA/Businesses/AICLOSE/Backups/Flutter/apps```

I chose the logical share path:

```/share/Businesses/AICLOSE/Backups/Flutter/apps```

because CACHEDEV paths are more implementation-specific and may change after storage migrations or pool changes.

---

# launchd + rsync Automation

Created:

```~/.backup_aiclose_qnap.sh``` 

Final working script:

```
#!/bin/bash

LOCKFILE="/tmp/backup_aiclose_qnap.lock"

if [ -f "$LOCKFILE" ]; then
    exit 0
fi

trap 'rm -f "$LOCKFILE"' EXIT
touch "$LOCKFILE"

/opt/homebrew/bin/rsync \
-avh \
--delete \
--partial \
--info=progress2 \
--exclude=build \
--exclude=.dart_tool \
--exclude=.git \
/Users/mb/Development/Flutter/apps/AICLOSE/ \
qnapbox66:/share/Businesses/AICLOSE/Backups/Flutter/apps/AICLOSE/ 
```

## Important Discovery

macOS ships an ancient rsync at:

bash /usr/bin/rsync 

which does NOT support:

bash --info=progress2 

My terminal was using the Homebrew-installed modern rsync instead.

This caused confusion because:
- interactive shell PATH
- launchd PATH

are different environments.

The fix was explicitly using:

bash /opt/homebrew/bin/rsync 

inside the script.

---

# launchd Agent

Created:

bash ~/Library/LaunchAgents/com.mb.backup_aiclose_qnap.plist 

Configured to:
- run hourly
- run at login
- log stdout/stderr to /tmp

Useful commands:

bash launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.mb.backup_aiclose_qnap.plist 

Manual trigger:

bash launchctl kickstart -k gui/$(id -u)/com.mb.backup_aiclose_qnap 

Check status:

bash launchctl list | grep backup_aiclose_qnap 

Exit status meanings:
- 0 = success
- nonzero = last run failed

---

# Notes About Active Development

Running rsync during active Flutter development is generally safe.

Behavior:
- rsync copies files as they exist at read time
- changed files get updated on next sync
- no file locking occurs
- project continues functioning normally

Excluded high-churn folders:
- build
- .dart_tool
- .git

This reduces:
- transfer size
- sync noise
- inconsistent transient states

The lockfile mechanism prevents overlapping backup runs.

---

# SSH config and key hygiene (2026-07-28)

Four weeks after the estate moved off SiteGround, `~/.ssh/config` still described the old world.
Cleaned it out and, more usefully, stopped using one key for everything.

## What the config was getting wrong

Five dead SiteGround host blocks, for accounts that expired on 07-01. One of those hostnames doesn't
resolve at all any more.

The Pi 4's LAN entry pointed at an address nothing answers on. Its actual LAN address is different —
confirmed with `hostname -I` over Tailscale and a Raspberry Pi OUI in the ARP table. AdGuard on the
Mac Mini holds a DHCP reservation for that Pi, so this wasn't lease drift; the entry predated the
reservation and nothing had used the alias since.

`known_hosts` still had the old address and nothing for the new one, so the first connection failed
with `Host key verification failed` — which under `BatchMode=yes` is just the trust-on-first-use
prompt turned into an error. I compared the offered host key against one pulled over the
already-trusted Tailscale path before adding it. Same key. Removed the stale entry.

The `github.com` block was decorative: that account has **zero** SSH keys registered, so it had never
authenticated once. The GPG keys on the account are for commit signing, which is a different
mechanism that shares a word. Signing works fine (`commit.gpgsign = true`, commits verify). Pushes go
over HTTPS with a token. Block removed rather than left lying.

## One key for everything

`id_ed25519` authenticated netcup (five production sites plus Vaultwarden), the QNAP holding the
off-site backups, both Pis and the Mac Mini. One file, whole estate, backups included.

Considered passphrasing everything and decided against it — a passphrase protects the key **at rest**
and does nothing about a process running as me, because once the key is in `ssh-agent` anything
running as my user can have it sign without ever reading it. `UseKeychain yes` makes that worse by
supplying the passphrase automatically. The real answers are `ssh-add -c`, `ssh-add -t`, or
hardware-backed keys where the material can't be extracted and each use needs a touch. Full reasoning
in `netcup.md`.

So: separate keys instead. netcup got its own, pinned with `IdentitiesOnly yes` so the agent can't
silently fall back to another identity and mask a broken config. Verified in both directions — new
key in, old key rejected.

Also deleted six SiteGround private keys that were still sitting in `~/.ssh` long after their hosts
were gone. Dead credentials are still credentials.

## Current shape

`~/.ssh` now holds exactly two keypairs: the general one, and the netcup-only one. Config covers
netcup, the QNAP, both Pis (with purpose aliases `cctv` and `catcam` alongside the old hostnames, so
existing scripts keep working), the Pi 4 on LAN, and the Mac Mini.

---

# Nothing gets to reach this laptop (2026-07-31)

Part of a house-wide hardening pass — key-only SSH everywhere and a deny-by-default policy on the
Tailscale mesh. The interesting decision landed on this machine, and it's the inverse of every other
rule I wrote: **no device is granted access to this laptop at all.**

## Why the admin workstation is the one thing nothing reaches

The key-splitting from 07-28 is exactly what makes this necessary. This machine holds the netcup-only
key *and* the general key — netcup, the NAS with the off-site backups, both Pis, the Mac Mini. One
directory, the whole estate.

So a shell here isn't access to a laptop, it's access to everything, plus the credentials to keep it.
I'd written a rule saying my phone must never reach the production server; leaving the phone able to
SSH *here* would have made that rule decorative, since the route runs straight through this machine's
`~/.ssh`. A denial you can walk around isn't a denial.

It also inverts the trust direction. The phone is the device most likely to be lost or stolen, and
this is the most privileged box in the house. And it doesn't serve the "run the house from the road"
goal it looked like it served — the laptop is in the same bag as the phone, while everything I'd
actually want remotely (the NAS, the DNS box, the Pis) is granted directly.

## The path that had to go, and why it cost nothing

`phone → this laptop` over SSH existed and was in daily use, so removing it was a real behaviour
change rather than tidying. The only thing it was ever used for was driving a terminal AI agent
running on the Mac from a phone terminal — deliberately avoiding the hosted remote-control feature,
for telemetry reasons.

The honest part: **that workflow already didn't work.** The phone session couldn't attach to the one
already running on the Mac — it forced a re-authorization and a resume, every time. So what looked
like giving up a daily path was really deleting something that had been quietly failing for weeks. It
went in the "refused" column with a note that the shape which *would* work is `tmux` on the Mac with
the phone attaching to it, and that reviving it means granting this back, deliberately and
temporarily.

## Turning the door off, not just papering over it

macOS **Remote Login** was on, so `tcp/22` genuinely answered over the mesh. The policy omission closes
that from the network side, but leaving the service running and relying on a rule elsewhere to hold it
shut is the same mistake as a firewall in front of a service you didn't need. Remote Login off, Remote
Desktop was already off, confirmed by there being no listener at all:

```bash
netstat -an | grep LISTEN | grep '\.22 '   # no output
```

Two controls, independent, and neither one is now the only thing standing between this laptop and the
rest of the mesh. That's the shape I want for the box that holds every key.