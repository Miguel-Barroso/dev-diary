# Astromeda — Minecraft Bedrock Server Notes

Astromeda is my Windows gaming PC. These notes cover migrating the Minecraft Bedrock world off the QNAP NAS into Docker on the local machine, and later expanding to multiple parallel Bedrock servers on the same host.

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
D:\Docker\Minecraft Bedrock Server\
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

`allowlist.json` controls who can join:

```json
[
  { "name": "Player1", "xuid": "..." }
]
```

`permissions.json` controls admin rights:

```json
{
  "permission": "operator"
}
```

### Outcome

A single Windows machine now functions as a multi-instance Minecraft hosting environment with proper isolation, automation, and reliability.
