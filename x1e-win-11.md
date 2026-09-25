# 🪟 Dev Diary — ThinkPad X1 Extreme Gen 1 on Windows 11

Same laptop as [`x1e-pop-os.md`](x1e-pop-os.md) — but **the dual boot is gone.** Pop!_OS is
retired, the SSD it lived on was pulled and repurposed as the CI drive on Astromeda (see
[Moving the CI VM, Docker and WSL onto a dedicated NVMe](astromeda-log.md#moving-the-ci-vm-docker-and-wsl-onto-a-dedicated-nvme)),
and this machine is now purely Windows 11 (build 26200). Linux work happens in a WSL2
Ubuntu 22.04 guest over `/mnt/c` interop instead, which is also where Claude Code runs.

Committing to a single OS is what made two of the entries below possible. Secure Boot had
been off for dual-boot reasons; with nothing else to boot, it went on and stayed on — and
that's the precondition for the PCR7 binding in the BitLocker entry.

**Hardware:** ThinkPad X1 Extreme Gen 1 (20MF000XMX) — i7-8750H, GTX 1050 Ti Max-Q,
Crucial P1 1 TB NVMe (QLC), TPM 2.0 (STM).

**Current state:** single-boot Windows 11 · Secure Boot **on** · BitLocker protected, TPM
bound to PCR 7+11 · **hybrid graphics back on** — the iGPU had been disabled in the BIOS,
which was the cause of this machine's boot hangs. Re-enabling it fixed them and restored
Optimus switching, so the discrete 1050 Ti is no longer driving the panel at idle.
P1 on firmware P3CR013 · no device in an error state · crash-on-hang armed · monthly
integrity + Defender tasks verified · Ultimate Performance kept on purpose (measured, below).

**Role since 2026-09-25:** a desk machine. Always on AC and Ethernet, never travels — a second
screen, Plex client, occasional gaming, dev in WSL. Battery charge held at 75–80 %. That
changed which optimisations were worth making: battery-life tuning stopped mattering, and
charge limits and link stability started to.

> ⚠️ **Never use "OS Optimized Defaults" or "Restore Factory Defaults"** in this machine's
> BIOS. It resets the iGPU setting and brings the boot hangs straight back, and it changes
> Secure Boot state, which would invalidate the PCR7 binding. Change individual options only.

The running theme of this file, which I did not set out to write about: **almost every tool
on this machine reported success it had not achieved, and every single time the thing that
caught it was a second, independent measurement.** The tally is at the bottom.

---

## 🔋 Dev Diary — The laptop that died when you picked it up

**Date:** 2026-09-25

For years this machine would occasionally just *go off* when carried around: no blue screen,
no freeze first, just dark. It's one of the reasons it lives on a desk stand now instead of
in a bag. I wanted to know if anything in the logs had ever explained it.

### Two populations of Kernel-Power 41

The full System log goes back to 2025-08 (36,787 events) and has eleven Event 41s ("the
system rebooted without cleanly shutting down"). Decoding the XML fields split them in two:

- **3** with `PowerButtonTimestamp != 0`. That's me holding the button during the boot hangs,
  which were already solved (see the iGPU entry below).
- **8** with `BugcheckCode = 0` **and** `PowerButtonTimestamp = 0`. No crash, no button.
  Power just went away, and Windows never got a chance to write anything. That's why they
  looked "unexplained".

What came right before each of the eight:

```
blackout           SleepInProg  min since   context
                                unplug/resume
2025-11-12 19:43        0          -        fingerprint driver installing
2025-11-13 10:00        0          -        4 min after the boot above; died again
2025-11-24 12:00        5        125        died ENTERING sleep; accelerometer event 10 min before
2025-11-29 18:58        0          -        mid-session
2026-03-23 11:05        0          3.7      Wi-Fi "Roam Complete" x2 -- literally being carried
2026-04-21 17:25        0          1.3      80 s after unplugging
2026-07-20 00:51        0          1.1      60 s after resume + unplug
2026-09-10 16:52        6          -        17 s after resume
```

Four of the eight are 1–4 minutes after going to battery or in the middle of a sleep
transition, and one has the laptop moving between access points. Nothing software-side came
before any of them: WHEA 0 in all history, zero bugchecks, NTFS healthy, no thermal events.

### A battery curve that went up

`powercfg /batteryreport` showed full-charge capacity *rising*, twice, and my first reading
was "those are battery replacements". The user corrected me: the replacements happened
before the log window. So what happened on those two dates was:

```
2025-11-17  cumulative update + reboot  ->  ACPI Event 15 x5 (EC returned unrequested data)
2026-02-13  Lenovo power-management driver updates + reboots  ->  ACPI Event 15 x5
```

Full-charge capacity **cannot physically go up**. A jump is the embedded controller's fuel
gauge re-initialising after a driver or firmware change. It then reports a stale estimate
until a real discharge forces it to relearn. That fits exactly: a dead-flat 71,980 mWh for
ten weeks on AC, then the 2026-04-21 unplug (dead in 80 s, followed by a "Sleep Reason:
Battery" critical sleep) relearned it down to 62,630 in a week.

With the artifact taken out, **all of the real capacity loss (~9 %) happened Sep–Dec 2025**,
and it's been flat since. That window has four of the eight hard cutoffs under load, and a
hard cutoff under load is about the worst thing you can do to a lithium pack.

### What I think it is

The pattern of death 17 s to 4 min after unplug or resume, never hours in, looks like
**voltage sag under a load spike**. Resume kicks off WSL, Defender and GPU init, the
8750H + 1050 Ti can pull 90–100 W for a few seconds, and a pack (or a battery path on the
board) with raised internal resistance sags below the BMS under-voltage cutoff. The BMS then
disconnects the cells instantly. Lenovo's battery diagnostic measures capacity and resting
voltage at low load, which is why it keeps passing.

Two things sped up the aging regardless: being held at 100 % on AC 24/7, and Ultimate
Performance idling the CPU at ~3.8 GHz right next to the pack. The first is now fixed
(threshold 75–80 %, set via Vantage and confirmed there).

Windows can't see below this layer, so there's nothing more to find in logs. The connector
was reseated in September when the Pop!_OS NVMe came out, and the machine hasn't been on
battery since, so whether that fixed it is **untested**. The cheap test, if it ever matters:
charged pack, unplug, resume from sleep, load a game for five minutes. On a desk, on AC, the
fault has no trigger.

> I got the battery swaps wrong because an upward step *looked* like a new pack. The better
> first question was "can this number physically go up?" It can't.

---

## 🖥️ Dev Diary — Tuning it as a desktop, and the power setting that does nothing

**Date:** 2026-09-25

Once it was settled that this machine never moves, some of the laptop defaults were working
against it.

### Applied

| change | why | rollback |
|---|---|---|
| Charge threshold 75 → 80 % (Lenovo `PWRMGRV` registry, then confirmed in Vantage) | lives on AC; calendar aging at 100 % is 2–3× faster | Vantage UI |
| I219-V Ethernet: EEE, Ultra Low Power Mode, Reduce Speed On Power Down → off | power-saving link states on a desk NIC are just a source of link renegotiation; Wake-on-Magic-Packet left on | set the three keywords back to 1 |
| Game DVR background recording off | constant background capture/encode for a feature I don't use | two registry values back to 1 |
| ~25 GB of orphaned WSL `swap.vhdx` in `%TEMP%` deleted | eleven GUID dirs from VM sessions that ended in a power-button shutdown; C: free 558 → 582 GB | — |
| Two dangling "Pop!_OS 22.04 LTS" UEFI boot entries removed | pointed at `\EFI\systemd\systemd-bootx64.efi` on an ESP with no `systemd` dir | — |
| Firefox Default Browser Agent task disabled | telemetry | re-enable the task |

The last three needed a human at an elevated prompt. Bulk temp deletion and boot-entry
removal are exactly the sort of thing an agent should hand back to you as a script rather
than do itself.

I also asked whether any partition on the 1 TB NVMe could go. No: it's EFI (260 MB), MSR
(16 MB), C: and Recovery (1.2 GB), and all four are load-bearing. The Pop partition went with
the other SSD.

### Measured and reverted: the idle clock

Ultimate Performance idles at **~3.8 GHz** (`% Processor Performance` ~175 % at 10–20 % busy).
The obvious lever, minimum processor state 100 → 5 %, did **nothing**: still 3.88 GHz. With
hardware P-states the CPU ignores the min-state floor while the energy-performance preference
(EPP) is 0. So I swept EPP, with 12-thread busy loops for the load column:

```
EPP   idle       all-core load
  0   ~3.8 GHz   ~3.6 GHz
 25   ~3.8 GHz   ~3.56 GHz
 40   ~3.1 GHz   ~3.0 GHz
 50   ~2.2 GHz   ~2.8 GHz
```

Every value that lowers the idle clock also cuts all-core turbo by ~20 %. Gaming is a real
workload here, so both went back to the Ultimate defaults. That finally closes the
power-plan question with numbers. (In an earlier session I'd switched to Balanced on a
generic "it runs hot" heuristic, with no temperature reading and no throttling observed, and
reverted it the same day.)

Gotcha: `powercfg /query` prints nothing for `PERFEPP` on this plan (hidden attribute), but
`/setacvalueindex` on it takes effect immediately.

### Checked and fine

Sleep/display timeouts already "never" on AC, hiberfil absent, Fast Startup off, TRIM on,
Storage Sense on, no throttling or WHEA events in 30 days, Plex is the desktop client only
and mpv is on hardware decode.

---

## 🔒 Dev Diary — BitLocker said 100% encrypted. It was completely unprotected.

**Date:** 2026-09-21
**System:** X1 Extreme Gen 1, Windows 11 26200

### The state I found

I went to enable BitLocker and the preflight aborted, because the volume was already
encrypted:

```
Conversion Status:    Used Space Only Encrypted
Percentage Encrypted: 100.0%
Protection Status:    Protection OFF
Key Protectors:       (none)
```

`100% encrypted` and **zero key protectors**. That combination means the volume master key
is sitting on the disk *unprotected*. Anything that can read the drive can recover it
without authenticating to anything. The machine had all of the performance cost of
encryption and none of the security.

Windows had done this by itself. **Automatic Device Encryption** fires on hardware that
meets the prerequisites, and it normally finishes the job when you sign in with a Microsoft
account — that sign-in is what escrows a recovery key and turns protection on. I don't use
a Microsoft account. So it encrypted the disk, had nowhere to put a key, and just… left it
like that. Indefinitely.

### The trap

`Percentage Encrypted: 100.0%` is the number a dashboard shows you. It is not the number
that means anything. The field that matters is `Protection Status`, and it read `OFF`.

I'd had an old recovery key in Bitwarden from 2020 and spent a while wondering whether it
was still valid. It wasn't, and it *couldn't* be: a recovery password binds to a specific
key-protector GUID, and this volume had no protectors at all. There was nothing for an old
key to match. The recovery screen shows you the first 8 characters of the protector ID
precisely so you can tell which key it wants — with zero protectors, that question has no
answer.

### The fix (and the wrong verb)

`Enable-BitLocker` is **not** the command here, and it correctly refuses: the volume isn't
decrypted, so there's nothing to enable. The data is already encrypted. What's missing is
protection. The right sequence:

```powershell
# 1. escape hatch FIRST, before anything locks
Add-BitLockerKeyProtector -MountPoint C: -RecoveryPasswordProtector
#    ... save the recovery password off this machine, verify it, THEN continue

# 2. the protector that makes it unlock without typing anything
Add-BitLockerKeyProtector -MountPoint C: -TpmProtector

# 3. the actual fix: turns protection ON and drops the unprotected key
manage-bde -protectors -enable C:
```

Step 3 is the whole thing. It's near-instant, because the data was already encrypted —
all it does is stop using a key that anyone could read.

Result:

```
Protection Status: Protection On
  RecoveryPassword  id={<recovery-key-id>}
  Tpm               id={<tpm-binding-id>}
```

### Secure Boot first, because of PCR7

I enabled Secure Boot in the BIOS *before* adding protectors, and it's worth explaining why
rather than treating it as generic hardening.

With Secure Boot off, BitLocker can't bind the TPM protector to **PCR7**. It falls back to
measuring PCR 0, 2, 4 and 11 — and **PCR0 covers system firmware**. Bind to PCR0 and a BIOS
update drops you at a recovery prompt. Bind to PCR7 and it doesn't, because PCR7 measures
Secure Boot *policy* rather than the firmware image.

Secure Boot being on does **not** guarantee you get PCR7, though. The first-party report is:

```
msinfo32 /report <file>    ->  "PCR7 Configuration: Binding Possible"
```

I wrote a parser for that line, it returned `indeterminate`, and that was a bug in my
parser — not a real result. Read the raw line. After a reboot, the binding was confirmed:

```
manage-bde -protectors -get C: -type tpm

  PCR Validation Profile:
    7, 11
    (Uses Secure Boot for integrity validation)
```

**7 and 11, not 0/2/4/11.** That's the tolerant binding, and it's the entire reason the
BIOS trip was worth making.

### The near-miss

I had the script print the recovery key and prompt `Type SAVED once it is in Bitwarden
(verify by reading it back there)`. Typed SAVED in good faith. A Bitwarden sync bug meant
the item had never actually reached the server.

Caught it **before** deleting the local key file and before the first reboot — i.e. before
the only two copies became one, and that one about to be tested.

Nothing was ever at risk, because of a fact worth knowing:

```powershell
# works any time the volume is unlocked and you are admin
manage-bde -protectors -get C: -type recoverypassword
```

An administrator can always read the recovery password off a *running, unlocked* volume.
That removes "I lost the key" as a failure mode entirely — right up until the machine stops
booting, which is exactly when you need it. Hence the off-machine copy.

**The prompt was the real bug.** "Verify by reading it back" asks you to confirm in the same
client that just lied to you. A read-back has to come from a **different client** — web
vault, phone — or you're re-reading the same unsynced local state.

And the ordering was wrong: I had reboot-then-save. The reboot is the first genuine test of
whether the TPM unseals; doing it with no confirmed off-machine copy is the one combination
worth avoiding.

### Standing rules that came out of this

- `Suspend-BitLocker -MountPoint C: -RebootCount 1` before **any** firmware, BIOS or TPM
  change. PCR7 tolerates a firmware image update but still measures Secure Boot policy, so
  a db/KEK change or a Secure Boot toggle will trip it.
- **Never use "OS Optimized Defaults" or "Restore Factory Defaults"** in this machine's
  BIOS. It would reset the iGPU setting that fixed this laptop's boot hangs, and it would
  change Secure Boot state. Change individual options only.

### Boot event 24641 is benign

Every boot logs, twice:

```
[24641] An unexpected error was encountered attempting to retrieve the
        BitLocker volume master key during restart.
```

It is not a fault, and it took a careful look to be sure:

- It occurs on boots from **before any key protector existed**. With zero protectors there
  is no master key to retrieve, so the error is the literally correct outcome. Pre-existing,
  not caused by anything I did.
- On every boot since, it's paired with `[24711] A V2 TPM protector was used to start
  Windows` — the unseal succeeded.
- "during restart" is a distinct path: the stashed key Windows uses to auto-resume across a
  *system-initiated* reboot, like a Windows Update restart. A manual restart stashes
  nothing, so the lookup fails. That fits the exactly-twice-every-boot regularity.

**Escalate only if a boot logs 24641 with no paired 24711.** That would mean the TPM path
failed too.

---

## 🧹 Dev Diary — The free-space wipe that failed three times and hadn't

**Date:** 2026-09-22

### Why wipe free space at all

Automatic Device Encryption always uses **Used Space Only**. Free space — including every
block belonging to a file you've deleted — stays plaintext. On this machine that included a
pile of logs containing a NAS credential in cleartext (see below), and the local copy of the
BitLocker recovery key.

`manage-bde -w C:` overwrites it.

### The story I told myself

I ran it. It reported `Free space wiping is now in progress.` and returned. Then:

- Disk writes fell to **0.08 MB/s mean, 99.9% idle**
- `manage-bde -status` showed no wipe line at all
- Free space, which had dropped 566 → 515 GB, went **back up** to 566
- `manage-bde -w C: -Cancel` → **"Wipe of free space is not currently taking place."**
- The `BitLocker Management` log had `[786] wiping was started` and **no completion event**

Conclusion: it registered, then died silently. I had the user run it again. Same thing.
And again. Three "silent deaths." I wrote a monitoring wrapper, added stall detection,
and finally recommended abandoning `manage-bde` for `cipher /w:C:`.

### What was actually happening

It completed. Every time. In 13 to 17 minutes.

```
Microsoft-Windows-BitLocker-Driver  (System log)
  17:51:11  [24649] Wiping of free space on volume C: started
  18:03:56  [24651] Wiping of free space on volume C: completed     12m 45s
  18:31:36  [24649] started
  18:48:30  [24651] completed                                       16m 54s
  16:39:44  [24649] started
  16:55:24  [24651] completed                                       15m 40s
```

**There are two BitLocker event providers.** I was reading
`Microsoft-Windows-BitLocker/BitLocker Management`, which logs the *start* of a wipe and
**never logs completion**. The completion events live in
`Microsoft-Windows-BitLocker-Driver` in the System log. I checked one source, found no
completion record, and treated that as evidence of failure instead of evidence about my
query.

Every downstream inference was then wrong in a mutually consistent way, which is what made
it so convincing:

| observation | what I concluded | what it meant |
|---|---|---|
| free space 566 → 515 → 566 | started, crashed, rolled back | ran, **completed**, released working space |
| writes fell to zero | the job died | the job **finished** |
| `Conversion Status` stayed `Used Space Only Encrypted` | wipe incomplete | that field **never changes** for a wipe |
| `wipe=n/a` for 41 straight minutes | not running | `manage-bde -status` doesn't report wipe progress here at all |

That third row is the worst of it. `Conversion Status: Fully Encrypted` as the completion
criterion was **my own invention**. I had explicitly flagged it as unverified — written the
words "don't let me send you chasing a phantom" — and then chased it anyway for two hours.

> Flagging an assumption is not the same as acting on the flag. If a criterion is
> unverified, verify it before letting it drive a conclusion.

Cost: two unnecessary 566 GB wipe passes, about 1.1 TB of writes. On a 1 TB QLC drive that's
roughly 1% of rated endurance, so no harm done — but it was pure waste.

**The check that would have caught it in five minutes:**

```powershell
Get-WinEvent -ListProvider *BitLocker*     # returns TWO providers. I queried one.
```

### Bonus: watching the QLC cliff live

Sampling `\PhysicalDisk(_Total)\Disk Write Bytes/sec` during a wipe shows the SLC cache
filling in real time:

```
write MB/s: 510, 507, 28, 8, 20, 48
```

Two samples at ~510 MB/s, then it falls off a cliff to native QLC write speed. Never
extrapolate a completion time from the first minute on one of these drives.

---

## 🕵️ Dev Diary — Two scheduled tasks that never went missing

**Date:** 2026-09-20

`Get-ScheduledTask` returned **nothing** for two maintenance tasks I'd registered. No error.
No rows. I recorded them as having mysteriously vanished, wrote a rebuild script, and
enabled an audit channel to catch whatever was deleting them.

They had existed the entire time.

`Register-ScheduledTask` assigns a default security descriptor granting only Administrators
and SYSTEM. Run non-elevated, `Get-ScheduledTask` **silently omits tasks whose SD denies the
caller read access** — no error, no row, indistinguishable from absence.

The discriminator, and it works without elevation:

```
schtasks /query /tn "<task name>"

  ERROR: Access is denied.                     -> EXISTS, SD denies read
  ERROR: The system cannot find the file...    -> genuinely absent
```

Always pair that with a **control on a name you know doesn't exist**, so you observe both
error strings in the same shell instead of assuming what the other one looks like.

The audit log later showed zero task-deletion records across 5,485 entries — consistent with
"never deleted" rather than "deleted before logging started."

Fix, so future unelevated checks tell the truth. PowerShell's `Register-ScheduledTask` has
no security-descriptor parameter, so this needs the COM API:

```powershell
# Administrators + SYSTEM full, Authenticated Users read-only.
# Same SD the in-box Microsoft tasks use.
$sddl = 'D:(A;;FA;;;BA)(A;;FA;;;SY)(A;;FR;;;AU)'

$svc = New-Object -ComObject Schedule.Service
$svc.Connect()
$root = $svc.GetFolder('\')
$reg  = $root.GetTask($name)
# 6 = TASK_CREATE_OR_UPDATE, 5 = TASK_LOGON_SERVICE_ACCOUNT
$root.RegisterTaskDefinition($name, $reg.Definition, 6, 'S-1-5-18', $null, 5, $sddl)
```

**This was the second time I made this exact mistake in a week**, the first being
`manage-bde -status C:` returning "An attempt to access a required resource was denied"
and me reading an empty `Get-BitLockerVolume` as "not encrypted."

> An empty result from an unprivileged query is not evidence of absence. Say explicitly
> which of *refused* or *empty* you observed, and don't conclude until you know.

---

## 📹 Dev Diary — QVR Pro won't open after sleep, and the fix that made it worse

**Date:** 2026-09-11 → 2026-09-23

After a wake, clicking QVR Pro Client did nothing visible. Its log said why:

```
connected to QVR Pro server <qnap-lan-ip>:6661
Server error: The bound address is already in use
```

The client binds a fixed local socket and has no working single-instance guard. The instance
from before the sleep survives with a dead session. The new one authenticates, connects, fails
to bind, and never shows a window. Reproduced live on 09-17: two PIDs, both with
`MainWindowHandle = 0`. The stale instances also explained two of the "QVR Pro Client is
delaying system shutdown" events.

### The watchdog I turned on

The client also logged `Agent disconnected` every ~5 minutes, and the `QvrProAgent` service
was Stopped/Manual. So I set it to Automatic. The spam stopped, and I called that fixed.

It was a **watchdog**. It relaunches the client through the `qvrpros://` handler whenever an
instance dies. Kill the clients and three new ones appeared within seconds, all parented to
`QVRProAgent.exe`, all decoding the same six camera streams: **668 % CPU** (238 + 227 + 203),
seconds of input lag across the whole machine, and more instances fighting over the socket
I was trying to free. I'd measured the log noise, not the thing I cared about.

Reverted to Stopped/Manual, QNAP's shipped default: 1 instance, 43 % CPU, zero bind errors.
Order matters when reverting: stop the watchdog *before* killing the clients. The log noise is
the correct trade.

### Exit code 0, nothing killed

Next I set up a scheduled task on resume to clear the stale instance. It fired, logged `resume:
clearing stale QVR instance(s)` / `done`, returned `0`, and the client was still alive.

QVR Pro Client runs **elevated from its own manifest**. No shortcut has the run-as-admin
bit. A medium-integrity `taskkill` gets "Access is denied", and the process reports blank owner,
path and command line to an unelevated caller (that's how you spot it). Exit code 0 meant
"taskkill ran", not "the process died".

Working version:

- Task **`RunLevel Highest`**, triggered on **Power-Troubleshooter Event 1** (the real resume
  event; see the sleep note in the iGPU entry), `AllowStartIfOnBatteries` because the default
  refuses to run on battery, which is exactly the lid-close case.
- The action waits with `ping -n 6 127.0.0.1`, **not** `timeout /t`. `timeout` needs an
  interactive console and fails outright under Task Scheduler, silently skipping the delay.
- Verified against a live, healthy client: 1 instance → 0 → clean relaunch, no bind error.

### 09-23: a second failure mode

The resume task worked: old client gone, no bind error. But the fresh client came up with its
main window **hidden**. It wasn't minimised or off-screen, just `visible=False`, while happily
streaming all six channels in the background. `ShowWindow(SW_SHOW)` brought back the frame
but the camera view never rendered, because its GL surfaces were never created while hidden.
Recovery that works: run the elevated cleanup task by hand (`Start-ScheduledTask "QVR resume
cleanup"`, callable unelevated), then launch normally.

Root cause still open. My suspect is display geometry changing mid-startup: the client
recorded the screen as 1670×939, Windows reports 1707×960.

---

## 📹 Dev Diary — QVR Pro Client writes the NAS password to disk in cleartext

**Date:** 2026-09-20

QNAP's QVR Pro Client stores its connection string in its own logfiles, in the clear:

```
qvrpros://admin:<secret>@<qnap-lan-ip>:6661
```

Found in 19 files spanning 2026-06-04 to 2026-09-17, including a `PanguDmp` HTTP capture
that had recorded the raw POST body to `/cgi-bin/authLogin.cgi` — so the password was there
twice over, as a URI and as a form field.

### Proving it was static, not a session token

A session token that leaks is bad. A permanent password that leaks is much worse, so it was
worth establishing which:

```bash
# extract every occurrence, hash each one, count distinct values
grep -rhoE 'qvrpros://[^:]+:[^@]+@' . \
  | sed 's/.*://; s/@//' \
  | while read -r s; do printf '%s' "$s" | sha256sum; done \
  | sort | uniq -c
```

**One distinct hash** across 3.5 months and many reboots. Static credential, 32 characters,
base64 alphabet, and the identity was `admin` — the NAS's full administrator.

Never print the secret to compare values. Hash it and compare hashes.

### Remediation

1. **Rotate on the NAS first.** Purging logs that contain a still-valid password achieves
   nothing.
2. Create a **scoped account** for the client instead of using `admin`. Confirmed via the
   NAS's own auth response that the new account reports `isAdmin: 0`.
3. *Then* purge — 187 files, 201 MB → 0.

### It recurs, and there's no setting to stop it

QVR rewrites the credential on every launch. There is no log-level toggle. So the mitigation
has to be recurring, which means it belongs in the monthly maintenance task — with one
non-obvious detail:

```powershell
# HARDCODED on purpose. The task runs as SYSTEM, where $env:APPDATA resolves to
# C:\Windows\System32\config\systemprofile\AppData\Roaming -- the wrong profile.
# The purge would find nothing and report success, which is worse than failing.
$qvrLog = 'C:\Users\<user>\AppData\Roaming\QNAP\QVRProClient\log'
```

It also skips rather than half-deleting if the client is running and holding the files open,
and logs the fact that it skipped — so the log says the credentials were *not* purged that
month, instead of leaving you to infer it from a file count.

---

## ⚔️ Dev Diary — Removing the ring-0 tools, and why

**Date:** 2026-09-22

I'd been wondering about reinstalling ThrottleStop for a bit of undervolting. Decided
against it, and then found the same problem already installed.

**MSI Afterburner** and **RivaTuner Statistics Server** ship `RTCore64.sys`, a driver that
exposes unrestricted ring-0 read/write to any caller that can reach it. It's a well-known
privilege-escalation primitive and it appears on vulnerable-driver blocklists. ThrottleStop
has the same problem via `WinRing0.sys`.

Keeping one of those resident while running Secure Boot with a PCR7 binding and a protected
volume key is incoherent — you'd have hardened the boot path and left a signed kernel
backdoor running on top of it.

Confirmed present on disk:

```
C:\Program Files (x86)\MSI Afterburner\RTCore64.sys              (and RTCore32)
C:\Program Files (x86)\MSI Afterburner\Legacy\RTCore*.sys
C:\Program Files (x86)\RivaTuner Statistics Server\Plugins\Client\RTCoreMini*.sys
```

**The check that nearly fooled me — again.** Querying for the driver *service* returned
nothing:

```powershell
Get-CimInstance Win32_SystemDriver -Filter "Name LIKE '%RTCore%'"   # empty
```

Empty, because the driver is loaded **on demand** when Afterburner runs. The files were
right there. Check the filesystem, not just the service list.

After uninstalling, verify the objective directly rather than trusting the uninstaller's
exit code:

```powershell
Get-ChildItem 'C:\Program Files (x86)','C:\Windows\System32\drivers' `
              -Recurse -Include 'RTCore*.sys','WinRing*.sys'
```

### On undervolting generally

Worth knowing before you bother: the voltage-offset MSR that ThrottleStop relied on was
disabled in microcode as the mitigation for **Plundervolt (CVE-2019-11157)**, and Lenovo
shipped that in ThinkPad BIOS updates. On a Coffee Lake machine with current firmware it
likely doesn't do the thing you remember it doing anyway.

And the premise is testable without installing anything. ThrottleStop fixes thermal and
power-limit throttling. If the machine isn't throttling, there's nothing to fix:

```powershell
# >100 = turbo, <100 = clocked below base i.e. throttled
Get-Counter '\Processor Information(_Total)\% Processor Performance' `
            -SampleInterval 5 -MaxSamples 60
```

Measure first. Then decide whether there's a problem worth trading boot integrity for.

---

## 🛡️ Dev Diary — A Defender full scan that actually finished

**Date:** 2026-09-19

Scheduled full scans had been silently not completing. Two things made this hard to see.

**1. `FullScanEndTime` is written whether or not the scan finished.** A cancelled scan sets
it just like a completed one, so it proves nothing on its own. The honest signal is the
event ID:

```
Event 1001 = scan FINISHED
Event 1002 = scan STOPPED before completion
```

**2. I wrote a probe that couldn't fail.** A one-liner that echoed `'started'`
unconditionally, whether or not a scan had actually begun. It dutifully reported success
while nothing ran. A probe whose output looks identical whether or not the thing happened
tells you nothing at all.

The working approach — throttled so the machine stays usable, since the scan pegs all
twelve threads for hours:

```powershell
Set-MpPreference -ScanAvgCPULoadFactor 50
& "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -Scan -ScanType 2 -CpuThrottling
```

`-CpuThrottling` honours `ScanAvgCPULoadFactor` for the scan's entire life, not just the
idle portion.

Result: 2 h 20 m 06 s, terminal event **1001**, zero detections. Mean CPU 435% and peak
604%, against 1047–1100% unthrottled.

Useful side finding: full scans on this box are **CPU-bound, not disk-bound** — the disk sat
90–99% idle throughout. Which meant the NVMe firmware flash I'd done the day before had no
bearing on scan duration, despite being the obvious suspect.

### The day before: a scan I couldn't stop

The first full scan (09-18) pinned the machine: `msmpeng` at **1,106 %**, disk 93.6 % idle.
`ScanAvgCPULoadFactor` was already 50, but `DisableCpuThrottleOnIdleScans = True` makes
Defender ignore it. Two things that did **not** work, both measured:

- `Set-MpPreference -DisableCpuThrottleOnIdleScans $false` applied and read back fine; the
  scan stayed at 1,100 %. **Scan parameters are read once, at scan start.**
- `Stop-ScheduledTask` put the task back to Ready while `msmpeng` stayed at 1,047 %. The scan
  lives in the `WinDefend` service and outlives whatever started it. Stopping the service
  isn't an option with Tamper Protection on.

What worked, 1,020 % → 3.1 % in 20 seconds:

```
MpCmdRun.exe -Scan -Cancel
```

Which is also how I learned that `FullScanEndTime` gets written for a *cancelled* scan, and
the "full scan overdue" nag clears with 16 minutes of coverage.

---

## 🧊 Dev Diary — Boot hangs caused by a BIOS setting for an OS I'd already deleted

**Date:** 2026-09-11 → 2026-09-17

The machine would sometimes hang solid about 2.5 minutes after boot, at the login screen,
display black, until I held the power button. Kernel-Power 41 with `BugcheckCode = 0` and
`PowerButtonTimestamp != 0`, and no crash dumps anywhere, because none were configured.

The one consistent correlate: `nvlddmkm` Event 14/153 (NVIDIA display driver faults) within
~20 s of **every** boot, good or bad.

### Making the next hang leave evidence

These hangs never bugcheck on their own, so step one was to make them produce a dump:

- `CrashOnCtrlScroll = 1` on **both** `kbdhid` and `i8042prt` (USB and the built-in keyboard),
  so Ctrl + ScrollLock ×2 forces a bugcheck.
- Kernel dump instead of minidump, **plus a dedicated dump file**. The pagefile was 2 GB
  system-managed, and Windows stages crash dumps through the pagefile. Setting
  `CrashDumpEnabled = 2` by raw registry write does **not** resize the pagefile the way the
  System Properties GUI does, so it would have looked applied and produced nothing.
  `DedicatedDumpFile` + `DumpFileSize = 8192` bypasses the pagefile entirely.

### Ruling out Fast Startup

Fast Startup was on, the classic suspect for this hang pattern. I turned it off (keeping
hibernate), and the very first true cold boot **hung anyway**, with the same `nvlddmkm` errors at
the same ~2.5 min mark. Ruled out. I left it off because it removes a confound.

### The actual cause

Then the user remembered: **the Intel UHD 630 was disabled in the BIOS**, years ago, for
Pop!_OS dual-boot compatibility. Pop was gone. The machine had been running discrete-only,
with the GTX 1050 Ti initialising a 4K eDP panel on its own at every boot and carrying every
power transition. Windows agreed: the iGPU wasn't just disabled in Device Manager, it was
absent from `Win32_VideoController` altogether.

Switched to **Hybrid Graphics** (Config → Display → Graphics Device):

```
nvlddmkm 14/153   every boot for 5 days before   ->   0 on every boot since
Kernel-Power 41   last one: the final discrete-only boot
```

Six boots later, including two firmware-update reboots: zero display-driver faults, zero dirty
shutdowns. The evidence that carries the conclusion is the error count going to zero, not
just the boots succeeding, since the hang was intermittent anyway. The Parsec virtual display
adapter, my other suspect, was re-enabled throughout, which clears it too.

Cleanup: the BIOS gives the 1050 Ti a different PCI subsystem ID in discrete vs hybrid mode, so
it left a ghost device node. I removed it by matching `IsPresent = False`, **never by name**.
The name matched the working GPU too.

### A retraction on the way

At one point I "found" that sleep never stuck: Kernel-Power Event 42 (entering sleep) and
107 (resume) were always ~1 s apart. That's an artifact. 107 is written on resume using a
timestamp captured at suspend entry. The real record is **Power-Troubleshooter Event 1**,
which has explicit `SleepTime` / `WakeTime`: 16-, 20-, even 69-hour sleeps. Sleep had been
fine for weeks.

---

## 🔥 Dev Diary — 11 of 12 cores, and the cap I shouldn't have set

**Date:** 2026-09-11

The machine felt slow. It wasn't throttling (`% Processor Performance` 110–135 %); every core
was busy. `vmmemWSL` was at **1,111 %**. The 97–99 % privileged time is just how Hyper-V
bills guest time to the host, not a driver problem.

Inside WSL it was one process: an MCP code-indexing server (`tokensave serve`) that Claude Code
starts every session, burning 10–12 cores and 8 GB of RAM at startup against a 4.5 GB SQLite
database with a 1 GB WAL that had never been checkpointed.

My first move was to cap WSL in `.wslconfig` at 8 CPUs / 12 GB. The user pushed back and they were right.
`processors=` is a ceiling, not a reservation. The Linux scheduler already scales per
workload, and `vmmemWSL` only takes host CPU on demand (load 0.17 once the burst settled). A
static cap throttles *every* workload forever to contain one bad process. Removed. The same
reasoning later killed a switch to the Balanced power plan.

What stayed in `.wslconfig` is dynamic: `autoMemoryReclaim=gradual` and `sparseVhd=true`.
**Gotcha:** on WSL 2.7, `autoMemoryReclaim` belongs under `[experimental]`, not `[wsl2]`. It
sat in the wrong section for five days with WSL printing `Unknown key` at every launch, and
I'd reported it as verified. My evidence was a low `vmmemWSL` working set on a freshly
restarted idle VM, and that shows nothing about reclaim. A real test is to measure after
freeing a large allocation.

The one real I/O fix came later. Defender had three PyCharm folders excluded but not the
34 GB `ext4.vhdx`, so every WSL read and write went through `WdFilter` against an image
it can't meaningfully inspect. I excluded the vhdx (found by glob, not a hardcoded package
name), `vmmemWSL` and `wslservice.exe`. I deliberately did **not** exclude `vmcompute.exe`,
because that would cover every Hyper-V guest.

---

## 🐢 Dev Diary — WmiPrvSE at 41 % of a core, and why my first probe couldn't find it

**Date:** 2026-09-18

A `WmiPrvSE` burning **41 % of one core, permanently**, about 7.4 hours of CPU per 22 hours.
To find out who's calling WMI, the `WMI-Activity/Operational` channel is useless: it logs
provider starts and errors only. The analytic channel has the caller:

```powershell
wevtutil sl Microsoft-Windows-WMI-Activity/Trace /e:true /q:true
# ...45 s...
wevtutil sl Microsoft-Windows-WMI-Activity/Trace /e:false /q:true
Get-WinEvent -LogName Microsoft-Windows-WMI-Activity/Trace -Oldest   # -Oldest is mandatory
```

```
id 24  Executing polling query select * from Win32_Process
       ClientProcessId = <pia-service>; IntervalMs = 100
```

**Private Internet Access** re-enumerates the entire process table every 100 ms to drive its
app-based split tunnel. Don't regex the rendered `Message` to pair events: id 24 has the query
and the client PID but no provider, and id 12 has the provider and host PID but no client. Correlate
`$_.Properties[n]` on `GroupOperationId`.

**Left in place on purpose.** Split tunnel is what keeps Parsec, QVR and Tailscale out of
the VPN. ~3.4 % of a 12-thread machine is a real cost, but the feature is worth more.

The more useful lesson is why the 09-11 sweep missed it. Re-running that exact
`Get-Process | Sort CPU` a week later put `WmiPrvSE` first by 2.7×. But I'd run it at **2 m 44 s
of uptime**, when lifetime CPU seconds can't separate anything. And the rate probe I wrote
to catch sustained consumers measured four hardcoded process names, all of them suspects I
already had.

> A probe filtered to your suspects can only confirm them. Sweep unfiltered first, then
> narrow.

---

## 🦊 Dev Diary — Striped image uploads that weren't a graphics bug

**Date:** 2026-09-18

Images uploaded to ChatGPT from Firefox arrived as coloured stripes. The preview before
sending was fine; the sent image was corrupt. Because the symptom was visual, I spent four
rounds on the graphics stack: GPU preference for hybrid graphics, forcing acceleration,
disabling canvas acceleration (which changed the stripe *colours*, a clue I misread), and an
Intel driver update.

It was `privacy.resistFingerprinting = true` in `prefs.js`. RFP deliberately returns noise
from canvas readback (`getImageData`/`toDataURL`/`toBlob`) to defeat fingerprinting. ChatGPT
downscales uploads through a canvas, so the bytes it uploaded really were noise. The preview
used a plain `<img>`, with no readback involved.

The proof harness was a local page that draws an image to a canvas and calls `getImageData()`
**twice**:

| condition | self-diff between two reads | mean pixel error |
|---|---|---|
| RFP on | **100 % of bytes** | 122 / 255 |
| RFP off | 0 | 1.4 / 255 |
| RFP on + per-site canvas allow | 0 | 1.4 / 255 |

No hardware fault makes two consecutive reads of an unchanged canvas differ in every byte.
That's deliberate randomisation. The same file from ungoogled-chromium was clean, which had
already ruled out memory.

Fix: a per-site "Extract canvas data" permission, with RFP left on. The prompt had never
appeared because `privacy.resistFingerprinting.autoDeclineNoUserInputCanvasPrompts` silently
declines it. Also: force-killing Firefox once dropped the RFP pref from `prefs.js`. Quit it
normally, and never edit `prefs.js` while it's running.

> A visual symptom isn't a graphics cause. Read the user config before touching drivers, and
> try a second browser before suspecting hardware.

---

## 💾 Dev Diary — Flashing the NVMe without the vendor's broken boot ISO

**Date:** 2026-09-18

The Crucial P1 was still on its launch firmware, P3CR010. Crucial ships P3CR013 as a bootable
TinyCore ISO, and its UEFI path **cannot work**: `BOOTX64.EFI` embeds no `fat` or `search`
module, so it can't even read a FAT32 stick, and `GRUB.CFG` has no `set root` and no `menuentry`.
It hangs at "Welcome to GRUB!". The legacy path would have worked, but CSM was unavailable
because Kernel DMA Protection pins the BIOS to UEFI-only, and turning off VT-d for a
firmware flash is disproportionate.

The firmware isn't on the ISO filesystem anyway. It's inside the initrd:

```bash
zcat COREPURE.GZ | cpio -idm 'opt/firmware/*'    # -> opt/firmware/P3CR013/1.bin
```

And Windows can flash NVMe firmware natively. The drive reported two slots, both writable,
active slot 1, so I flashed the **inactive** slot and kept the old firmware as a fallback:

```powershell
Get-StorageFirmwareInformation            # check this BEFORE building any boot media
Update-StorageFirmware -ImagePath .\1.bin -SlotNumber 2
```

After reboot: `P3CR013`, Healthy, no stornvme/NTFS/WHEA errors, and a `chkdsk /scan` an
hour later came back clean.

---

## 🧰 Dev Diary — Driver updates by hardware ID, and a maintenance script that had never run

**Date:** 2026-09-17 → 2026-09-18

### Optional updates with useless names

Windows Update offered twenty optional drivers with names like `INTEL - System - 1/1/1970 -
10.1.1.42`. The Windows Update Agent COM API gives you the hardware IDs:

```powershell
$s = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
$s.Search("IsInstalled=0 and Type='Driver'").Updates |
  select Title, DriverHardwareID, DriverVerDate
```

Matching on `DriverHardwareID` showed the 1970 one was the driver for the yellow-triangle GNA
device (`PCI\VEN_8086&DEV_1911`, Problem 28), which had been there forever. I installed that
plus ME firmware 12.0.93.2331. Afterwards
`Get-PnpDevice -PresentOnly | ? Status -ne 'OK'` returned **nothing** for the first time.

Skipped on purpose: a "BIOS 1.51" that was already installed, a 2018 Realtek/Dolby/SST audio
bundle that would have downgraded a working stack, and the **Intel XTU** driver, whose
`iqvw64e.sys` is a known bring-your-own-vulnerable-driver target. TPM firmware is only
worth doing deliberately, with BitLocker suspended.

### The maintenance battery

`run-maintenance.ps1` (monthly: `chkdsk /scan` → DISM → `sfc` → ReTrim → `cleanmgr`) had been
scheduled but never actually run. First real run: 41 minutes, all exit 0, 0 bad sectors,
4.6 GB reclaimed.

- **DISM before SFC.** SFC repairs *from* the component store.
- **ReTrim, never defrag**, on QLC NAND.
- DISM prints `The restore operation completed successfully` whether or not it repaired
  anything. `dism.log` / `CBS.log` are the only way to tell. (It repaired nothing.)
- The cleanmgr profile explicitly **deselects the crash-dump handlers**, or the monthly
  cleanup would delete the very dumps Ctrl+ScrollLock is armed to capture.

Task Scheduler gotchas I hit along the way:

- `schtasks /TR` strips nested double quotes and then parses what was inside them as its own
  switches: `"Start-MpScan -ScanType FullScan"` became an unknown option `-ScanType`. Make
  every action a space-free, quote-free `.ps1` path.
- `schtasks /SD` parses dates in the machine's **short date pattern**. This box says `en-US`
  but has it overridden to `yyyy-MM-dd`, so both a hardcoded format and a culture guess
  fail. Use `New-ScheduledTaskTrigger -At <DateTime>` for anything dated.
- `New-ScheduledTaskTrigger` writes `StartBoundary` in **UTC**. On a UTC+9 machine, check
  it by parsing back with `.ToLocalTime()`.
- `DeleteExpiredTaskAfter` never fires unless the trigger also has an `EndBoundary`.

---

## 🔁 The pattern

The same shape shows up again and again in this file:

| tool | reported | reality | what caught it |
|---|---|---|---|
| Defender | `FullScanEndTime` set | scan was cancelled | event ID 1001 vs 1002 |
| `Get-ScheduledTask` | no rows | tasks existed, read denied | `schtasks` two distinct errors |
| `manage-bde -status` | `100% Encrypted` | zero protectors, unprotected | `Protection Status` field |
| `manage-bde -w` | "wiping in progress" | *(true — but no completion logged)* | the **other** event provider |
| `Win32_SystemDriver` | no RTCore service | driver files on disk | looking at the filesystem |
| QVR client log | "Agent disconnected" spam stopped | watchdog respawn loop, 668 % CPU | counting processes |
| resume task (LIMITED) | exit 0, "done" | `taskkill` denied, client alive | instance count before/after |
| `.wslconfig` | low `vmmemWSL` working set | key in the wrong section, ignored | WSL's own startup warning |
| DISM | "completed successfully" | printed either way | `dism.log` / `CBS.log` |
| Kernel-Power 42 → 107 | 1-second sleeps | 16–69 hour sleeps | Power-Troubleshooter Event 1 |
| battery report | capacity went *up* 9 Wh | fuel-gauge reset | a real discharge relearning it |

In every case the resolution came from a **different measurement**, never from asking the
same tool more insistently. And in the one case where I measured a physical quantity
independently — disk write throughput — it falsified the tool's success message immediately.

> A tool's account of its own success is the weakest evidence available.
