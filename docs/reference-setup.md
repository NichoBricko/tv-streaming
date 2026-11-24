# Reference setup (where this was built and tested)

| Part | Model |
|---|---|
| OS / desktop | CachyOS (Arch-based), kernel 7.3, **KDE Plasma 6 on Wayland**, systemd 262 |
| CPU / GPU | AMD Ryzen 7 9800X3D (iGPU unused) / **AMD Radeon RX 9070 XT**, Mesa radeonsi |
| Motherboard | ASUS PRIME B850M-F WIFI: Realtek r8169 Ethernet, Realtek RTL8851BE Wi-Fi + RTL8851BU Bluetooth |
| Monitor | Acer VG240Y V, 1920x1080 @ 165 Hz (accepts a 3840x2160 @ 60 signal and downscales it) |
| TV | LG 55NANO766QA, webOS 22, 100 Mb/s Ethernet |
| Client | Moonlight TV 1.6.36, sideloaded via Developer Mode |
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

## Lessons learned
- **The Moonlight default bitrate is low.** At ~7 Mbps a 4K picture looks blocky. Set 50–65 Mbps.
- **Sunshine prep `undo` steps run in reverse order.** The Steam step must sit *above* the display step, so Steam is handled after the resolution is restored.
- **Steam caches its UI scale** (`AutoScaleFactor` in `~/.local/share/Steam/config/config.vdf`) while the screen is 4K, and only recalculates on restart. Hence `sunshine-steam-reset`.
- **Controller input doesn't count as desktop activity**, so without the inhibitor the PC could sleep mid-game.
- **The TV's Bluetooth was too laggy** for the controller. Pairing with the PC's Bluetooth only worked after a controller firmware update (5.09 → 5.17), and only became stable once the motherboard's **Wi-Fi/Bluetooth antennas** were attached.
- **The front-panel USB-C** on the case carried no data. Use rear ports for wired controllers.
- **Moonlight TV sends Wake-on-LAN as a broadcast to UDP 9** (`mariotaku/commons-c` `net/wol/wol.c`), then polls the PC for 15 s.
- **The LG Developer Mode session is 1000 h** and renewable through LG's `ResetDevModeSession` endpoint with the token from `/var/luna/preferences/devmode_enabled`.
- For RDR2-specific problems (umu Steam ID, non-ASCII Epic name, fake EpicGamesLauncher parent, DX12), see [`extras/rdr2-epic-heroic`](../extras/rdr2-epic-heroic/README.md).
