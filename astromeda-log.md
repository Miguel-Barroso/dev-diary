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

Server runs smoothly on Ubuntu 22.04 LTS (WSL2), 64 GB RAM, no swap, fully Dockerized.

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

A Minecraft Bedrock server can only bind to one port, so running multiple instances requires:

- Each container uses the same internal port (`19132`)
- Each container maps to a **different external port**

This is a fundamental networking constraint — only one service can use a given port per host — so multiple servers must be exposed on different external ports.

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
    volumes:
      - ./rhens-world/data:/data
    restart: unless-stopped
    tty: true
    stdin_open: true

  big-earth:
    image: itzg/minecraft-bedrock-server
    container_name: bedrock-big-earth
    ports:
      - "19133:19132/udp"   # second server, different external port
    environment:
      EULA: "TRUE"
      SERVER_NAME: "Big Earth"
    volumes:
      - ./big-earth/data:/data
    restart: unless-stopped
    tty: true
    stdin_open: true
```

### LAN discovery

Minecraft Bedrock uses broadcast discovery on fixed ports, and Docker isolates broadcast traffic by default. Result: the servers do not appear in the in-game LAN list. This is expected behaviour in Docker environments.

Workaround — disable LAN discovery in `server.properties`:

```
enable-lan-visibility=false
```

Players connect using direct addresses:

| Server       | Address              |
| ------------ | -------------------- |
| Rhen's World | `192.168.x.x:19132`  |
| Big Earth    | `192.168.x.x:19133`  |

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
