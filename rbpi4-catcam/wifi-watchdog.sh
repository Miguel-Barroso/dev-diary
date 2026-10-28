#!/usr/bin/env bash
# wifi-watchdog.sh — bring the Pi 4 back onto WiFi when brcmfmac wedges after an AP hiccup.
# Invoked every minute by wifi-watchdog.timer (as root). Consecutive-failure escalation:
#   2 fails  -> reconnect via NetworkManager
#   4 fails  -> reload the brcmfmac kernel module (clears wedged firmware a reconnect can't)
#   6+ fails -> reboot, unless the box has been up <10 min (boot-loop guard)
set -u

IFACE="${IFACE:-wlan0}"
CONN="${CONN:-preconfigured}"
STATE=/run/wifi-watchdog/fails

mkdir -p "${STATE%/*}"
fails=$(cat "$STATE" 2>/dev/null || echo 0)

# Ping the wlan0 connection's own gateway, NOT the default route's — eth0 holds
# the default route whenever the maintenance cable is plugged in.
gw=$(nmcli -g IP4.GATEWAY device show "$IFACE" 2>/dev/null | head -1)
[ -n "$gw" ] || gw=$(ip -4 route show default dev "$IFACE" 2>/dev/null | awk '{print $3; exit}')

if [ -n "$gw" ] && ping -q -c 2 -W 3 -I "$IFACE" "$gw" >/dev/null 2>&1; then
    [ "$fails" -gt 0 ] && echo "recovered after $fails failed checks"
    echo 0 > "$STATE"
    exit 0
fi

fails=$((fails + 1))
echo "$fails" > "$STATE"
echo "check failed (${fails}x): gw=${gw:-none}; $(/usr/sbin/iw dev "$IFACE" link 2>&1 | head -1)"

# Clear anything that could pin WiFi down no matter the stage (both idempotent).
/usr/sbin/rfkill unblock wifi 2>/dev/null || true
nmcli radio wifi on >/dev/null 2>&1 || true

if [ "$fails" -ge 6 ]; then
    if [ "$(cut -d. -f1 /proc/uptime)" -lt 600 ]; then
        echo "reboot stage reached but uptime <10 min — waiting"
    else
        echo "escalating to reboot"
        systemctl reboot
    fi
elif [ "$fails" -eq 4 ]; then
    echo "reloading brcmfmac"
    modprobe -r brcmfmac_wcc 2>/dev/null || true
    modprobe -r brcmfmac || echo "brcmfmac unload failed"
    sleep 3
    modprobe brcmfmac
    sleep 10
    nmcli connection up "$CONN" ifname "$IFACE" || true
elif [ "$fails" -eq 2 ]; then
    echo "reconnecting via NetworkManager"
    systemctl is-active --quiet NetworkManager || systemctl restart NetworkManager
    nmcli device disconnect "$IFACE" 2>/dev/null || true
    sleep 2
    nmcli device wifi rescan 2>/dev/null || true
    sleep 3
    nmcli connection up "$CONN" ifname "$IFACE" || true
fi
exit 0
