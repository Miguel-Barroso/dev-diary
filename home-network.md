# Home network: the Orbi mesh, and the cheap cameras on it

The house runs on a Netgear Orbi RBR50 with four satellites (two RBS50s, two older RBS20s). The
Orbi only routes: DNS and DHCP live on the Mac mini, with the Pi 3 as standby (see their logs). This
file covers the mesh itself and the least trustworthy things attached to it.

## 2026-10-28 — Two cameras that phoned home with a factory password, and a router backup that isn't encrypted

### The cameras that weren't ONVIF

Two of the house's cameras are a cheap rebranded model, sold as "Fredi". Their web UI has an ONVIF
section with a port number, so I tried to use it for camera-side motion events in QVR Pro. The port
refuses connections. Neither camera answers ONVIF discovery (the Tapo next to them does), and nothing
on them answers an ONVIF request. The setting is a port number with no on/off switch, most
likely left over from a firmware family shared across models. The firmware is old, and there's
nothing newer: the brand has no download page, and flashing another brand's image for the same chip
family is a good way to brick a camera. So motion detection
for these two stays on the NAS side.

### What they did have

One camera had P2P remote viewing switched on, and checked in every 16 minutes or so with servers under
`runtopcam.com` and `iruntop.com`. Runtop is the remote-viewing provider whose service is baked into
the firmware; the hardware maker is still unknown. I had never set the P2P password, so it was a
factory default. Anyone with the ID printed on that camera's sticker and the
default password could have watched it from anywhere, probably since the day I installed it. I can't
tell whether anyone did, because nothing kept a record.

Dumping the P2P settings also showed a hole in my own masking: the regex expected `key="value"`, and
the firmware writes `p2p_pwd = "value"`, with spaces. It's the same mistake as the database password
on Astromeda, and the lesson stands: test the masking against the real output before running it on
secrets.

### Fencing them in

P2P is off on both, and the cameras no longer reach the internet. Since the change, neither has gone
looking for Runtop.

One thing I learned on the way: blocking a device in the Orbi app also cut it off from the LAN, which
killed the recordings on the NAS. The web UI's Block Services only applies to traffic leaving
through the router, so it can cut a device off from the internet without touching the LAN.

### A router backup that's only scrambled

The Orbi's config backup is a 700 KB file that's mostly zeros: a tar header, then, at a fixed offset,
a 12-byte header and a 48 KB blob. The blob holds the router's settings as about 1,700 `key=value`
pairs, XORed word by word with glibc's `random()` seeded with the header's own magic number. The
giveaway was that every fourth byte had its top bit clear, because `random()` returns 31 bits. The
third header word is a checksum: the inverted 32-bit sum of the plaintext words. With both known, a
backup decodes and re-encodes byte for byte.

So the backup holds the Wi-Fi password, the hidden backhaul key and the admin login in what is
effectively plain text. Treat it like a password, not like a settings file.

### The last firmware, installed by hand

Firmware 2.7.6.6 (January 2026) was never offered automatically, even with auto-update on, so I
installed it by hand. Satellites went first, one at a time, the two RBS20s with their own image, and
the router last. The release notes say only "addresses security vulnerabilities". The whole series is
end-of-service now, so this is very likely the last firmware it will get.

The decoded config showed the wireless settings needed nothing. 5 GHz runs on a non-radar channel,
beamforming and 802.11k are on, and everything else is at defaults. The weak spots are physical: the
one satellite on a wireless backhaul links at −68 dBm, and the cat-cam Pi's Wi-Fi sits at the same level.
