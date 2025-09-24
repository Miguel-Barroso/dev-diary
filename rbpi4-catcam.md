# Streaming with Raspberrypi 4 and C525 webcam
**Last updated: 2025-09-24**
## Background
The Raspberry Pi 3 and 4, model B-boards can relay UVC-compliant USB camera feeds over the local network. This can be utilized for live-streaming your cats, but also for surveillance applications, etc.
That said, the boards are not powerful enough to stream the camera-feed directly as it is too much data, while USB-buses and networking share the same limited bandwidth. Instead, one can ingest the feed as motion-JPEG (MJPG) data, which is basically a JPEG capture of each frame, which are relayed to a HTTP server which broadcasts on the local network.
There are many ways to achieve this however in this guide the MJPG-Streamer-Experimental library will be utilized. Note that this library is no longer maintained but remains a reliable option.

## Materials
- Raspberrypi 3 or 4, model B with at least 2GB RAM
- Protective case (RBPi4 may need active cooling)
- Raspbian 64-bit OS
- USB-A webcam (USB-C webcams send too much data for the BUS to handle)
- Adequate power adapter (i.e., 5V, 3A for RBPi4)
- [mjpg-streamer](https://github.com/jacksonliam/mjpg-streamer)

## Procedure
### Raspberry Pi Setup
Setup the Raspberry Pi so that it has the latest OS and updates. Make sure you can connect to it via SSH from another device. VNC is optional but helpful (Tiger VNC is an excellent client). Connect the USB-camera and check `dmseg` that there are no communication problems. Otherwise, check that the powersupply is of correct rating, or switch camera.
### Installing mjpg-streamer
First, make a directory called mjpg-streamer:

    mkdir -p mjpg-streamer
Download the project's zip file:
https://github.com/jacksonliam/mjpg-streamer/archive/refs/heads/master.zip
Extract its contents into the new folder.

 Ensure the Pi 4 has `cmake`, `build-essential`, and other required packages:

    sudo apt update
    sudo apt install cmake build-essential
    libjpeg-dev
Navigate to:

    cd mjpg-streamer/mjpg-streamer-experimental
Build the project:

    mkdir -p _build && cd _build
    cmake -DCMAKE_BUILD_TYPE=Release ..
    make
Make sure you build it on each target machine as there may be differences in the resulting binaries depending on which RBPi you have.

Copy binaries, plugins, and HTML files to system-wide locations:

    sudo cp _build/mjpg_streamer /usr/local/bin/
    sudo mkdir -p /usr/local/lib/mjpg-streamer
    sudo cp _build/plugins/input_uvc/input_uvc.so /usr/local/lib/mjpg-streamer/
    sudo cp _build/plugins/output_http/output_http.so /usr/local/lib/mjpg-streamer/
    sudo cp -r www /usr/local/share/mjpg-streamer/
This way the binaries are accessible by the system, along with the necessary plugins and HTML files.

## Creating mjpg-streamer service in Systemd
Systemd allows runs your program as a service on boot which means it the program will be restarted if there are any crashes. Makes it much more resilient and the Raspberry Pi acts more like a utility than a computer.

Begin by creating a service:

    sudo nano /etc/systemd/system/mjpg-streamer.service

Fill it out like this:

    [Unit]
    Description=MJPG-Streamer webcam service
    After=network.target
    
    [Service]
    Restart=always
    RestartSec=1
    User=pi-admin
    Group=pi-admin
    ExecStart=/usr/local/bin/mjpg_streamer \
      -i "/usr/local/lib/mjpg-streamer/input_uvc.so -d /dev/video0 -r 1280x720 -f 30" \
      -o "/usr/local/lib/mjpg-streamer/output_http.so -p 8080 -w /usr/local/share/mjpg-streamer/www -c admin:my-test-password"
    StandardOutput=journal
    StandardError=journal
    
    [Install]
    WantedBy=multi-user.target
It will start the mjpg-streamer service after network stack has been loaded. It will restart as soon as there is a problem. Make sure the user and group matches that of your user. You may have to change the permissions of your user so you that you can access the files used by the service.

Make sure that the paths in `ExecStart` points to the correct locations of the mjpg-streamer binary (/usr/local/bin/mjpg_streamer), the plugins (/usr/local/lib/mjpg-streamer/) and the html files (/usr/local/share/mjpg-streamer/www).

It is also here that you can set credentials for accessing the stream, set the port used and the resolution of the video. Note, if your webcam is not /dev/video01 you have to check using:

    sudo apt install v4l-utils
    v4l2-ctl --list-devices
It should list all webcams available. Change the device number accordingly in the service file. Note that devices IDs may change after reboots. To make it persistent, one can create a `udev` rule or use `-d /dev/video/by-id/...` in mjpg-streamer.

## Starting the service, troubleshooting
First, load the new service into systemd:

    sudo systemctl daemon-reload

Then, start the service:

    sudo systemctl start mjpg-streamer

Check how it went:

    systemctl status mjpg-streamer
Any error messages should now be displayed. Usually, the problems are either with permissions for the user, the paths to the binaries, plugins and HTML files or formatting issues in the mjpg-streamer.service file itself.

Systemd servives often fail if the user does not have access to the webcam device. Try:
    
    sudo usermod -aG video pi-admin
This ensures the pi user can access `/dev/video0` without `sudo`.

After you correct any issues, you can restart the service to see the effects:

    sudo systemctl restart mjpg-streamer

Once the stream is up and running, the service relays MJPG data as an http stream over the local network.

For auto-start on reboot:

    sudo systemctl enable mjpg-streamer

Access it via browser, VLC etc:
http://admin:REDACTED@192.168.1.142:8080/?action=stream

The stream can be fed into different software, depending on the purpose; either live-streams or surveillance, etc.

## Live-streaming via OBS Studio
On a more powerful machine, install OBS Studio.

Add a new Media source, uncheck "Local file" and paste the URL:
http://admin:REDACTED@192.168.1.142:8080/?action=stream
Check "Use hardware acceleration where available".


Configure OBS Studio to stream on your favorite platform.

Note, if you do not see the stream in OBS but it works in VLC, here is a workaround you can try:

1. Some installations of OBS Studio allows you to download and install a VLC source. Use it instead of the Media source.
2. Run VLC standalone and capture the window in OBS.
In order to get a clean picture without any controls you can run VLC via CLI. Instruction for Linux follows:

## Create VLC Watchdog Script
In order to start VLC so it can be captured by OBS and to restart the stream in case there are any problems, create a watchdog script:

    nano autovlc.sh

Edit the file to look like this:

    #!/bin/bash
    while true; do
      cvlc --no-video-title-show --quiet --network-caching=1000 \
           --width=1280 --height=720 --no-autoscale \
           "http://admin:REDACTED@192.168.1.142:8080/?action=stream"
      echo "[`date`] VLC crashed or stream ended. Restarting in 5s..."
      sleep 5    done

`cvlc` → runs VLC without the full GUI, just the video window.

`--no-video-title-show` → hides the filename overlay.

`--quiet` → suppresses extra console messages (still prints errors if something breaks).

 `--network-caching=1000` → 1 second buffer, helps smooth network hiccups.

 `--no-autoscale` → prevents automatic scaling to fit the window

Infinite `while true` loop → automatically restarts VLC if it exits/crashes.
`echo …` + `sleep 5` → Prints a timestamped message when VLC drops and it waits 5s before retrying.

Make the file executable and run the file:

    chmod +x autovlc.sh
    ./autovlc.sh

VLC will auto-retry  indefinitely in case the Raspberry Pi encounters any problems.

Go ahead and capture this window via OBS Studio.
## autovlc Service
For best resilience and most utility, make autovlc.sh a service:

    sudo nano /etc/systemd/system/autovlc.service
Edit the file like this:

    [Unit]
    Description=Auto VLC (user session)
    After=graphical.target
    
    [Service]
    Type=simple
    ExecStart=/home/macmini2012/autovlc.sh
    Restart=always
    Environment=DISPLAY=:0
    Environment=XDG_RUNTIME_DIR=/run/user/1000
    User=macmini2012
    
    [Install]
    WantedBy=default.target
**Description** → A short text describing what the service is. Useful for `systemctl status`.
    
**After=graphical.target** → Tells systemd to start this service **after the graphical environment (your desktop) has loaded**. This is important because VLC needs a running X/Wayland session to open a window.

**Type=simple** → Default type; systemd assumes the process started by `ExecStart` is the main service process.
    
**ExecStart** → The command to run. Here, it runs your VLC script.
    
**Restart=always** → If the script or VLC crashes, systemd will automatically restart it.
    
**Environment=DISPLAY=:0** → Tells VLC which X display to use. Usually `:0` is your main desktop session.
    
**Environment=XDG_RUNTIME_DIR=/run/user/1000** → VLC needs this to access session-specific resources like sockets. Replace `1000` with your user’s UID (`id -u macmini2012`).
    
**User=macmini2012** → Runs the service as your regular user (so it can access your X session).
**WantedBy=default.target** → Tells systemd when to enable/start this service. `default.target` is your normal user session target, so the service will start when you log in.

For auto-start on reboot:

    sudo systemctl enable autovlc

### Key points

1.  **This is a user-level GUI service**, not a system-level headless service. This is why  `DISPLAY` and `XDG_RUNTIME_DIR` are set.
    
2.  Running it as a system service under `/etc/systemd/system` without these environment variables causes VLC to fail (errors like `XDG_RUNTIME_DIR is invalid`).
    
3.  `Restart=always` + the autovlc.sh script loop ensures VLC keeps trying if the stream fails.
    
4.  The script still handles retrying if VLC exits normally or crashes — systemd just guarantees it’s automatically restarted even outside the terminal.

Note that there may be prompts for user authentications when the script starts the first time.

