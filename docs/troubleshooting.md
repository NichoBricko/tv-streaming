# Troubleshooting

**Start here:** `./setup.sh status` shows what's installed and running. `./setup.sh report` (current boot) or `./setup.sh report -1` (previous boot) writes every relevant log into one file under `~/.cache/sunshine-on-demand/`. Set `SUNSHINE_LOG_LEVEL="debug"` (then `./setup.sh install --user`) to also record every request the Moonlight client makes.

With the Claude Code plugin, run `/sunshine-on-demand:troubleshoot` and describe what you saw.

## Symptoms
| Symptom | Check / fix |
|---|---|
| **Wake** does nothing (PC awake) | `journalctl -u sunshine-wol -n 20`. "not the allowed client (CLIENT_IP)" → only with `FIREWALL_SCOPE="client"`: the client's IP changed (fix `CLIENT_IP` or use the default `"lan"`), reinstall. Nothing logged → the firewall rule for UDP 9 or the socket isn't active (`./setup.sh status`). |
| **Wake** doesn't wake a sleeping/off PC | BIOS settings ([linux.md](linux.md#3-wake-on-lan-in-the-biosuefi)); `nmcli -g 802-3-ethernet.wake-on-lan con show "<conn>"` → `magic`; use Ethernet, not Wi-Fi. |
| After a Wake from **power-off** you get the normal login screen | TV session off? (`TV_SESSION="yes"`.) Otherwise the TV check didn't see the TV: `journalctl -u sunshine-tv-clientcheck -b`; "no streaming client known yet" → stream once (its MAC is learned then) or set `CLIENT_IP`. `sudo /usr/local/lib/sunshine-on-demand/sunshine-tv-autologin client-scan` tests the detection. Press **Wake** again at the login screen (fallback trigger). |
| **Every** manual boot lands in the TV session | Your TV/box answers pings in standby (Quick Start+, Instant On, Android TV network standby). Turn that off on the TV, or set `TV_AUTOLOGIN="on-wake"` (two presses). |
| Wake works (the PC starts) but Moonlight never connects / stays "offline" | Only with `FIREWALL_SCOPE="client"`: the TV connects from another IP than `CLIENT_IP` (typically it is **also on Wi-Fi**), and the firewall blocks it. `./setup.sh report` lists blocked connections by source IP, and `sunshine-idle-stop` logs a warning (`journalctl --user -t sunshine-idle-stop`). Fix: the default `FIREWALL_SCOPE="lan"`, then `install --system`. Either way, turn the TV's Wi-Fi off when it's cabled (LG: Settings → General → Network → Wi-Fi Connection → off); it streams better over the cable. |
| After **resume from sleep**, Wake does nothing and Moonlight can't connect (Sunshine "already running") | Sunshine started before the GPU's outputs were back and found no display (`Fatal: Unable to find display or encoder` in `journalctl --user -u <sunshine unit>`). `sunshine-healthcheck.service` restarts it automatically, and a **Wake** re-runs the check; see `journalctl --user -t sunshine-on-demand`. If it gives up: `sunshine-on-demand stop; sunshine-on-demand start`. |
| Moonlight stays "offline" although Sunshine runs | Moonlight's Wake only waits ~15 s. Press **Retry**, or go back and select the PC again. |
| Stream shows the **lock screen** | `journalctl --user -t sunshine-session-lock`. Your locker must honour `loginctl unlock-session` (KDE/GNOME do). |
| Black screen / no picture | `./setup.sh setcap` (after **every** Sunshine update), or set `SUNSHINE_CAPTURE` (portal/wlr/x11). |
| Blocky picture | Moonlight's bitrate is too low; the default can be ~10 Mbps. Use 50–80 Mbps on gigabit boxes, about 40 on smart TVs (see next row). |
| **Sporadic stutter / fps drops** although the PC renders far above 60 fps | Usually **keyframe bursts** overflowing a TV with a 100 Mb/s port or a weak SoC; see [Stream stutter](#stream-stutter-on-smart-tvs). |
| Display didn't switch / restore | `journalctl --user -t sunshine-display-mode`; `sunshine-display-mode current`; check `DISPLAY_OUTPUT` and that the mode exists. |
| Steam window wrong size after a stream | **Best fix:** Steam → Settings → Interface → **"Scale text and icons to match monitor settings" off** (saved as `"DPIScaling" "0"` in `~/.steam/registry.vdf`); Steam then keeps a fixed size whatever resolution the screen switches to, and Big Picture still scales itself. Otherwise `sunshine-steam-reset` restarts Steam after the stream; if a game was still running it waits until the game closes (`journalctl --user -t sunshine-steam-reset`). |
| PC still unlocked / in 4K after leaving the stream | You disconnected without **quitting** the app. Quit from Moonlight's menu, or run `sunshine-on-demand stop`. |
| Sunshine stopped mid-session | `journalctl --user -u sunshine-idle-stop`. It only stops after a disconnect + `IDLE_LIMIT`. |
| **Screen sharing broken** on the desktop (Discord/Vesktop "Go Live", OBS, browser) after the PC booted into the TV session | The TV session left `xdg-desktop-portal` running with the GTK fallback and no ScreenCast. Fixed: the TV session now stops the portals when it ends. On an older install: `systemctl --user restart xdg-desktop-portal`, then restart the app. Check: `busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \| grep ScreenCast`. |
| Controller lag / drop-outs | See [Controller](#controller) below, and [extras/xbox-controller-bluetooth](../extras/xbox-controller-bluetooth/README.md) for ~1 s Bluetooth dropouts. |
| Controller **won't connect or pair at all** ("could not connect", `AuthenticationCanceled`, `btmon`: `Connection Failed to be Established (0x3e)`) although it pairs with a phone | **Open issue** after the xbox-controller-bluetooth extra on a Realtek Wi-Fi/Bluetooth combo chip: undo it (`revert.sh`), turn the Wi-Fi radio back on, reload `btusb`, restart bluetooth, then pair again. Details: [known problem](../extras/xbox-controller-bluetooth/README.md#known-problem-the-pc-cant-connect-to-the-controller-any-more). |

## Lessons learned (things that cost us hours)
- **Moonlight only contacts a PC** when you open its page, press Retry, when the PC announces itself on the network (mDNS), and **for 15 s after Wake**. It does *not* keep polling an offline PC. A cold boot takes longer than 15 s, which is why the TV session uses the TV-ping trigger.
- **Sunshine's prep `undo` steps run bottom-to-top.** Anything that must happen after the resolution is restored has to sit *above* the display step.
- **Steam caches its UI scale** (`AutoScaleFactor`) while the screen is 4K, and only recalculates it on restart. Turning off "Scale text and icons to match monitor settings" avoids it entirely; `sunshine-steam-reset` (restart, deferred while a game runs) is the fallback.
- **A TV with both cable and Wi-Fi connected** answers on both IPs. Moonlight's Wake went out over the cable, its connections over Wi-Fi, and an IP allowlist blocked them. Unplugging the cable for a moment is enough for webOS to join Wi-Fi, and it stays on Wi-Fi after the cable is back. A Developer-Mode app can't change the TV's network settings, and no Moonlight client can pick its interface. That's why the default firewall scope is the LAN and the TV is identified by its pairing certificate, not its IP.
- **Sunshine stays "active" when it found no display at startup.** Right after resume the GPU's outputs can be missing for a few seconds; Sunshine then logs `Fatal: Unable to find display or encoder` but keeps running, so "already running" doesn't mean "working". The health check restarts it. (A screen that is merely off/DPMS is fine.)
- **Controller input doesn't count as desktop activity**, so without the sleep inhibitor the PC can suspend mid-game.
- **`kwin_wayland --lockscreen` doesn't report the lock to logind**, so `loginctl unlock-session` can't unlock it. The TV session locks through logind instead.
- **The user's systemd manager outlives the TV session.** Portals D-Bus-activated inside the bare KWin (no `XDG_CURRENT_DESKTOP` yet) pick the GTK fallback and keep running into the next Plasma login, so screen sharing silently fails there. The TV session stops them on exit.
- **Many motherboards report SMBIOS Wake-up Type "Power Switch" for every boot**, Wake-on-LAN included, so the boot reason is unreliable.
- **Flatpak Sunshine runs prep commands inside its sandbox**; they need `flatpak-spawn --host` (the installer does this).
- **sudo needs a real terminal.** Neither Claude nor `!`-prefixed commands can answer the password prompt.
- **Compiled Python files (`__pycache__`) embed absolute paths.** Keep them out of git.
- **BlueZ settings don't reset with the service.** `[LE]` values from `main.conf` stay in the kernel after `systemctl restart bluetooth`; only reloading the driver (`modprobe -r btusb && modprobe btusb`) or a reboot resets them. A "reverted the file, still fails" test is invalid without that.
- **Radio-level Bluetooth tweaks on Wi-Fi/Bluetooth combo chips can backfire.** Turning the Wi-Fi radio off (and btusb autosuspend off) coincided with the PC no longer being able to connect to the controller at all; undoing them fixed it (still being investigated).

## Stream stutter on smart TVs
Measured on the reference LG (webOS 22, 4× Cortex-A55, 100 Mb/s port) during a 3.5 h session:
- **0 packets dropped by the TV's network port,** but **52,077 UDP receive-buffer overflows**: packets arrived, and Moonlight didn't read them in time.
- **33 keyframes** were too large for error correction ("Skipping FEC for abnormally large encoded frame" in Sunshine's log).

Keyframes leave the PC at line rate. A TV port or SoC can't absorb the burst, and one lost packet breaks the frame. The TV's background services were *not* busy: 5% CPU at idle.

**Verified fix on the reference setup:** decoder **NDL** + `SUNSHINE_STRICT_RC="yes"`; the bitrate was *not* the cause, and **60 Mbps** runs clean. Measured with `lgtv-stream-stats`:

| Settings | Duration | TV drops | Oversized frames without FEC |
|---|---|---|---|
| 4K, 55 Mbps, decoder auto, default rate control | 23 min | **170 / min** | 8 |
| 4K, **40 Mbps, NDL, strict rate control** | 39 min | **0** | 0 |
| 4K, **60 Mbps, NDL, strict rate control** | 46 min (incl. fast driving) | **0** | 0 |

Whether NDL or the strict rate control matters more isn't isolated (they were switched on together). Pacing (step 3) wasn't needed. The remaining drops (~8k) happened around **stream starts / loading in**, outside the measured windows; to see them, run `lgtv-stream-stats watch` before connecting.

**Measure** (LG with the [Developer Mode extra](../extras/lg-webos-devmode/README.md)): run `lgtv-stream-stats start`, play 15 min, then `lgtv-stream-stats stop`. That gives drops per minute. Change one thing at a time, in this order:
1. **Moonlight:**
   - decoder **NDL** explicitly, not Auto;
   - bitrate: on an unknown TV start at **40 Mbps** (the Moonlight TV FAQ's sweet spot for webOS), then raise it while the drops stay at ~0 (60 was clean on the reference LG);
   - HDR off;
   - the TV **not** also on Wi-Fi.
2. **`SUNSHINE_STRICT_RC="yes"`**: smaller keyframes at scene changes (AMD/Intel).
3. **`STREAM_PACING_MBIT=90`**: paces only the video stream so keyframes arrive as an even flow (system part; run `install --system`).
4. **1440p60** in Moonlight (the TV upscales): about 44% less decoding work.
5. **A streaming box with gigabit Ethernet** (Shield Pro, Google TV Streamer, Ethernet Apple TV 4K): the outright fix.

**Not effective:**
- **LG "debloat" tools:** `cleanyourtv` is Android-only, and its webOS ports only replace the home screen.
- **Rooting:** no public method for current webOS 22 firmware.
- **USB gigabit adapters.**

The TV's ad and tracking settings are worth turning off for privacy ([tv-clients.md](tv-clients.md#lg-privacy-settings)), but there's no evidence they help performance.

## Controller
- **Pair it with the PC, if possible.** That gives the lowest latency, and the TV can then be display-only (`BLOCK_CLIENT_CONTROLLER="yes"`). The LG TV's Bluetooth added very noticeable lag.
- **Xbox controller won't pair over Bluetooth on Linux:** update its firmware first (Xbox Accessories app on Windows/Xbox; 5.09 failed, 5.17 worked). If the desktop pairing wizard fails, use `bluetoothctl`: `agent NoInputNoOutput`, `default-agent`, `scan le`, `pair <MAC>`, `trust <MAC>`, `connect <MAC>`.
- **Frequent disconnects:** attach the motherboard's **Wi-Fi/Bluetooth antennas**. Without them the reference PC got a disconnect every 8–30 s.
- **Can't connect at all after the dropout fix:** an open issue; see the [known problem](../extras/xbox-controller-bluetooth/README.md#known-problem-the-pc-cant-connect-to-the-controller-any-more). `revert.sh` + Wi-Fi radio on + reloading `btusb` fixed it on the reference PC.
- **Occasional ~1 s dropouts** even with antennas (`failed to send FF report` in the kernel log): run [extras/xbox-controller-bluetooth](../extras/xbox-controller-bluetooth/README.md). It sets BlueZ LE parameters (2 s supervision timeout), turns btusb autosuspend off and the unused Wi-Fi radio off, and shows how to read the disconnect reason with `btmon`. The fallbacks are a USB-C cable or the Xbox Wireless Adapter (xone driver, unmaintained since 2026).
- **Wired controller not detected:** front-panel USB-C ports often carry no data. Use a **rear** port and a data cable.
