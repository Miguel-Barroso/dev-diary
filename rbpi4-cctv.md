# Setting up MJPG-Streamer on a Raspberry Pi 4

This guide documents how to migrate and run mjpg-streamer-experimental from a Raspberry Pi 3 to a Pi 4.

## Steps

1. Copy source folder from Pi 3 to Pi 4  
   Use `rsync` or `scp` to copy the mjpg-streamer-experimental folder:

    ```bash
    rsync -avz pi@raspberrypi3:~/Applications/mjpg-streamer/mjpg-streamer-experimental ~/Applications/mjpg-streamer/
    ```

2. Copy the systemd service file  
   Copy your existing `mjpg-streamer.service` to `/etc/systemd/system/` on the Pi 4:

    ```bash
    sudo cp ~/Applications/mjpg-streamer/mjpg-streamer.service /etc/systemd/system/
    ```

3. Install required build dependencies  
   Ensure the Pi 4 has `cmake`, `build-essential`, and other required packages:

    ```bash
    sudo apt update
    sudo apt install cmake build-essential libjpeg-dev
    ```

4. Build MJPG-Streamer on the Pi 4  
   Enter the mjpg-streamer-experimental folder and build the project so the binaries match the Pi 4 architecture:

    ```bash
    cd ~/Applications/mjpg-streamer/mjpg-streamer-experimental
    mkdir -p _build && cd _build
    cmake -DCMAKE_BUILD_TYPE=Release ..
    make
    ```

5. Copy binaries, plugins, and HTML files to system-wide locations:

    ```bash
    sudo cp _build/mjpg_streamer /usr/local/bin/
    sudo mkdir -p /usr/local/lib/mjpg-streamer
    sudo cp _build/plugins/input_uvc/input_uvc.so /usr/local/lib/mjpg-streamer/
    sudo cp _build/plugins/output_http/output_http.so /usr/local/lib/mjpg-streamer/
    sudo cp -r www /usr/local/share/mjpg-streamer/
    ```

6. Update the systemd service file  
   Make sure the `ExecStart` line points to the correct paths and includes your credentials:

    ```bash
    ExecStart=/usr/local/bin/mjpg_streamer \
      -i "/usr/local/lib/mjpg-streamer/input_uvc.so -d /dev/video0 -r 640x480 -f 15" \
      -o "/usr/local/lib/mjpg-streamer/output_http.so -p 8080 -w /usr/local/share/mjpg-streamer/www -c admin:<YOUR_PASSWORD>"
    ```

7. Reload systemd and start the service:

    ```bash
    sudo systemctl daemon-reload
    sudo systemctl enable mjpg-streamer
    sudo systemctl start mjpg-streamer
    sudo systemctl status mjpg-streamer
    ```

8. Test the stream  
   - **Curl test (with credentials):**

        ```bash
        curl -u admin:<YOUR_PASSWORD> "http://<pi-lan-ip>:8080/?action=stream"
        ```

   - **VLC test:**

        ```
        http://admin:<YOUR_PASSWORD>@<pi-lan-ip>:8080/?action=stream
        ```

   - **Browser test:**  
     Open `http://admin:<YOUR_PASSWORD>@<pi-lan-ip>:8080/?action=stream` in Chrome or Firefox.

---

💡 **Notes / Tips:**

- Always build MJPG-Streamer on the target device to ensure the binaries match the CPU architecture.  
- The `www` folder contains the MJPEG viewer and must be copied recursively (`-r`).  
- If using HTTP authentication, don’t forget to include credentials in test URLs.  
- For debugging, stop the service and run `mjpg_streamer` manually in a terminal to see plugin logs in real time.

## Monitoring the MJPG-Streamer Service

You can check the real-time status and logs of MJPG-Streamer using `systemctl` and `journalctl`.

### 1. View current status

```bash
sudo systemctl status mjpg-streamer
```

### 2. Tail live logs
```bash
sudo journalctl -u mjpg-streamer -f
```

•	The -f flag “follows” the log, showing new output as it arrives.
•	This is especially useful if you want to see if the plugins are starting correctly or if there are errors with your camera.

### 3. Stop the service for manual debugging
If you want to see detailed plugin output:
```bash
sudo systemctl stop mjpg-streamer
/usr/local/bin/mjpg_streamer \
  -i "/usr/local/lib/mjpg-streamer/input_uvc.so -d /dev/video0 -r 640x480 -f 15" \
  -o "/usr/local/lib/mjpg-streamer/output_http.so -p 8080 -w /usr/local/share/mjpg-streamer/www -c admin:<YOUR_PASSWORD>"
```
•	Run MJPG-Streamer manually in a terminal to see verbose output directly.
•	Once done, press Ctrl+C to stop, then restart the service:
sudo systemctl start mjpg-streamer
```bash
sudo systemctl start mjpg-streamer
```

## Connecting MJPG-Streamer to OBS Studio

You can use your MJPG-Streamer feed as a source in OBS Studio for live streaming or recording.

## Streaming MJPG-Streamer to OBS using FFmpeg

If the VLC Video Source plugin is unavailable or problematic in your OBS Flatpak, you can use FFmpeg to relay the MJPG-Streamer feed as an RTMP stream that OBS can easily consume.

### 1. Install FFmpeg
Ensure FFmpeg is installed on your machine:

```bash
sudo apt update
sudo apt install ffmpeg
```

### 2. Relay MJPG-Streamer feed to RTMP
Run FFmpeg to read the MJPEG stream from your Raspberry Pi and push it to a local RTMP server (for example, OBS’s built-in obs-rtmp or Nginx RTMP):

```bash
ffmpeg -i "http://admin:<YOUR_PASSWORD>@<pi-lan-ip>:8080/?action=stream" \
       -f flv rtmp://localhost/live/stream
```

- `-i "http://admin:<YOUR_PASSWORD>@<pi-lan-ip>:8080/?action=stream"` — the MJPEG source from your Pi.
- `-f flv rtmp://localhost/live/stream` — outputs as an RTMP stream that OBS can use as a Media Source.

### 3. Open OBS Studio
Launch OBS Studio on your computer.

### 4. Add a new Media Source
1. In the **Sources** panel, click the **+** button.
2. Select **Media Source**.
3. Name it something like `MJPG-Streamer`.

### 5. Configure the stream URL
- Check **Input is URL** (or similar option depending on OBS version).
- Enter the stream URL, including credentials:

rtmp://localhost/live/stream

- Make sure **Use hardware decoding when available** is enabled for better performance.
- Uncheck **Local file** if prompted.

### 6. Adjust settings
- Set **FPS** to match your MJPG-Streamer settings (e.g., 30 fps).
- Adjust the resolution to 1920x1080 (or whatever your camera is streaming).

### 7. Test the stream
- Click **OK** to add the source.
- You should now see the live camera feed in OBS Studio.
- Resize and position the feed as desired in your scene.

### 8. Optional: Add filters
- You can apply **color correction**, **cropping**, or **scaling filters** to your MJPG-Streamer source directly in OBS.

💡 **Tips**
- Make sure your network connection is stable; MJPEG at 1080p/30 fps is bandwidth-intensive.
- If the stream is laggy, consider lowering FPS or resolution in the MJPG-Streamer service.

💡 Notes:
	•	Running FFmpeg like this keeps the feed in real-time.
	•	You can adjust resolution or framerate in FFmpeg using flags like -r 30 -s 1280x720 if needed.
	•	Make sure your RTMP server is running and accessible at localhost.