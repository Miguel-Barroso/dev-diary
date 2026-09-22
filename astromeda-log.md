# Astromeda — Windows Host Notes

Astromeda is my Windows gaming PC, and without ever deciding to, I've made it the busiest machine in the house: Minecraft Bedrock servers in Docker, Plex (moved off the NAS), the WSL2 Ubuntu install I actually work in, and a Hyper-V VM running the self-hosted CI for a private project. These notes started as a Minecraft migration log and have grown into a log for the host as a whole.

16 logical CPUs and 64 GB of RAM, which matters later — the machine is not the bottleneck, the disk was.

---

## Initial recovery and migration

*(undated — predates the multi-server entry below)*

### What was done

1. **Copied server files.** Transferred the full `Minecraft Bedrock Server` folder from the QNAP NAS to `D:\Docker\Minecraft Bedrock Server` on the local machine.

2. **Docker setup.** Installed Docker Desktop, navigated to the server folder, and ran:
   ```bash
   docker compose up -d
   ```
   This pulled and deployed the latest images for:
   - `itzg/minecraft-bedrock-server`
   - `containrrr/watchtower`

3. **Firewall loopback exception.** Added a loopback exemption so the host machine can also play locally:
   ```
   CheckNetIsolation.exe LoopbackExempt -a -p=S-1-15-2-1958404141-86561845-1752920682-3514627264-368642714-62675701-733520436
   ```

4. **Backup automation.** Updated `backup-world-silent.bat` and registered it with Windows Task Scheduler for daily automatic backups to OneDrive. Tested and confirmed working.

5. **Performance tuning.** Configured `.wslconfig` to disable swap for more predictable memory behaviour:
   ```ini
   [wsl2]
   swap=0
   ```

### Outcome

Server runs smoothly, fully Dockerized, no swap.

> **Updated 2026-08-17.** The host was on Ubuntu 22.04 LTS under WSL2 when this was written; it now runs **Ubuntu 24.04 LTS**. Worth being precise about the memory figure, because it misled me later: the machine has 64 GB of physical RAM, but that is not what the containers get. With `memory=0` in `.wslconfig`, WSL2 takes its default allocation and the Linux VM sees **~31 GiB**. `swap=0` is still set.

> **Updated 2026-09-11.** Every `D:\` path in this section now reads `N:\`. The
> Docker data root, the Bedrock server folder and the WSL2 distro itself all
> moved to a dedicated NVMe volume — see
> [Moving the CI VM, Docker and WSL onto a dedicated NVMe](#moving-the-ci-vm-docker-and-wsl-onto-a-dedicated-nvme).
> `.wslconfig` is untouched by that move (`memory=0`, `processors=0`, `swap=0`),
> so the ~31 GiB figure above still holds.

---

## Running multiple Bedrock servers with Docker

**Date:** 2026-05-04

### Goal

Run multiple Minecraft Bedrock servers on a single machine while keeping:

- Clean separation of worlds
- Stable networking
- Automated backups
- Minimal manual intervention

### Key constraint

A Minecraft Bedrock server binds one UDP port, so running several on one host means each one needs its own. The part that is easy to get wrong is *where* you change the port.

- Each server gets its own port via `SERVER_PORT` (and `SERVER_PORT_V6`), so it **binds** that port inside the container
- The Docker mapping is then **identical on both sides** — `19134:19134/udp`, not `19134:19132/udp`

Do not leave every container bound to `19132` internally and simply remap it externally. Bedrock advertises its own port in the ping response it sends to clients, so a container that binds `19132` keeps announcing `19132` regardless of what the host maps in front of it. Matching both sides keeps what the server says about itself true.

One more reason the ports look odd: `SERVER_PORT_V6` defaults to one above the IPv4 port, so the first server occupies **19132 and 19133**. That is why the second server is on `19134` and not `19133` — `19133` was never free.

### Docker setup

Base image:

```
itzg/minecraft-bedrock-server
```

This image:
- Automatically downloads the latest Bedrock server
- Uses `/data` for worlds and configs
- Exposes UDP port `19132`

### `docker-compose.yml`

```yaml
services:
  rhens-world:
    image: itzg/minecraft-bedrock-server
    container_name: bedrock-rhens-world
    ports:
      - "19132:19132/udp"
    environment:
      EULA: "TRUE"
      SERVER_NAME: "Rhen's World"
      SERVER_PORT: "19132"
      SERVER_PORT_V6: "19133"
      ENABLE_LAN_VISIBILITY: "true"
      ENABLE_RCON: "true"
      RCON_PASSWORD: "<RCON_PASSWORD>"
    volumes:
      - ./rhens-world/data:/data
    restart: unless-stopped
    tty: true
    stdin_open: true

  big-earth:
    image: itzg/minecraft-bedrock-server
    container_name: bedrock-big-earth
    ports:
      - "19134:19134/udp"   # second server — same port both sides
    environment:
      EULA: "TRUE"
      SERVER_NAME: "Big Earth"
      SERVER_PORT: "19134"
      SERVER_PORT_V6: "19135"
      ENABLE_LAN_VISIBILITY: "true"
      ENABLE_RCON: "true"
      RCON_PASSWORD: "<RCON_PASSWORD>"
    volumes:
      - ./big-earth/data:/data
    restart: unless-stopped
    tty: true
    stdin_open: true
```

### LAN discovery

Minecraft Bedrock uses broadcast discovery on fixed ports, and Docker isolates broadcast traffic by default. Result: the servers do not show up on their own in the in-game **Friends** list, and players have to add them by address instead. That much is expected behaviour in Docker environments.

> ⚠️ **Correction (2026-08-13).** This entry used to recommend
> `enable-lan-visibility=false` as the workaround for that. **The advice was
> wrong — do not follow it.** It does not switch off a discovery mechanism that
> wasn't working anyway; it makes the server unjoinable by *any* means,
> including a direct address. It cost me a server for months. Full diagnosis in
> the next section. Both servers now run `enable-lan-visibility=true`.

Leave the setting alone and have players connect by direct address:

| Server       | Address              |
| ------------ | -------------------- |
| Rhen's World | `192.168.x.x:19132`  |
| Big Earth    | `192.168.x.x:19134`  |

### `enable-lan-visibility=false` makes a server unjoinable (2026-08-13)

Big Earth sat unjoinable for a long time, and the container reported `unhealthy` forever. Two symptoms that looked like two faults; one root cause, and it was the line I'd recommended above.

**What it actually does.** BDS still answers the RakNet unconnected ping with the setting off — but with its identity string stripped. A **33-byte pong instead of ~130 bytes**: no server name, no version, no protocol number, no player count. The Bedrock client needs that payload to decide a server is joinable, so it marks the entry unreachable and never attempts a connection at all. The healthcheck fails for the same reason — the image runs `mc-monitor status-bedrock`, which reports `empty response from bedrock server`.

**Why it wastes so much of your time.** Everything underneath is genuinely healthy, and every test you'd reach for first says so. Probe the port from outside with an `open connection request 1` and you get a valid `0x06` reply, byte-for-byte the shape of the working server's. Port mapping, NAT and the Windows firewall all exonerate themselves in turn, which sends you looking further out into the network — the one direction the fault isn't in.

**The test that actually discriminates.** Compare the *size* of the ping payload against a server you know works. A pong that arrives but is short means config, not connectivity:

```bash
python3 -c 'import socket,struct,time
M=bytes.fromhex("00ffff00fefefefefdfdfdfd12345678")
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.settimeout(3)
s.sendto(b"\x01"+struct.pack(">Q",int(time.time()*1000))+M+struct.pack(">Q",2),("<windows-host-ip>",19134))
d,_=s.recvfrom(4096);print(len(d),d[35:])'
```

~130 bytes and a readable server name is healthy. 33 bytes is this bug.

**Lesson.** "Disable the thing that isn't working" was a guess dressed up as a fix, and I wrote it down as a recommendation without ever confirming a client could still join afterwards. A setting that silently degrades a response — rather than refusing outright — buys itself months before anyone catches it.

### Folder structure

```
N:\Docker\Minecraft Bedrock Server\
├── rhens-world\
│   └── data\
│       ├── worlds\
│       ├── server.properties
│       ├── allowlist.json
│       └── permissions.json
├── big-earth\
│   └── data\
│       └── ...
└── scripts\
    └── backup-all.bat
```

> **Path updated 2026-09-11** (`D:` → `N:`). The bind mounts in
> `docker-compose.yml` are *relative* (`./big-earth/data:/data`), so relocating
> the whole tree was `docker compose down --timeout 60`, move the folder, then
> `docker compose up -d` from the new location — nothing in the compose file
> changed. One trap: Compose derives the **project name from the folder name**,
> so the directory has to stay called `Minecraft Bedrock Server` or Compose
> treats the stack as brand new and you get a second set of containers next to
> worlds it no longer thinks it owns.

### Backup strategy

Use Bedrock's built-in safe backup commands:

```
save hold
(copy files)
save resume
```

This ensures no world corruption and produces consistent snapshots.

Although Bedrock also supports `save query`, it is hard to reliably automate in Docker and can hang or misbehave. Final approach: use a fixed delay (~10 seconds) instead of polling.

### Backup script design

Key features:
- Freezes both servers
- Waits 10 seconds
- Copies worlds and config
- Creates a timestamped ZIP
- Logs everything
- Resumes the servers

Example flow:

1. `save hold` (both servers)
2. wait 10 seconds
3. copy world data
4. compress backup
5. `save resume`

### Logging

All output redirected to `backup.log`. Debuggable, works headless with Task Scheduler, no UI required.

### Automation

Configured via Windows Task Scheduler:
- Runs daily
- Runs whether the user is logged in or not
- Uses highest privileges

### Performance tuning

With two servers running concurrently:

| Setting         | Value |
| --------------- | ----- |
| `max-threads`   | 5     |
| `view-distance` | 16    |

Prevents CPU contention and maintains smooth gameplay.

### Access control

`allowlist.json` lists who may join, and `permissions.json` grants admin rights, both keyed on a player's XUID:

```json
// allowlist.json
[
  { "ignoresPlayerLimit": false, "name": "<gamertag>", "xuid": "<xuid>" }
]
```

```json
// permissions.json
[
  { "permission": "operator", "xuid": "<xuid>" }
]
```

> ⚠️ **Correction (2026-08-17).** Written as though populating `allowlist.json`
> were sufficient. It isn't, and on this host neither file is doing what the
> section implied:
>
> - **`allow-list=false`** on both servers. The allowlist file exists and has
>   names in it, but the server never consults it — anyone who can reach the
>   port can join. A populated allowlist that isn't switched on looks exactly
>   like a working one.
> - **`online-mode=false`** on both, which is the more interesting half. That
>   disables Xbox Live authentication, so the XUID a client presents is simply
>   asserted, not verified. Since *both* files key on XUID, turning the
>   allowlist on while `online-mode` stays off gives you a door with a lock
>   whose key anyone can claim to hold — including the `operator` grant in
>   `permissions.json`.
>
> Both values are set in each `server.properties`, not in `docker-compose.yml`.
> That matters for the itzg image: it leaves already-persisted properties alone,
> so adding `ALLOW_LIST` or `ONLINE_MODE` to compose later will *not* override
> what's on disk. Edit the properties file, or the change will look applied and
> do nothing.
>
> This is an acceptable trade on a LAN behind NAT, where reaching the port at
> all means you're already in the house, and it saves the friction of Xbox
> sign-in for local players. It stops being acceptable the moment either port is
> forwarded — that's the point to turn `online-mode` on **first**, then the
> allowlist, in that order.

### Outcome

A single Windows machine now functions as a multi-instance Minecraft hosting environment with proper isolation, automation, and reliability.

---

## Moving the CI VM, Docker and WSL onto a dedicated NVMe

**Date:** 2026-09-11

### Why

Everything I/O-heavy on this box lived on `D:`, an 8 TB **SMR** archive drive. SMR is
close to a worst case for these particular workloads: container layer writes, SQLite
commits and a CI VM's VHDX are small, scattered and often synchronous, and shingled
recording turns those into read-modify-write across a whole zone band. The drive is fine
for what I bought it for — bulk media that gets written once — and quietly awful for a
build server.

Meanwhile a Samsung 1 TB NVMe (PM981a, `MZVLB1T0HALR-000L7`, disk 2) was sitting in the
machine holding a Pop!\_OS install I had not booted in months. The plan: back it up, wipe
it, and give it entirely to the things that hurt on SMR.

> **Provenance, for the record:** that Pop!\_OS install is the one written up in
> [`x1e-pop-os.md`](x1e-pop-os.md) — the drive came out of the ThinkPad X1 Extreme, which
> has since stopped dual-booting and gone purely Windows 11. So this CI drive and the end of
> that laptop's dual boot are the same event seen from two ends. Dropping the dual boot is
> also what let Secure Boot go back on over there, which turned out to matter for BitLocker:
> see [`x1e-win-11.md`](x1e-win-11.md).

### Getting the disk away from Windows long enough to read it

Before wiping, I wanted the LUKS partition's contents. The old layout was EFI 1 GB /
recovery 4 GB / **LUKS2** 88.9 GB (argon2id, LVM, 70 GB ext4 root) / swap 4 GB /
856 GB NTFS "shared", the last of which held nothing but chkdsk debris and Xbox games.

WSL2 can take a whole physical disk with `wsl --mount \\.\PHYSICALDRIVE2 --bare`, which is
the tidiest way to read a Linux filesystem from a Windows host. It failed:

```
ERROR_DRIVE_LOCKED (0x8007006c)
```

Not a Linux problem and not a BitLocker problem — Windows itself had the disk open.
Three services had to let go of it first:

```powershell
Stop-Service WSearch, GamingServices, GamingServicesNet   # plus close the Xbox app
mountvol E: /P                                            # drop the drive letter
Set-Disk -Number 2 -IsOffline $true
wsl --mount \\.\PHYSICALDRIVE2 --bare
```

Inside WSL the disk shows up as a plain `/dev/sd*`, and the WSL2 kernel ships `dm-crypt`
as a loadable module, so after `apt install cryptsetup-bin lvm2` and `modprobe dm_crypt`
the LUKS volume opens normally and the LVs mount.

⚠️ **The trap is what those three commands leave behind.** Taking a disk offline and
removing a drive letter are *persistent* — they survive reboots. If a disk "vanishes"
weeks later, this is why. The undo is `Set-Disk -Number 2 -IsOffline $false` and
`Start-Service WSearch`, and I now treat reverting it as part of the job rather than
something to notice later.

### One partition, not four

My instinct was to carve the new volume into separate partitions per workload — CI here,
Docker there — for isolation. That instinct is wrong on this hardware, for two reasons:

- The things being stored are **dynamically expanding VHDX files**. Fixed partitions
  don't reserve them anything; they only impose ceilings that I'd eventually have to
  resize around.
- A single NVMe device has **one queue**. Partition boundaries are an addressing
  convention, not an I/O boundary, so two partitions on one SSD contend exactly as much as
  two folders do. The isolation would have been imaginary.

So: one GPT/NTFS volume, `N:` (label `FASTCI`, 953.85 GB), 64 KB allocation unit, 8.3
name creation off, Search indexing off.

### BitLocker encrypted it before I could choose the cipher

I intended `XTS-AES 256`. I got 128, and the reason is worth writing down: the moment `C:`
became BitLocker-protected, **Windows Automatic Device Encryption claimed the fresh
volume** (event 4146) and started encrypting at the 128-bit default — about two seconds
before my `Enable-BitLocker -EncryptionMethod XtsAes256` ran, which made that argument a
silent no-op.

I left it at 128 deliberately. There is no practical attack on AES-128-XTS, and 256 costs
~40% more AES rounds on a volume whose entire purpose is absorbing heavy CI writes. To
actually get 256 on a future volume, the policy has to exist *before* the volume does:

```powershell
# HKLM:\SOFTWARE\Policies\Microsoft\FVE
EncryptionMethodWithXtsFdv = 7   # XTS-AES 256, fixed data drives
```

⚠️ **Second BitLocker gotcha, on both this volume and `C:`:** encryption ran to
completion and then sat at `ProtectionStatus: Off`. Encrypted but not protected is a
strange half-state to be in while believing you're done. `Resume-BitLocker` fixes it, and
`Get-BitLockerVolume` is worth checking after *any* new volume is encrypted rather than
trusting that "it finished" means "it's on".

### The moves themselves

Three tenants, three different mechanisms, and only one of them is a thing you'd guess:

**The Hyper-V CI VM** — `Move-VMStorage`, which relocates VHDX, configuration, snapshots
and smart paging together and does it live. 10.6 minutes, and the runner was back online
afterwards without intervention. Its config and checkpoints had been scattered under
`C:\ProgramData\Microsoft\Windows\Hyper-V`; now everything sits in one folder per VM.

**Docker Desktop** — there is **no disk-image key in `settings-store.json`**. The data
root is recorded in the *WSL registry*, at
`HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss\{guid}\BasePath` for the
`docker-desktop` distro. It's tempting to edit that and move the files by hand. Don't:
Settings → Resources → Advanced → Disk image location does the move safely, and a mistake
here costs every container, volume and config on the machine — including Plex's.

**The WSL2 Ubuntu distro** — exported and re-registered on `N:` the same way.

Result:

```
N:\HyperV\mimir-ci\Virtual Hard Disks\mimir-ci.vhdx   # CI VM
N:\Docker\DockerDesktopWSL\                           # Docker images, containers, volumes
N:\Docker\Minecraft Bedrock Server\                   # Bedrock worlds (plain host files)
N:\WSL\Ubuntu-24.04\                                  # the distro I work in
```

⚠️ **`D:\Docker` is still live and must not be deleted.**
`%LOCALAPPDATA%\Docker` is a **junction pointing at it**, so that folder is Docker
Desktop's app-data and log directory and the backend writes to it continuously. Only the
*disk image* moved. Before deleting anything that looks like a leftover:
`Get-Item <path> -Force | Select LinkType,Target`. Relatedly, error messages still print
the literal `...\appdata\local\docker\...` path even when the data is on `N:`, which sends
you to the wrong drive if you take it at face value.

### What it actually bought

Old numbers taken on SMR are not comparable to new ones — different medium, different
failure mode — so the honest move was to throw the old baseline away and take a fresh one
after the migration. With the runner service stopped, host steal ticks at zero, `fio` at
queue depth 32 via `libaio`:

| Job        | Throughput | IOPS    | p50    | p99     |
| ---------- | ---------: | ------: | -----: | ------: |
| seq-write  | 2244 MB/s  | 2243    | 13.7 ms| 21.9 ms |
| seq-read   | 2655 MB/s  | 2654    | 11.9 ms| 21.1 ms |
| rand-write | 1020 MB/s  | 261,066 | 432 µs | 1106 µs |
| rand-read  | 1078 MB/s  | 275,955 | 399 µs | 1221 µs |
| sync-write | 1.4 MB/s   | 356     | *see below* | *see below* |

And with the VHDX off shingled media, `Optimize-VHD` stopped being off-limits — that
restriction only ever existed because compaction on SMR is punishing. A `fstrim` inside
the guest followed by `Optimize-VHD -Mode Full` took the file from **103.63 GB to
69.85 GB in 24 seconds**. Less than the ~65 GB I'd predicted, because VHDX blocks are
32 MB and a partially-used block can't be released.

### Three ways I nearly fooled myself with these numbers

**1. The `dd` harness is too noisy to measure anything.** Run-to-run variance is **±25%**,
which is larger than most effects worth measuring. I added `fio` to the VM specifically
because of this, breaking my own "no installs, no leftovers" rule for the box — knowingly,
because an A/B you can't resolve is worse than no A/B.

**2. Two `fio` flags produce confidently wrong numbers.** The default ioengine is `psync`,
which is synchronous and **caps `iodepth` at 1** — passing `--iodepth=32` without
`--ioengine=libaio` is a no-op that fio only mentions in a passing note. And fio prints
those advisory notes to *stdout ahead of the JSON*, so `--output-format=json | parser`
fails; write to a file with `--output=` and parse that. Also, `sync-write` clat
percentiles **exclude the fsync itself**, so p50 reads ~100 µs while the real commit rate
is 356/s — about **2.8 ms per commit**. Trust the IOPS figure there, not the percentiles.

**3. The "regression" that was physics.** Sequential writes dropped from 2.6 GB/s to
2.0–2.1 GB/s and stayed there for four runs. I chased four hypotheses; three were wrong
(queue affinity tuning: ±5–9% noise; dynamic-VHDX first-allocation: 2.0 fresh vs 2.1
overwrite; thermal: 40 °C under load, 36–37 °C rested, max-ever 81, wear 0). The actual
cause was **SLC cache exhaustion**. The PM981a is TLC with a *dynamic* SLC cache: ~3 GB/s
while it holds, ~1.7–2.0 GB/s writing straight to TLC, and I'd pushed ~150 GB through it.
Tracking recovery against idle time, with **no configuration change between
measurements**:

| Drive state         | Seq write | Seq read |
| ------------------- | --------: | -------: |
| Freshly hammered    | 2.0 GB/s  | 2.1 GB/s |
| After 9 min idle    | 2.2 GB/s  | 2.4 GB/s |
| After 14.5 min idle | 2.5 GB/s  | 2.7 GB/s |

**Lesson:** always record *which drive state* a number came from. Rested and sustained
figures differ by ~25% on the same hardware and both are correct. A benchmark number
without that context isn't a measurement, it's an anecdote.

### The tuning that changed nothing, and stayed anyway

Inside the guest, `/etc/udev/rules.d/60-nvme-tuning.rules` sets `rotational=0`,
`add_random=0` and scheduler `none`, verified to survive a reboot. It produced **no
measurable throughput gain** — the kernel was already doing the sensible thing. I kept it
because the alternative is the kernel describing an NVMe as a spinning disk, which is
simply false, and false descriptions eventually cost you somewhere else. Two host-side
changes did matter: automatic checkpoints **off** (otherwise every CI write lands on an
AVHDX differencing chain), and a 90 s `AutomaticStartDelay` so the VM doesn't try to start
before BitLocker has unlocked `N:` at boot.

---

## Three runners on one CI VM

**Date:** 2026-09-11 → 2026-09-12

The CI VM (8 vCPU / 16 GB / 120 GB, benchmark-locked at that size) ran a single
self-hosted Actions runner, and seven workflows queued behind it. Adding two more runner
services — same box, same user, `/home/runner/actions-runner{,-2,-3}` — is the obvious
fix, and it exposed three things in a row that the single-runner setup had been hiding.

### Registering runners proves nothing

After adding them, several workflows went green at once and I nearly called it done. They
hadn't run concurrently at all: every job still reported `runner_name` of the *original*
runner, with staggered start times, and runners 2 and 3 had empty `_work` directories.

**Check `runner_name` per job** (`gh api .../runs/<id>/jobs`), not whether the run was
green. The real validation was dispatching a full three-leg browser matrix and watching
three different runner names start at the same second.

### A shared tool cache is not the default

Each runner defaults its tool cache to `<runner-dir>/_work/_tool`, so runners 2 and 3
started stone cold and would have downloaded their own copy of the Flutter SDK. `~/.npm`
is shared for free because all three services run as the same user; the tool cache needs
to be told:

```
AGENT_TOOLSDIRECTORY=/home/runner/_tool_shared    # in each runner's .env
```

That's the supported override — the runner derives `RUNNER_TOOL_CACHE` from it. Seed it
from the warm runner, and make the "add a runner" script append the line itself, or every
future runner is silently cold.

⚠️ Re-registering a runner **rewrites `.env`**. I renamed runner 1 (there is no rename
API, so it's deregister + re-register, and it comes back with a new numeric id) and both
the custom label and the `AGENT_TOOLSDIRECTORY` line were gone afterwards. Losing that one
line is invisible until you notice builds got slower.

### The regression concurrency created

The very test that proved concurrency worked also broke two of the three legs, both in the
same step: booting an ephemeral local Supabase stack. One cause, two mechanisms:

- `supabase start` binds the **fixed ports in `config.toml`**, so the second job collides.
- The preceding "pre-clean any leftover stack" step runs
  `docker ps -aq --filter name=supabase_ | xargs -r docker rm -f`, so a second job's
  *cleanup* tears down the first job's live stack.

Neither is a bug. Both are correct code that silently assumed **one job at a time on the
box**, which was true for as long as there was one runner. That assumption was never
written down anywhere, which is exactly why it survived.

⚠️ **Do not "fix" this with job-level `concurrency`.** A concurrency group keeps one
pending job and *cancels* the rest, so matrix legs get silently cancelled rather than
queued. The two things that do work are label routing (add a custom label to one runner
and target it — an emergency lever that needs no VM access, at the cost of serialising:
44 min wall clock instead of 12) and real per-runner isolation.

I ended up on isolation: each runner gets its own project id (`…-r<N>`, via
`SUPABASE_PROJECT_ID`, which outranks `config.toml`) and its own host port offset, with
teardown scoped by the `com.supabase.cli.project` label instead of a name prefix.
**43m55s → 24m33s**, all three legs starting on the same second, all green.

🔴 **The lesson that cost me a validation run: Supabase wasn't the only thing binding a
host port.** The first isolated dispatch still failed —
`http://localhost:5173 is already used` — because the E2E job also runs `wrangler pages
dev`. The right question was never "which ports does Supabase use" but **"which host ports
does this *job* bind"**, and the answer spanned three tools: Supabase's eight, the dev
server's 5173, and the DevTools inspector on 9229, which hadn't failed yet only because
the app port failed first.

### Sizing: read PSI, not CPU%

Measured during three concurrent E2E legs:

| Overlap    | PSI cpu stall |
| ---------- | ------------: |
| one job    | 1.8%          |
| two jobs   | 16.5%         |
| three jobs | **41.9%**     |

RAM peaked at 11.3 GiB of 15.6 (73%) with PSI memory at 0.8%, 165 MB of swap and zero OOM
kills; disk peaked at 41% utilisation with 3.79 ms await. So CPU is the only constrained
resource here — **more vCPU would help, more RAM would not** — and the host itself idles
at ~6% of its 16 logical CPUs, so there's room. The point is that CPU% alone could not
have told me this: it cannot distinguish "fully used" from "oversubscribed". PSI can.

### Caches, eviction, and a directory permission that lied to me

Three runners share caches that nothing was evicting: the provisioning script that
installs the nightly cleanup job had never run on this VM (it predates that change and was
never re-provisioned), and the cron file still held a month-old line that pruned Docker and
nothing else. npm, tool and Playwright caches had **no retention at all**.

Two things worth carrying forward from fixing it:

- The cleanup script's `NPM_MAX_GB=2` sat *below* the resting size of `~/.npm` (2.6 GB).
  Had it been installed as written, it would have cleared the entire cache nightly and
  re-downloaded it every morning — a "cache" that is never warm, quietly, forever.
- ⚠️ `/home/runner` is `0750 runner:runner`, so `[ -d /home/runner/... ]` run as the
  *admin* user is false for lack of **traverse** permission, not absence. My first
  maintenance pass cheerfully reported "already gone" about 2.7 GB that was still sitting
  on disk. A permissions artifact reads exactly like a clean result.

The retention policy I settled on: while **any** runner is mid-job, every cache-evicting
step defers to the next idle pass. "`docker rmi` refuses in-use images, so it's safe" is
not a sufficient bar — a job that hasn't yet pulled the image it needs has no container
referencing it, so the removal succeeds and the job re-pulls mid-run. Safe by the letter,
and an attack on the warm cache in practice.

### Two constraints that stay, and why

**GitHub's hosted cache service stays disabled** (`cache: 'npm'`, `flutter-action`'s
`cache: true`, `actions/cache` — all removed deliberately, with a comment in every
workflow saying so). From this VM it stalled the entire runner queue with
`Failed to restore: operation aborted`. Registry egress is fine; only the cache service
was not. The endpoints answer a plain `curl` again now, but that proves TCP reachability
and nothing else — re-enabling needs a real job to validate.

**Unattended `sudo` is gone**, which changes day-to-day operations more than it sounds
like. Privileged work on the VM now needs `ssh -t … sudo …` with someone typing a
password, so it has to be *planned* rather than discovered mid-task. `sudo -u runner`
doesn't work either; become root, then `su - runner`.

Worth being honest about the boundary that actually matters here: the runner user is in
the `docker` group, and a container can mount the host filesystem, so **it is
root-equivalent inside the VM regardless of sudo**. The workflows genuinely need Docker,
so this is accepted rather than fixed, and the VM is treated as the blast radius —
egress from it is dropped to the LAN, the NAS and the tailnet, there are no host
filesystem mounts into the guest, and nothing on the host trusts it.
