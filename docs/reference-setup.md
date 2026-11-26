# Reference setup (where this was built and tested)

| Part | Model |
|---|---|
| OS / desktop | CachyOS (Arch-based), kernel 7.3, **KDE Plasma 6 on Wayland**, systemd 262 |
| CPU / GPU | AMD Ryzen 7 9800X3D (iGPU unused) / **AMD Radeon RX 9070 XT**, Mesa radeonsi |
| Motherboard | ASUS PRIME B850M-F WIFI: Realtek r8169 Ethernet, Realtek RTL8851BE Wi-Fi + RTL8851BU Bluetooth |
| Monitor | Acer VG240Y V, 1920x1080 @ 165 Hz (accepts a 3840x2160 @ 60 signal and downscales it) |
| TV | LG 55NANO766QA, webOS 22, 100 Mb/s Ethernet |
| Client | Moonlight TV 1.6.36, sideloaded via Developer Mode; 4K60, **60 Mbps, HEVC, decoder NDL** |
| Controller | Xbox Series X\|S, Bluetooth to the PC |
| Sunshine | CachyOS package, service `app-dev.lizardbyte.app.Sunshine.service`, VAAPI HEVC, KMS capture (`setcap`) |
| Firewall | ufw |

## Verified end to end
- 4K60 HEVC stream at 55 Mbps (~57 Mbit/s on the wire with FEC), 0 network errors, GPU ~70% in RDR2.
- **Wake while awake:** Moonlight "Wake" → `sunshine-wol` accepted the packet → Sunshine up within seconds.
- **Wake from sleep (S3 "deep"):** the PC resumed, `sunshine-resume` started Sunshine, and the stream unlocked the session and re-locked it after.
- Stream started while logged in: it **did not** lock afterwards.
- After a stream: display back to 1080p@165, Steam restarted to the tray with a correct window size, sleep inhibitor released.
- Idle stop: Sunshine stopped 10 min after the last disconnect.
- Wake packets with the wrong MAC or from another IP were ignored (local test).
- **Cold boot, one Wake press (TV session):** power-on → login screen at 6 s → network at 11 s → TV detected by ping at 12 s → locked TV session at 13 s → stream unlocked it and started Steam Big Picture on request. Power button with the TV off → normal login screen. The board reports SMBIOS Wake-up Type "Power Switch" for every boot, so the boot-reason trigger never fires here; the TV ping does.
- Robustness: exiting Steam/Big Picture during or after a stream ends the TV session cleanly; a Wake brings it back (second-Wake trigger at the login screen).
- **Stream stutter fixed:** 4K60 at 55 Mbps showed 170 TV buffer drops/min and sporadic fps dips. **NDL + strict rate control** gave 0 drops at 40 Mbps (39 min) and at **60 Mbps** (46 min incl. fast driving; "very clear"), so the bitrate wasn't the cause. Short stutter can remain in the first seconds after a stream starts.
- **Controller dropouts:** about one every 18 min before; 0 in 71 min after `extras/xbox-controller-bluetooth` (BlueZ LE parameters, btusb autosuspend off, Wi-Fi radio off).

## Lessons learned
- **The Moonlight default bitrate is low.** At ~7 Mbps a 4K picture looks blocky. Set 50–65 Mbps.
- **Sunshine prep `undo` steps run in reverse order.** The Steam step must sit *above* the display step, so Steam is handled after the resolution is restored.
- **Steam caches its UI scale** (`AutoScaleFactor` in `~/.local/share/Steam/config/config.vdf`) while the screen is 4K, and only recalculates on restart. Hence `sunshine-steam-reset`.
- **Controller input doesn't count as desktop activity**, so without the inhibitor the PC could sleep mid-game.
- **The TV's Bluetooth was too laggy** for the controller. Pairing with the PC's Bluetooth only worked after a controller firmware update (5.09 → 5.17), and only became stable once the motherboard's **Wi-Fi/Bluetooth antennas** were attached.
- **The front-panel USB-C** on the case carried no data. Use rear ports for wired controllers.
- **Moonlight TV only contacts a host** on page open, Retry, mDNS announcements and for 15 s after Wake - it does not keep polling an offline PC. A cold boot takes longer than 15 s, hence the TV-ping trigger.
- **`kwin_wayland --lockscreen` doesn't report the lock to logind** (LockedHint stays "no"), so `loginctl unlock-session` can't be used; the TV session locks itself through logind instead.
- **LG TVs in standby** (here) drop off the network completely, so pinging the TV is a reliable "TV is on" signal - but check yours (Quick Start+).
- **Moonlight TV sends Wake-on-LAN as a broadcast to UDP 9** (`mariotaku/commons-c` `net/wol/wol.c`), then polls the PC for 15 s.
- **The LG Developer Mode session is 1000 h** and renewable through LG's `ResetDevModeSession` endpoint with the token from `/var/luna/preferences/devmode_enabled`.
- For RDR2-specific problems (umu Steam ID, non-ASCII Epic name, fake EpicGamesLauncher parent, DX12), see [`extras/rdr2-epic-heroic`](../extras/rdr2-epic-heroic/README.md).
