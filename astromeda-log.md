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

---

## The sluggish game that had nothing to do with the hardware

**Date:** 2026-09-23 → 2026-09-24

This machine now does five things at once: a workstation, a gaming rig, two Minecraft
Bedrock servers, a Plex server, and a Hyper-V CI VM running three self-hosted runners.
Minecraft felt sluggish while CI was busy, so I went looking for contention. I found
none, because there wasn't any — and the three days it took to establish that were worth
more than the answer.

### Everything had slack, and the game was still bad

Host CPU peaked at 83%. The Windows processor queue averaged 0.9 on sixteen logical
processors. The Bedrock server's tick threads were starved for 0.018% of wall clock. The
GPU sat at 514 MHz of a ~1777 MHz boost, drawing 16 W. Nothing was saturated, nothing was
waiting, and it still stuttered.

The cause was that I was playing over **RDP**. The client was rendering into the Microsoft
Remote Display Adapter at **32 Hz**, not the GPU's 3440×1440 output. No amount of CPU
would have fixed a display pipeline that only presents 32 frames a second.

🔴 **Check which display adapter the thing is actually rendering into before you profile
anything.** `qwinsta` would have told me on day one which session I was in. I spent that
day measuring CPU, GPU, scheduler pressure and memory instead — all of which were fine,
and all of which I now have baselines for, so it wasn't wasted. But it was the wrong
question, asked thoroughly.

### The measurement that was wrong by 1100×

To decide whether CI was starving the game servers I used `run_delay` from
`/proc/<pid>/schedstat` — nanoseconds a task spent runnable but not scheduled. It read
essentially zero, so I reported the servers were untouched.

`/proc/<pid>/schedstat` reports **the main thread only**. The Bedrock server runs 19
threads and its main thread does almost nothing: 8 ms of CPU against 8909 ms for the
process over the same window. I had been measuring an idle thread and calling it a server.

⚠️ Sum `/proc/<pid>/task/*/schedstat` instead. The corrected numbers were still small —
0.009% to 0.025% of wall across every scenario — but they were *measurements* rather than
an artifact. Being right for the wrong reason is still being wrong, and it would have
fallen apart the moment someone loaded the box differently.

### Queue length, not CPU%

The one signal that tracked reality was the Windows processor queue — threads ready to run
with no processor free. Under the heaviest combined load (a CPU-bound game, a Plex
hardware transcode, remote desktop streaming, two Minecraft players and three CI runners)
the queue's worst spikes landed at **68–72% host CPU, not at the 85.5% peak**. Utilisation
and contention are decoupled, and averages hide the spikes entirely: 38 of 51 samples sat
at ≤2, then single samples at 8, 9, 10 and 12.

That distribution is exactly what a vsync cliff feeds on. The game was capped at 60 and
dropping to the low 30s — not gradual degradation, but frames missing a 16.7 ms window by
a hair and waiting for the next refresh. A small stall, a large visible drop.

### More cores did not make CI faster

While I was in there I tested giving the CI VM 12 vCPUs instead of 8, on an eight-core
host. Guest CPU pressure halved and the VM genuinely consumed the extra capacity. Wall
clock did not improve: the critical-path browser leg came in at 15.1 and 16.2 minutes
against a baseline of 15.9 and 16.0.

The reason was in the test config all along — the browser runner is set to one worker,
deliberately, because the suite shares one dev server and one database. A serial critical
path does not get shorter when you add cores to the machine around it. Reverted to 8.

⚠️ I also nearly quoted the wrong variance. I warned that this harness swings ±25% and
that four samples couldn't resolve anything — but that figure came from the *disk*
benchmarking earlier in this log, not from the test suite, which repeats to within 3–4%
per leg. Reusing a number across two harnesses because both live on the same box is a
quiet way to talk yourself out of a valid result.

### 32 GB of memory that was not actually in use

Separately: Windows was sitting at 88% physical with commit at 64 of 67.9 GB, and ~29.6 GB
had been pushed to the pagefile. The consumer was WSL2, holding 32 GB.

It wasn't using it. Inside, Linux reported 4.3 GiB used and 27 GiB of clean page cache
(`Dirty: 56 kB`) — file cache from container image pulls and media reads, which Linux will
release instantly under pressure and correctly reports as available. Windows just can't
see that, so it sees 32 GB occupied and starts trimming working sets to compensate.

`autoMemoryReclaim=gradual` in `.wslconfig` returned about 30 GB of commit. Two honest
caveats: the documented default is already `dropCache`, so the absence of the setting is
not "reclaim disabled" — the 27 GiB I measured is the evidence, not the config. And a
reading taken minutes after a restart proves nothing about reclaim; it proves a clean
start. The test is whether the cache comes back down *after* it has been rebuilt.

### What it holds up to

With all five workloads running simultaneously the box peaked at 85.5% and never ran out
of processors. The servers stayed responsive throughout. The only real cost was occasional
frame-pacing hitches in a 2011 engine bound on a single thread — and having measured what
it would take to fix that (throttling CI when the desktop is busy, with detection,
hysteresis and a failure mode for each), I decided it wasn't worth building. Cancelling CI
takes ninety seconds on the rare occasions it matters.

The useful conclusion isn't that the hardware is impressive. It's that I spent three days
instrumenting a machine to discover the bottleneck was a remote desktop protocol, and the
instrumentation only became valuable *because* it ruled everything else out convincingly.

---

## A backup that only existed on the machine it was backing up

**Date:** 2026-09-24

Follow-on from the entry above. Having established that the box copes fine under
combined load, I spent a day on the things that were quietly wrong rather than slow —
and the worst of them was one I had built myself, three days earlier, and believed was
finished.

### The gap

I had written a nightly config backup for the CI VM: capture the firewall ruleset, the
SSH hardening, the cron entries, the runner configuration, a package manifest — the
things a rebuild cannot derive. Installed it, verified it, watched it fire unattended at
03:45 and produce a 31 KB archive. Ticked it off.

The archive was on the VM. Only on the VM. I had also written the host-side script that
pulls it onto two separate disks, deployed that script, and **never registered the
scheduled task that runs it**. So for two nights the machine had been diligently backing
itself up onto itself.

🔴 **"The script exists" and "the job is scheduled" are different claims, and finishing
the first one feels exactly like finishing the second.** This is the same failure this
log already records for the nightly cleanup script — written, merged, never installed —
and I reproduced it in a fortnight, in the component whose entire purpose is surviving
the loss of the machine it runs on. The check that catches it is trivial and I did not
run it: list the scheduled tasks and look for yours.

### Compaction does nothing without a trim

The VM's virtual disk had grown to 103.8 GB of a 120 GB dynamic maximum while the guest
was using 32 GB. So: shut the VM down, take a rollback copy, compact, restart. It
reclaimed **nothing** — identical size, fifteen seconds.

Compaction can only reclaim blocks it can prove are free. On a Linux guest that means
blocks the filesystem has explicitly *discarded*; blocks merely freed by deleting a file
still contain stale data and look occupied from outside. The periodic trim timer had last
run three days earlier, so everything the CI had churned since was opaque to the host.

I had checked that trim was *supported*, and I had read the timer's last-run date, and I
proceeded anyway. Both facts were on screen. The obvious conclusion from "last trimmed
three days ago" and "the file is 70 GB larger than its contents" is the one I didn't
draw. Cost: a three-and-a-half minute outage for a no-op.

With a trim first — which discarded **64.8 GiB** — the same compaction took 17 seconds
and recovered **25.3 GB**. Note the gap between those two numbers: discarding a block
inside the guest and reclaiming it in the disk file are not the same event, and not every
discard propagates as something the host can act on. The disk is now 77.9 GB with the
guest still using 32 GB, so roughly 46 GB of slack remains and a second pass would
probably find some of it. Not worth another outage.

### The elevation inversion

A thing I had assumed backwards all week. Remote desktop sessions run with a UAC-filtered
token, so every administrative command I tried through one was refused. I had been
working around it for days by handing commands over for someone to run in an elevated
window.

SSH is the opposite. The SSH daemon runs as the system account and constructs the user's
token directly rather than going through a filtered network logon, so a member of the
administrators group gets a *full* token. The moment I switched from remote desktop to
SSH, every command that had been failing worked — hypervisor management, virtual disk
inspection, scheduled task registration, all of it.

⚠️ So on this machine **SSH is strictly more privileged than the graphical remote path**,
which is the reverse of what the graphical session's richer interface suggests. Worth
knowing before assuming a shell is the lesser tool.

### Two traps in adding SSH to Windows

Both cost nothing if you know them and are invisible if you don't.

**The installer opens the port to everyone.** Adding the SSH server capability creates a
firewall rule allowing port 22 from any address. My network policy is deny-by-default and
grants SSH to exactly one machine — but that policy governs the overlay network and says
nothing about the local subnet. Leave the rule and nothing fails: the intended path works
perfectly while a second, ungoverned door sits beside it on the LAN. That is the failure
mode a policy file cannot detect, and the only place to catch it is on the host.

**Administrator accounts do not read the usual authorized-keys file.** They read a
separate machine-wide one, and ignore the per-user file entirely. That file's permissions
must also be restricted or the daemon silently refuses to use it — it fails closed, which
is the right direction, but it presents as "key rejected" with nothing in any log saying
why.

Verify the result from the client, not the server: ask the server which authentication
methods it offers and read the reply. A configuration file saying password auth is
disabled is a claim; the server's own answer is evidence. (And disabling password auth
alone is not enough — keyboard-interactive is a separate setting and stays open unless
you turn it off too.)

### The memory that was never in use

Earlier I found the Linux subsystem holding 32 GB while genuinely using 4.3 GiB; the rest
was clean page cache the host could not see as reclaimable. I enabled gradual reclaim and
reported a 30 GB improvement, with the caveat that a reading taken minutes after a restart
proves a clean start and nothing about reclaim.

So I let it run for five hours across a two-hour film and three hours of idle afterwards,
sampling every two minutes. It climbed **+8.08 GB** during playback and returned
**9.65 GB** afterwards — 119% of the climb, finishing 1.57 GB *below* where it started.
Page cache drained from 8.91 GB to 0.21 GB and the host got all of it back.

That is the measurement the earlier entry was missing. The fix works, and the more
aggressive option I had lined up as a fallback is not needed. Worth noting the shape of
the test rather than the result: the load phase alone would have shown the climb and told
me nothing, because **the question was never whether cache grows — it was whether it
comes back.** A sampler that stopped when the credits rolled would have captured exactly
the uninformative half.

### Assorted smaller things

⚠️ **An unattended upgrade needs to be told it is unattended.** `apt-get -y upgrade`
answers yes to *installing* but nothing to configuration questions, so it dropped a
headless VM into an interactive keyboard-layout menu, then a console character-set menu,
over a nested SSH session with a broken clipboard. The environment variable that
suppresses those prompts is not optional on a server; neither is the option that keeps
existing config files when a package ships a new one.

⚠️ **The default shell for SSH on Windows is the old command interpreter**, not
PowerShell. Handing someone a `.ps1` to run by typing its path does nothing at all — the
shell tries to *open* the file rather than execute it, and fails silently. A `.cmd` works,
or change the default shell, which is a registry value. Note the accompanying
command-option value differs between the two shells; I set it to the command interpreter's
form first and had to correct it.

### What I would tell myself on Monday

Three of the four real problems this week were *absences*: a scheduled task that was never
registered, a trim that was never run, an elevated shell I already had and didn't know
about. None of them announced itself, and none would have been caught by watching the
system more closely — only by checking whether the thing I believed existed actually did.

---

## The lag was an army, and the firmware was five years behind

**Date:** 2026-09-25

My son and I play Minecraft Bedrock on a server this box hosts. He plays from a tablet
over Wi-Fi to the same mesh satellite the PC is wired to; I play on the PC itself. Lately
it lagged when we were together at our base, and for him it became unplayable. The
previous entry had already cleared the network and the host, and a follow-up tuning pass
had trimmed view distance, switched compression to snappy, unlocked worker threads and
moved terrain generation from the tablet to the server. The question I started with was
whether that last change would push the single tick thread over the edge, and whether
we should undo it.

Wrong question again, though a cheaper one this time.

### Count what is in the world before touching the config

Bedrock simulates the whole world on one thread. Every tuning knob I had already turned
addresses what the server *sends*; none of them touches what it *ticks*. What it ticks is
entities, and nobody had counted them.

With zero players online and no ticking areas, the server still held **1,265 loaded
non-player entities**, all inside one 250 × 280-block patch around the base: 586 drowned,
305 tridents stuck in the ground, 81 villagers, 73 snow golems, 35 wolves, 32 skeletons.
Natural spawning is off in that world, so every one of them had been spawned by hand — a
war, weeks ago, that never ended. Snow golems attack hostile mobs, so 73 golems next to
586 drowned was a battle running every tick, for days, whether anyone was logged in or
not. Drowned have the most expensive AI in the game: three-dimensional water pathfinding
plus ranged combat.

That explained the pattern exactly. Two players in different places tick two small areas
of terrain. Two players together at the base tick one area containing a thousand entities
fighting each other. The tick thread had been measured at full saturation with two
players; it idled at 8% with *nobody* on, which should have been the tell.

⚠️ **Bedrock has no `/tps`, no entity count and no profiler.** The census came from the
server console: create a scoreboard objective, `scoreboard players set @e[type=drowned]
… 1`, and read "Set for N entities" from the log. `family=` selectors group by class, and
`execute as @e[type=…,c=3] at @s run tp @s ~ ~ ~` prints coordinates for the nearest
three. Clunky, but it turned a guess into a table in ten minutes.

I culled the drowned and the tridents (after a held-save backup), leaving the villagers,
golems and animals. 1,265 became 374. The tick thread now idles at 1%.

**A correction to the previous entry:** I wrote that "the servers stayed responsive
throughout" the load matrix. They did — with two players standing away from the base.
The variable I never varied was what was loaded around the players, and it was the only
one that mattered. A machine can be instrumented to the bone and still miss the thing
that is not a resource.

The part that changes the workflow: spawning enormous crowds and letting them fight is,
my son tells me, the *point*. So "spawn fewer mobs" is not a fix. The fix is that a war
has to end when you are done with it — one `/kill @e[family=monster]` in chat — and
that the leftovers (projectiles, drops, orbs) get swept. He is now an operator on both
servers so he can do that himself. The single-thread ceiling is real and no server on
any platform ticks one battle across cores; a 5800X core handles a few hundred cheap
mobs in one place comfortably. It cannot handle a permanent drowned navy.

A few things I looked at and correctly left alone: the world sits on a 9p bind mount of a
Windows path, which is ~10× slower than ext4 on small-file metadata but only touches the
LevelDB thread, never the ticker. And the CPU already boosts to 4.66 GHz on a single
thread, *including inside the WSL2 VM* — measured, not assumed — so the power plan and
every "dedicated box" argument I was tempted by would have bought nothing. Only
single-core speed moves this ceiling.

> **Retracted the same evening:** "never the ticker" was wrong. The tick thread does
> synchronous I/O over that mount, and it was sitting there when the world froze. See
> [the next entry](#the-migration-that-left-three-pointers-behind).

### A BIOS from the month the CPU launched

While checking the clocks I noticed the firmware: **P1.20, October 2020**, the Zen 3
launch BIOS. Two things follow from that. It predates the fTPM stutter fix (AGESA
1.2.0.7, 2022), and this box uses the firmware TPM for BitLocker on C:, so the bug that
freezes the whole system for a second while the TPM writes to SPI flash applied here.
And it predates the 2023 Secure Boot certificates, which Windows now needs.

The flash cost an afternoon, and the reasons are worth recording because none of them
were in the manual.

🔴 **Instant Flash could not leave P1.20.** It listed the 5.80 image as suitable, then
rejected it with "Invalid File!". I downloaded every release for the board and compared
them: identical board ID throughout, but from 1.50 onward the AMD PSP firmware
directories sit at different offsets in the image. The flasher baked into P1.20 validates
against the layout it knows and refuses everything newer. There is no stepping-stone
version — the very first release after mine already has the new layout. The only path
is **BIOS Flashback**, the button on the rear I/O that writes the flash with its own
controller and never involves the running firmware. The manual describes Flashback as a
recovery feature. From this firmware it was the *only* upgrade path.

🔴 **The USB stick bricked the board.** Not the image — I had verified the download was
byte-identical to the vendor's file. The first two sticks were the same "Generic Flash
Disk" model. One refused writes at the controller level (diskpart's `clean` failed with
access denied; the event log said "cannot zero sectors"). The second passed a full SHA-256
read-back under Windows and *still* delivered a corrupt image to the Flashback
controller, which reads the stick with a minimal USB stack, not the OS's. The board would
not POST. A stick of a different make, full (not quick) FAT32 format, fresh download, and
Flashback again — and it came up. Flashback recovered its own failure, which is what it is
for, but I should have insisted on a known-good brand instead of a sacrificial one. A hash
check under the OS does not prove a stick is safe for firmware.

Smaller traps, in the order they cost me time:

- `shutdown /r /fw` — the "reboot straight into UEFI setup" flag — fails with error 203
  on this firmware. Plain restart and hammer Del.
- A stick with no bootloader, selected as a boot device, produces an error screen and a
  drop back to setup. Instant Flash is a utility *inside* setup (Tool menu), not something
  you boot.
- BitLocker's "suspend for N reboots" counts every Windows boot, including the ones you
  make while failing. Two suspensions were used up by detours and the post-flash boot
  asked for the recovery key after all. Have it to hand before you start, not in a
  password manager you need the same machine to open.
- Windows' PowerShell disk cmdlets could not create a volume on a healthy stick that
  diskpart plus the old `format` command handled fine. Use the old tools for removable
  media.

The box now runs P5.80 with the DDR4 profile, fTPM, Secure Boot, SVM and Resizable BAR
re-enabled, the chipset package updated from a 2025 build to the current one (the PSP
driver that talks to the fTPM went from 5.25 to 5.40), and the NVIDIA and Windows
updates that were waiting behind it. The Minecraft servers had to be started by hand
afterwards — containers stopped deliberately do not auto-start, by design of
`unless-stopped` — and the CI VM came back on its own.

### What I would tell myself on Monday

Last week's problems were absences. This week's were *presences* nobody had counted: a
thousand entities in a world, five years of firmware releases between the installed
version and the current one. Both were visible in ten minutes once I asked "what is
actually there?" instead of "what is the machine doing?". And the thing that nearly cost
the motherboard was the one component I had decided did not matter enough to choose
carefully.

---

## The migration that left three pointers behind

**Date:** 2026-09-25 (evening) — with one loose end from 2026-09-22

The afternoon's entity cull fixed the constant lag. It did not fix the freezes. My son
still reported the world stopping dead for a second or two, and so did I, on a wired PC.
This time I did not tune anything until I could see a freeze happen.

### Measuring a freeze on a server that has no `/tps`

Bedrock has no tick-rate readout, but it has `time query gametime`. It also does **not**
run catch-up ticks: a tick it misses is gone. So I sent that command once a second from
the console and diffed the gametime lines in the log. Twenty ticks between samples means
healthy. Fewer means the world stood still for the wall-clock difference.

The first 17 minutes, with one player at the base, gave two freezes: about 3 s, then about
1 s. After that, nothing for 9.5 minutes. The tick thread never went above 30% CPU, the
host sat around 20%, and PSI was zero. That is a stall, not saturation. The one time I
caught the thread during a freeze, it was in state `D`, blocked in `p9_client_rpc`.

A 40-minute run with both of us online made the case. I sampled the tick thread's kernel
wait channel ten times a second. In the five seconds before *each* of the two hard freezes
(≈2 s and ≈2.5 s), it spent 40–80% of its samples in `p9_client_rpc`. Meanwhile the LevelDB
thread was running at 75–86% and both players were standing still. That is a LevelDB flush,
with the tick thread doing synchronous file I/O over the 9p mount that joins the container
to a Windows directory. The afternoon entry said this mount "never touches the ticker".
It does.

The same run showed a second, different slowdown: 13–16 ticks per second for up to 20 s,
with the tick thread at 95–104% CPU. It happened when a player flew fast (20–28 blocks/s,
so fresh chunks loading) or went into a second dense cluster of 100–120 entities. That one
really is CPU, and it is the single-thread ceiling from the afternoon entry. It did not
correlate with host CPU (41% mean), disk latency (p95 6 ms) or ping.

⚠️ Two traps in the instrumentation:
- There are **two threads named `MC_SERVER`**, and only one of them ticks. Anything that
  picks "the" tick thread by name has to take the one with large `utime`.
- A collector built on `docker logs --tail` looks dead if you analyse it while it is still
  running. Check for its own "done" line before you decide it crashed.

### Why the tablet felt worse than the PC

The freezes hit both players equally, because they are server-side. So they did not
explain why he felt it more than I did. Two things did, both on his side:

- **Rendering.** By early evening there had been a new battle, and the world was back at
  ~1,280 entities. Within 48 blocks of his player there were 96 non-player entities on
  average, with a peak of 385. The tablet has to draw all of them. The PC barely notices.
- **Wi-Fi.** 35 minutes of pings showed zero loss, but 37 spikes over 20 ms and 10 over
  50 ms (max 167 ms). The wired PC had none. Through Docker Desktop's UDP proxy, RakNet
  round trips stayed under 1 ms, so the host was not adding any of this.

The fixes for that are on the client: render distance 6–8 on the tablet, fancy graphics
off, and the after-battle sweep. None of them is a server setting.

### The move off 9p

I had staged the move in the early evening. I created a Docker named volume, warm-filled it
while the server was running (3.7 GB in 81 s), and wrote a cutover script that refuses to
run while anyone is online. The cutover itself ran later that night from a Claude Code
session on the Windows side, and it widened the scope sensibly: Big Earth sits on the same
kind of mount, so **both** servers moved. After stopping both, a delta sync copied 383 MB
for Rhen's World and 446 MB for a new Big Earth volume, and the file lists matched. `/data`
is now ext4 inside Docker's VM. The old `N:` directories are frozen rollback copies.
Nothing reads them any more, and nothing should write to them.

⚠️ **A named volume lives inside Docker Desktop's disk image**, so it goes with that image
if Docker Desktop is ever reset. After the move, a world that exists nowhere else has to be
backed up through the container. That is also how I found the next problem.

**Not yet proven:** I have not repeated the freeze measurement since the cutover. The
mechanism fits, and the ext4 volume removes it. The next play session with the sampler
running will settle it, and I will record the result here whichever way it goes.

### Three pointers still aimed at the drive I emptied

The NVMe entry from 11 September moved Docker, WSL and the worlds off `D:`. It made no
mention of what still *pointed* at `D:`. Three things did, and none of them reported an
error:

🔴 **The nightly world backup had failed every night from 11 to 25 September.** The
scheduled task still ran the scripts under `D:\Docker`, which no longer existed. It
failed silently, with nothing in the logs I actually read. That was two weeks with no
backup of a world my son plays in every day. It would have kept failing after the volume
move anyway, because the scripts read world files straight from disk. The rewrite:
- The world is pulled out with `docker cp` from the running container, between
  `save hold` and `save resume`.
- The task was re-registered with an **S4U** principal. It runs without me logged in and
  stores no password.
- There is change detection. The script hashes a tar stream of the world plus its config
  files, with mtimes and ownership zeroed, and skips the zip when the hash matches the
  last backup. `level.dat` is rewritten on every save hold/resume, even on an idle world,
  but I checked that the content hash stays the same across that cycle. Without zeroing
  the metadata, every night would count as a change.

Deduplication then showed how much the old scheme had been duplicating. Most nights
nobody played, and each of those produced a full copy in OneDrive. Comparing every zip by
entry names, sizes and CRC32, and keeping the first zip of each unchanged run, took the
folder from **319 zips to 224**. That removed 95 files, **about 78 GB**. The full list of
deletions is logged beside the backups. Fifteen files could not be checked: fourteen were
OneDrive placeholders with no local copy, and one zip from May has no end-of-archive
record, which means a truncated upload that may never have been restorable.

🔴 **Defender's exclusions still named the `D:` paths.** For two weeks, none of the new
locations for Docker, WSL, Hyper-V or the Steam library were excluded from real-time
scanning. I never measured what that cost, so I can't say it was slowing anything. The agent
proposed the new exclusions (`N:\Docker`, `N:\WSL`, `N:\HyperV`, `N:\SteamLibrary`) and was
refused permission to apply them itself. That was the right call: weakening the
antivirus is something I should type myself, and I did.

🔴 **The WSL distro's disk was owned by the wrong account.** On 22 September, Ubuntu
stopped starting with `Wsl/Service/CreateInstance/MountDisk/HCS/E_ACCESSDENIED`. It looks
like a locked or corrupt disk, and it is neither. Every time a distro starts, the host
compute service rewrites the VHDX's ACL to add the new utility VM's SID. That needs
`WRITE_DAC`, which the file's owner has implicitly. The files re-registered on `N:` during
the move were owned by `BUILTIN\Administrators`, not me, and the inherited "Authenticated
Users: Modify" grant does not include `WRITE_DAC`. The fix was
`icacls N:\WSL /setowner ASTROMEDA\MB /T /C` from an elevated shell. Granting the Virtual
Machines group full control does nothing, because the failure is in writing the ACL, not
in the access check. This is **the same bug** that took down Docker Desktop's disk after
an update in August. At the time I wrote it off as a one-off. It is a pattern: any VHDX
created from an elevated context on this machine will do it.

**Lesson:** a migration checklist needs a step for what points at the old location, not
just for what lives there. Scheduled tasks, AV exclusions, file ownership, junctions. None
of these fail loudly, and all of them fail *later*.

### Host tuning, and where it contradicts my own measurement

The same Windows-side pass tuned the host for everything running on it at once: Plex,
Docker, the two servers, occasional Steam and the CI VM.

| Change | Why |
|---|---|
| WSL memory capped at 24 GB | `memory=0` is not "unlimited". WSL ignores it and falls back to 50% of RAM (32 GB). With CI holding 16 GB and Windows ~10 GB, that left ~6 GB headroom at peak. |
| Power plan → High performance | see below |
| Xbox Game DVR background capture off | records the GPU continuously for nothing |
| Green Ethernet off on the NIC | power saving on a desktop's wired link |
| NVIDIA Broadcast, Logitech updater, Edge removed from startup | Broadcast holds GPU resources whenever it runs |
| `docker image prune -a` | 3.06 GB of unused images |
| "WAN Miniport (IP)" Code 56 removed and rescanned | a RAS pseudo-device, typically broken by VPN client installs; Windows recreated it clean |

⚠️ **High performance contradicts this afternoon's entry.** Then I measured 4.66 GHz on
one thread under Balanced, *inside WSL2 as well*, and wrote that a power-plan change
would buy nothing. That is still true for single-thread boost. What High performance
changes is how quickly idle cores wake up and park, and I have no measurement either way.
I have left it on, but I am counting it as untested, not as an optimisation.

Considered and deliberately left alone:
- **Memory integrity (HVCI)** stays on. It costs a few percent in games and some VM-exit
  overhead, and it is a real security boundary. That trade is not worth a few frames.
- **The 2.5 GbE NIC negotiates at 1 Gbps.** That is the switch or the cable, not the host.
- **NetherNet.** Every server start now prints a "TRANSPORT TYPE ERROR" block saying
  Mojang's WebRTC-based transport is the only one supported. It isn't, yet: no
  `transport` line means RakNet on UDP 19132, and the tablet connects fine. But this
  whole setup assumes RakNet: the port mapping, the LAN discovery relay, the tablet. A
  switch needs TCP 19132 published plus a UDP range. That has to be planned and tested with
  the tablet before an automatic image update pulls a build that enforces it.

### A smaller trap: the blank launcher

After the BIOS flash, eight reboots, a new NVIDIA driver and a Windows preview update, the
Minecraft launcher took 3 min 15 s to start (normally 4–7 s) and showed a blank page. Its
Chromium log shows a `--type=gpu-process … --use-gl=disabled` relaunch, which looks like
the obvious suspect. It is not: that line is in nine of my last ten launcher logs,
including all the healthy ones. So were 176 GPU `LiveKernelEvent` reports, which all fall
inside the reboot storm, with none after the last boot. If the page is blank, relaunch
once. If it happens again, delete `.minecraft\webcache2`. Bedrock itself does not need the
launcher:
`explorer.exe shell:AppsFolder\Microsoft.MinecraftUWP_8wekyb3d8bbwe!App`.

### What the day actually taught

I wrote two confident sentences this afternoon: the 9p mount never touches the ticker,
and the power plan is irrelevant. By night the first had been disproved by measurement,
and the second had been set aside without a measurement either way. The first is the kind
of correction I want in this log. The second is the kind I want to avoid, so it is marked
here until I have a number for it.
