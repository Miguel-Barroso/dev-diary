## 🛠️ Minecraft Bedrock Server Recovery & Optimization

1. ✅ **Copied Server Files**  
   Transferred the full `Minecraft Bedrock Server` folder from **QNAP** NAS to local path:  
   `D:\Docker\Minecraft Bedrock Server`.

2. 🐳 **Docker Setup**  
   Installed **Docker Desktop**, navigated to the server folder, and ran:  
   ```bash
   docker compose up -d
   ```
    This pulled and deployed the latest images for:
    ```
    itzg/minecraft-bedrock-server
    ```
    ```
    containrrr/watchtower
    ```

3. 🔥 Firewall Loopback Exception
    Added a loopback exemption to allow local play from the host machine:
    ```
    CheckNetIsolation.exe LoopbackExempt -a -p=S-1-15-2-1958404141-86561845-1752920682-3514627264-368642714-62675701-733520436
    ```
4. 💾 Backup Automation
Updated backup-world-silent.bat script and registered it with Windows Task Scheduler for daily automatic backups to OneDrive.
✅ Successfully tested!

5. ⚙️ Performance Optimization
Configured .wslconfig to disable swap for better memory performance:
    ```
    [wsl2]
    swap=0
    ```
6. 🧪 Testing Complete
Everything tested — the server runs smoothly and performs beautifully on:

    Ubuntu 22.04 LTS (WSL2)

    64 GB RAM / No Swap / Dockerized

🎮 Ready to game!

# 🧱 Dev Diary: Running Multiple Minecraft Bedrock Servers with Docker + Backups

## 📅 Date
2026-05-04

---

## 🎯 Goal

Set up **multiple Minecraft Bedrock servers** on a single machine using Docker, while keeping:

- Clean separation of worlds
- Stable networking
- Automated backups
- Minimal manual intervention

---

## 🧠 Key Insight

A Minecraft Bedrock server **can only bind to one port**, so running multiple instances requires:

> ✅ **Each container uses the same internal port (19132)**  
> ✅ **Each container maps to a different external port**

This is a fundamental networking constraint:

- Only one service can use a given port per host
- So multiple servers must be exposed on different ports :contentReference[oaicite:0]{index=0}

---

## 🐳 Docker Setup

### Base Image

Using:
itzg/minecraft-bedrock-server


This image:
- Automatically downloads latest Bedrock server
- Uses `/data` for worlds and configs
- Exposes UDP port `19132` :contentReference[oaicite:1]{index=1}

---

## ⚙️ docker-compose.yml

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
      - "19133:19132/udp"   # 👈 second server
    environment:
      EULA: "TRUE"
      SERVER_NAME: "Big Earth"
    volumes:
      - ./big-earth/data:/data
    restart: unless-stopped
    tty: true
    stdin_open: true
```


### 🌐 Networking Lessons
❗ LAN Discovery Issue
Minecraft Bedrock uses broadcast discovery on fixed ports
Docker isolates broadcast traffic by default

👉 Result:

Servers don’t show in LAN list

This is expected behavior in Docker environments

✅ Solution

Disable LAN discovery:
```enable-lan-visibility=false```

| Server       | Address           |
| ------------ | ----------------- |
| Rhen’s World | 192.168.x.x:19132 |
| Big Earth    | 192.168.x.x:19133 |

### 📁 Folder Structure
D:\Docker\Minecraft Bedrock Server\
│
├── rhens-world\
│   └── data\
│       ├── worlds\
│       ├── server.properties
│       ├── allowlist.json
│       └── permissions.json
│
├── big-earth\
│   └── data\
│       └── ...
│
└── scripts\
    └── backup-all.bat

### 💾 Backup Strategy
Approach

Use Bedrock’s built-in safe backup commands:
```
save hold
(save files)
save resume
```

This ensures:

No world corruption
Consistent snapshots

### 🧠 Important Note
Although Bedrock supports save query, it is:

Hard to reliably automate in Docker
Can hang or misbehave

👉 Final approach:

Use fixed delay (~10 seconds) instead of polling

### 🛠 Backup Script Design
Key Features
Freezes both servers
Waits 10 seconds
Copies worlds + config
Creates timestamped ZIP
Logs everything
Resumes servers

## Example Flow
1. save hold (both servers)
2. wait 10 seconds
3. copy world data
4. compress backup
5. save resume

## 🧾 Logging System
Instead of silent execution:

All output redirected to:
```backup.log```
Benefits:

Debuggable
Works with Task Scheduler
No UI required

## ⏱ Automation
Configured via Windows Task Scheduler:

Runs daily
Runs whether user is logged in or not
Uses highest privileges

⚙️ Performance Tuning

With two servers:

Setting	Value
max-threads	5
view-distance	16

Why:

Prevent CPU contention
Maintain smooth gameplay

### 🔐 Access Control
allowlist.json

Controls who can join:

```[
  { "name": "Player1", "xuid": "..." }
]
```

permissions.json

Controls admin rights:

```
{
  "permission": "operator"
}
```

⚠️ Lessons Learned

This setup effectively turns a single machine into:

🧱 A multi-instance Minecraft hosting environment

…with proper:

- isolation
- automation
- reliability