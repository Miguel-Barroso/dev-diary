## 🧠 Dev Diary — Secure Networking Setup on Pop!_OS (X1 Extreme)

**Date:** 2025-11-08  
**Goal:** Route all application and web traffic through PIA VPN while keeping full access to my Tailnet (Tailscale) — treating it as my personal LAN anywhere in the world.

---

### 🔧 1. PIA VPN configuration

Switched the PIA client to **OpenVPN protocol** instead of WireGuard.  
Reason: WireGuard on Linux enforces strict kernel-level routing that conflicts with Tailscale’s `tailscale0` interface.  
OpenVPN provides a user-space tunnel that respects app-level exclusions.

Under **Split Tunneling**, I **added `tailscaled`** (`/usr/sbin/tailscaled`) to the list of apps that **bypass the VPN**.

Result:  
- All web and app traffic → routed through PIA  
- Tailscale daemon → communicates directly to the Tailnet and DERPs  
- No more broken connectivity when PIA is active

---

### 🧱 2. Firewall hardening (UFW)

Enabled and configured **UFW** (disabled by default on Pop!_OS) to allow only essential inbound traffic.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 41641/udp comment 'Tailscale peer traffic'
sudo ufw allow in on tailscale0
sudo ufw allow out on tailscale0
sudo ufw enable
```

### Result:
- Inbound internet traffic blocked by default
- Tailnet devices can reach this machine like a local LAN peer
- SSH accessible either locally or via Tailnet, depending on configuration

### 🌐 3. Final network behavior

| Traffic Type      | Route                     | Notes                                    |
|------------------|---------------------------|-----------------------------------------|
| Web / App         | PIA VPN (OpenVPN)         | Full outbound privacy and encryption    |
| Tailnet           | Direct via Tailscale      | Acts as a private LAN                    |
| Local LAN (192.168.x) | Split-tunneled through PIA (optional) | Still reachable           |
| Firewall          | Active (UFW)              | Deny incoming, allow outgoing, Tailscale allowed |

### ✅ 4. Outcome

Pop!_OS on my X1 Extreme is now fully hardened and privacy-protected:
- PIA handles all outbound web traffic
- Tailscale provides seamless access to my home network and servers
- UFW enforces strict inbound rules without breaking connectivity

Essentially:

A mobile workstation that behaves like it’s still on my home LAN — but with full VPN-level privacy and a hardened firewall.

## 🧰 Dev Diary — Fixing Slow sudo Response on Pop!_OS (X1E Gen1)

**Date:** 2025-11-09

**System:** ThinkPad X1 Extreme Gen 1 (Pop!_OS)  

### 🐢 Problem: Noticed a consistent ~10-second delay before any sudo command started running.

**Example:**
```
time sudo true
# real 0m10.065s
```
The delay occurred before any visible output or network activity, suggesting it wasn’t apt or I/O related.

### 🔍 Investigation
- Tested `sudo` responsiveness directly → confirmed delay independent of command.
- Suspected hostname or PAM resolution.
- Checked /etc/hosts — found only:
```
127.0.0.1 localhost
::1       localhost
```
- Ran hostname → x1e-pop-os
- Realized hostname missing from /etc/hosts.

### ⚙️ Fix
Added hostname to the localhost entry:
```
127.0.0.1   localhost x1e-pop-os
::1         localhost
```

### ⚡ Result

s‌udo response became instant:

```
time sudo true
# real 0m0.023s
```

## 🧠 Root Cause

`sudo` and PAM modules try to resolve the system’s hostname for logging/auth purposes.
Without a local entry, Linux falls back to DNS queries that time out (~10s).
Adding the hostname to /etc/hosts provides an immediate local resolution.

### 🪄 Lesson Learned

Always ensure /etc/hosts contains:

```
127.0.0.1 localhost <hostname>
```
to avoid slow `sudo` responses, especially on Pop!_OS, Ubuntu, or systems using systemd-resolved.

## Dev-Diary — Automounting NAS Shares over Tailscale (and accidentally learning how Linux boots)

### The goal

I’ve never really liked mounting SMB shares from Nautilus.
It *works*… but it never feels native. You click **Network → QNAP → Share**, it asks for credentials again someday for no clear reason, and every application treats the mount slightly differently. Sometimes it’s there, sometimes it isn’t, and CLI tools behave like the share lives in a parallel universe.

What I actually wanted was simple:

> My NAS should behave like a normal folder inside `$HOME`.

Not a “network location”.
Not a GUI session thing.
A real path.

```
~/QNAP/Multimedia
~/QNAP/Miguel
~/QNAP/Businesses
```

If a terminal, script, IDE, backup job, or media server touches that path — it should just work.

Even better: I wanted it to work **anywhere I bring my laptop**.

The trick that makes this possible is **Tailscale** (WireGuard-based mesh VPN). As long as both my laptop and my QNAP are logged into Tailscale, the NAS effectively exists on my local network no matter where I am. I won’t cover Tailscale setup here — only the Linux mounting part.

---

## The idea

Instead of GUI mounting, Linux can mount SMB shares directly using **CIFS** via `/etc/fstab`.

But we don’t want traditional mounts.

Traditional mounts try to mount during boot.

Network mounts + boot = pain.

I discovered this the hard way when my machine suddenly dropped into **emergency mode** because the NAS wasn’t reachable during startup. Linux interpreted that as a critical filesystem failure and refused to continue booting. Fun.

So the *correct* approach is not a boot mount.

It is a:

> **systemd automount**

Meaning:

* Linux does NOT mount the share at boot
* The folder exists immediately
* The share mounts the moment you access it
* It unmounts automatically when idle

In other words — perfect behavior.

---

## Step 1 — Store credentials safely

Create a credentials file:

```
sudo nano /etc/samba/cred-qnap
```

Contents:

```
username=YOUR_QNAP_USERNAME
password=YOUR_QNAP_PASSWORD
```

Very important:

```
sudo chmod 600 /etc/samba/cred-qnap
```

Otherwise Linux will refuse to use it for security reasons.

This file allows systemd to authenticate to the NAS without storing passwords inside `fstab`.

---

## Step 2 — Create mount folders

I keep all NAS mounts grouped:

```
mkdir -p ~/QNAP
mkdir -p ~/QNAP/Multimedia
mkdir -p ~/QNAP/Miguel
mkdir -p ~/QNAP/IT
mkdir -p ~/QNAP/Businesses
mkdir -p ~/QNAP/Ebihara\ Solutions
```

Now the paths exist even when the NAS is offline — important for scripts and software.

---

## Step 3 — Configure `/etc/fstab`

Open:

```
sudo nano /etc/fstab
```

Add:

```
# --- QNAP NAS (Tailscale) Automounts ---
# Multimedia
//100.x.x.x/Multimedia /home/mb/QNAP/Multimedia cifs _netdev,noatime,x-systemd.automount,x-systemd.idle-timeout=300,x-systemd.device-timeout=10,credentials=/etc/samba/cred-qnap,uid=1000,gid=1000,iocharset=utf8,vers=3.0,nofail 0 0

# Miguel
//100.x.x.x/homes/Miguel /home/mb/QNAP/Miguel cifs _netdev,noatime,x-systemd.automount,x-systemd.idle-timeout=300,x-systemd.device-timeout=10,credentials=/etc/samba/cred-qnap,uid=1000,gid=1000,iocharset=utf8,vers=3.0,nofail 0 0

# IT
//100.x.x.x/IT /home/mb/QNAP/IT cifs _netdev,noatime,x-systemd.automount,x-systemd.idle-timeout=300,x-systemd.device-timeout=10,credentials=/etc/samba/cred-qnap,uid=1000,gid=1000,iocharset=utf8,vers=3.0,nofail 0 0

# Businesses
//100.x.x.x/Businesses /home/mb/QNAP/Businesses cifs _netdev,noatime,x-systemd.automount,x-systemd.idle-timeout=300,x-systemd.device-timeout=10,credentials=/etc/samba/cred-qnap,uid=1000,gid=1000,iocharset=utf8,vers=3.0,nofail 0 0

# Ebihara Solutions
//100.x.x.x/Ebihara\040Solutions /home/mb/QNAP/Ebihara\040Solutions cifs _netdev,noatime,x-systemd.automount,x-systemd.idle-timeout=300,x-systemd.device-timeout=10,credentials=/etc/samba/cred-qnap,uid=1000,gid=1000,iocharset=utf8,vers=3.0,nofail 0 0
```

---

## What the important options actually do

| Option                | Why it matters                         |
| --------------------- | -------------------------------------- |
| `_netdev`             | tells Linux this depends on networking |
| `nofail`              | boot continues even if NAS is offline  |
| `x-systemd.automount` | mount on first access                  |
| `idle-timeout=300`    | auto-unmount after 5 minutes           |
| `device-timeout=10`   | prevents 2-minute boot freeze          |
| `uid/gid=1000`        | files belong to your user              |
| `noatime`             | faster browsing                        |
| `vers=3.0`            | QNAP SMB compatibility                 |

This combination turns a fragile boot mount into a lazy-loaded filesystem.

---

## Step 4 — Reload systemd

```
sudo systemctl daemon-reload
```

You do **not** need to reboot.

You can test immediately:

```
ls ~/QNAP/Multimedia
```

The moment that command touches the folder → Linux silently mounts the NAS.

---

## The result

Now my NAS behaves like a local disk:

* Works in terminal
* Works in IDEs
* Works in scripts
* Works in backup jobs
* Works over VPN
* No Nautilus weirdness
* No duplicate sidebar entries
* No password prompts

And best of all:

I can sit in a café, open my laptop, and:

```
cd ~/QNAP/Multimedia
```

…and I’m effectively at home.

No clicking.
No connecting.
No thinking.

Linux just mounts it on demand through an encrypted WireGuard tunnel.

Honestly this ended up being less about NAS mounting and more about finally understanding something fundamental:

> `/etc/fstab` is not just a mount list — it is part of the Linux boot process.

And if you give Linux a filesystem that might not exist yet…
Linux will simply refuse to boot.

Now it boots fast, mounts instantly, and my home server genuinely feels like part of the laptop.
