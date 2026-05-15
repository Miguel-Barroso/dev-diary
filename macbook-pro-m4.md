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