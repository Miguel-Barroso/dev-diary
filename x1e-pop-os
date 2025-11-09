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