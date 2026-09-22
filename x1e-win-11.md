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

> ⚠️ **Never use "OS Optimized Defaults" or "Restore Factory Defaults"** in this machine's
> BIOS. It resets the iGPU setting and brings the boot hangs straight back, and it changes
> Secure Boot state, which would invalidate the PCR7 binding. Change individual options only.

The running theme of this file, which I did not set out to write about: **almost every tool
on this machine reported success it had not achieved, and every single time the thing that
caught it was a second, independent measurement.** Four separate instances below.

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

---

## 🔁 The pattern

Five separate investigations in this file, and the same shape in every one:

| tool | reported | reality | what caught it |
|---|---|---|---|
| Defender | `FullScanEndTime` set | scan was cancelled | event ID 1001 vs 1002 |
| `Get-ScheduledTask` | no rows | tasks existed, read denied | `schtasks` two distinct errors |
| `manage-bde -status` | `100% Encrypted` | zero protectors, unprotected | `Protection Status` field |
| `manage-bde -w` | "wiping in progress" | *(true — but no completion logged)* | the **other** event provider |
| `Win32_SystemDriver` | no RTCore service | driver files on disk | looking at the filesystem |

In every case the resolution came from a **different measurement**, never from asking the
same tool more insistently. And in the one case where I measured a physical quantity
independently — disk write throughput — it falsified the tool's success message immediately.

> A tool's account of its own success is the weakest evidence available.
