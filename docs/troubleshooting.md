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
| Moonlight stays "offline" although Sunshine runs | Moonlight's Wake only waits ~15 s. Press **Retry**, or go back and select the PC again. |
| Stream shows the **lock screen** | `journalctl --user -t sunshine-session-lock`. Your locker must honour `loginctl unlock-session` (KDE/GNOME do). |
| Black screen / no picture | `./setup.sh setcap` (after **every** Sunshine update), or set `SUNSHINE_CAPTURE` (portal/wlr/x11). |
| Blocky picture | Moonlight's bitrate is too low; the default can be ~10 Mbps. Use 50–80 Mbps (≤ 65 on TVs with 100 Mb/s Ethernet). |
| Display didn't switch / restore | `journalctl --user -t sunshine-display-mode`; `sunshine-display-mode current`; check `DISPLAY_OUTPUT` and that the mode exists. |
| Steam window wrong size after a stream | `journalctl --user -t sunshine-steam-reset`. Was a game still running? (Then the restart is skipped.) Run `sunshine-steam-reset` by hand. |
| PC still unlocked / in 4K after leaving the stream | You disconnected without **quitting** the app. Quit from Moonlight's menu, or run `sunshine-on-demand stop`. |
| Sunshine stopped mid-session | `journalctl --user -u sunshine-idle-stop`. It only stops after a disconnect + `IDLE_LIMIT`. |
| Controller lag / drop-outs | See [Controller](#controller) below. |

## Lessons learned (things that cost us hours)
- **Moonlight only contacts a PC** when you open its page, press Retry, when the PC announces itself on the network (mDNS), and **for 15 s after Wake**. It does *not* keep polling an offline PC. A cold boot takes longer than 15 s, which is why the TV session uses the TV-ping trigger.
- **Sunshine's prep `undo` steps run bottom-to-top.** Anything that must happen after the resolution is restored has to sit *above* the display step.
- **Steam caches its UI scale** (`AutoScaleFactor`) while the screen is 4K, and only recalculates it on restart; hence `sunshine-steam-reset`.
- **Controller input doesn't count as desktop activity**, so without the sleep inhibitor the PC can suspend mid-game.
- **`kwin_wayland --lockscreen` doesn't report the lock to logind**, so `loginctl unlock-session` can't unlock it. The TV session locks through logind instead.
- **Many motherboards report SMBIOS Wake-up Type "Power Switch" for every boot**, Wake-on-LAN included, so the boot reason is unreliable.
- **Flatpak Sunshine runs prep commands inside its sandbox**; they need `flatpak-spawn --host` (the installer does this).
- **sudo needs a real terminal.** Neither Claude nor `!`-prefixed commands can answer the password prompt.
- **Compiled Python files (`__pycache__`) embed absolute paths.** Keep them out of git.

## Controller
- **Pair it with the PC, if possible.** That gives the lowest latency, and the TV can then be display-only (`BLOCK_CLIENT_CONTROLLER="yes"`). The LG TV's Bluetooth added very noticeable lag.
- **Xbox controller won't pair over Bluetooth on Linux:** update its firmware first (Xbox Accessories app on Windows/Xbox; 5.09 failed, 5.17 worked). If the desktop pairing wizard fails, use `bluetoothctl`: `agent NoInputNoOutput`, `default-agent`, `scan le`, `pair <MAC>`, `trust <MAC>`, `connect <MAC>`.
- **Frequent disconnects:** attach the motherboard's **Wi-Fi/Bluetooth antennas**. Without them the reference PC got a disconnect every 8–30 s.
- **Wired controller not detected:** front-panel USB-C ports often carry no data. Use a **rear** port and a data cable.
