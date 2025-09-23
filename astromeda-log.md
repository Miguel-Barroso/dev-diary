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