# Troubleshooting

**Start here:** `./setup.sh status` shows what's installed and running. `./setup.sh report` (current boot) or `./setup.sh report -1` (previous boot) writes every relevant log into one file under `~/.cache/sunshine-on-demand/`. Set `SUNSHINE_LOG_LEVEL="debug"` (then `./setup.sh install --user`) to also record every request the Moonlight client makes.

With the Claude Code plugin, run `/sunshine-on-demand:troubleshoot` and describe what you saw.

## Symptoms
| Symptom | Check / fix |
|---|---|
| **Wake** does nothing (PC awake) | `journalctl -u sunshine-wol -n 20`. "not the allowed client" → the client's IP changed: give it a DHCP reservation, fix `CLIENT_IP`, reinstall. Nothing logged → the firewall rule for UDP 9 or the socket isn't active (`./setup.sh status`). |
| **Wake** doesn't wake a sleeping/off PC | BIOS settings ([linux.md](linux.md#3-wake-on-lan-in-the-biosuefi)); `nmcli -g 802-3-ethernet.wake-on-lan con show "<conn>"` → `magic`; use Ethernet, not Wi-Fi. |
| After a Wake from **power-off** you get the normal login screen | TV session off? (`TV_SESSION="yes"`.) Otherwise the TV check didn't see the TV: `journalctl -u sunshine-tv-clientcheck -b`. Press **Wake** again at the login screen (fallback trigger). |
| **Every** manual boot lands in the TV session | Your TV/box answers pings in standby (Quick Start+, Instant On, Android TV network standby). Turn that off on the TV, or set `TV_AUTOLOGIN="on-wake"` (two presses). |
| Wake works (the PC starts) but Moonlight never connects / stays "offline" | The TV is probably **also on Wi-Fi**: it sends Wake over the cable (from `CLIENT_IP`), but connects over Wi-Fi from another IP, which the firewall blocks. `./setup.sh report` lists blocked connections to Sunshine's ports by source IP. Turn Wi-Fi off on the TV (LG: Settings → General → Network → Wi-Fi Connection → off). webOS can turn Wi-Fi on by itself while the cable is unplugged. |
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
| Controller lag / drop-outs | See [Controller](#controller) below, and [extras/xbox-controller-bluetooth](../extras/xbox-controller-bluetooth/README.md) for ~1 s Bluetooth dropouts. |

## Lessons learned (things that cost us hours)
- **Moonlight only contacts a PC** when you open its page, press Retry, when the PC announces itself on the network (mDNS), and **for 15 s after Wake**. It does *not* keep polling an offline PC. A cold boot takes longer than 15 s, which is why the TV session uses the TV-ping trigger.
- **Sunshine's prep `undo` steps run bottom-to-top.** Anything that must happen after the resolution is restored has to sit *above* the display step.
- **Steam caches its UI scale** (`AutoScaleFactor`) while the screen is 4K, and only recalculates it on restart. Turning off "Scale text and icons to match monitor settings" avoids it entirely; `sunshine-steam-reset` (restart, deferred while a game runs) is the fallback.
- **A TV with both cable and Wi-Fi connected** answers on both IPs. Moonlight's Wake went out over the cable (allowed), but its connections went over Wi-Fi (blocked). Unplugging the cable for a moment is enough for webOS to join Wi-Fi, and it stays on Wi-Fi after the cable is back.
- **Sunshine stays "active" when it found no display at startup.** Right after resume the GPU's outputs can be missing for a few seconds; Sunshine then logs `Fatal: Unable to find display or encoder` but keeps running, so "already running" doesn't mean "working". The health check restarts it. (A screen that is merely off/DPMS is fine.)
- **Controller input doesn't count as desktop activity**, so without the sleep inhibitor the PC can suspend mid-game.
- **`kwin_wayland --lockscreen` doesn't report the lock to logind**, so `loginctl unlock-session` can't unlock it. The TV session locks through logind instead.
- **Many motherboards report SMBIOS Wake-up Type "Power Switch" for every boot**, Wake-on-LAN included, so the boot reason is unreliable.
- **Flatpak Sunshine runs prep commands inside its sandbox**; they need `flatpak-spawn --host` (the installer does this).
- **sudo needs a real terminal.** Neither Claude nor `!`-prefixed commands can answer the password prompt.
- **Compiled Python files (`__pycache__`) embed absolute paths.** Keep them out of git.

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
- **Occasional ~1 s dropouts** even with antennas (`failed to send FF report` in the kernel log): run [extras/xbox-controller-bluetooth](../extras/xbox-controller-bluetooth/README.md). It sets BlueZ LE parameters (2 s supervision timeout), turns btusb autosuspend off and the unused Wi-Fi radio off, and shows how to read the disconnect reason with `btmon`. The fallbacks are a USB-C cable or the Xbox Wireless Adapter (xone driver, unmaintained since 2026).
- **Wired controller not detected:** front-panel USB-C ports often carry no data. Use a **rear** port and a data cable.
