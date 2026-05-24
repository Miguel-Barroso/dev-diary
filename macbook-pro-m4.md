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

Lesson: on modern macOS, persistent path exports belong in `~/.zshenv`, not `~/.zshrc`. `.zshenv` is sourced for every zsh invocation (including non-interactive ones), and additive `export` statements compose cleanly with the defaults Apple ships.

Current `~/.zshenv`:

```bash
# Ruby gems installed via Homebrew
export PATH=$HOME/.gem/bin:$PATH

# Flutter
export PATH=$HOME/development/flutter/bin:$PATH

# Browser used by Flutter (verify via `flutter doctor`)
export CHROME_EXECUTABLE="/Applications/Chromium.app/Contents/MacOS/Chromium"

# Allow shell-style comments in interactive shells
setopt INTERACTIVE_COMMENTS
```

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

In Plex's network settings, registered the QNAP's Tailscale IP as a custom server access URL:

```
http://100.x.x.x:32400
```

Clients now resolve the server via Tailscale whether the device is on the home LAN, on cellular, or on hotel WiFi abroad.

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