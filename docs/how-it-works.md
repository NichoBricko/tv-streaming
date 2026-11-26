# How it works

Technical reference for the Linux implementation. For installing, see the [README](../README.md); for problems, see [troubleshooting.md](troubleshooting.md).

## Features
| Feature | How |
|---|---|
| **Sunshine on demand** | Not started at login. Started by Moonlight's **Wake PC** button (a Wake-on-LAN listener on UDP 9), after resume from sleep, by the TV session, or from the app menu. |
| **Wake from sleep** | Moonlight's Wake-on-LAN packet wakes the PC; `sunshine-resume.service` starts Sunshine. |
| **Wake from power-off** | The PC boots; if the TV answers pings (it's on, so someone pressed Wake), the PC logs into the locked **TV session** by itself. See [TV session](#tv-session-cold-boot). |
| **Auto stop** | Sunshine stops after `IDLE_LIMIT` (default 10 min) without a connected stream. |
| **Unlock for the stream** | If the session is locked, it's unlocked when a **paired** client starts a stream, and locked again afterwards. If you were already logged in, it's left alone. |
| **Display switching** | The PC's display switches to the client's resolution/fps, then back to the previous mode (KDE, X11, wlroots; GNOME via your own command). |
| **Steam fix-up** | Steam is restarted minimized after the stream, so it doesn't keep its 4K layout on a 1080p monitor. Skipped while a game is still running. |
| **No sleep mid-game** | A `systemd-inhibit` lock is held while streaming (controller input doesn't count as desktop activity). |
| **Stream smoothness** (optional) | `SUNSHINE_STRICT_RC` limits keyframe size; `STREAM_PACING_MBIT` paces only Sunshine's video (UDP 47998) via `sunshine-stream-pacing.service`, so 100 Mb/s TVs don't overflow on keyframes. |
| **Locked down** | Only one app (Steam Big Picture); keyboard/mouse (optionally controller) input from the TV blocked; stream encryption required; web UI local-only; firewall open **only** to the client's IP. |

## What gets installed
| Component | Scope | What it does |
|---|---|---|
| `sunshine-wol.socket` + `sunshine-wol.service` | system | Listens on UDP 9. `sunshine-wol-handler.py` (runs as you) starts Sunshine **only** for a magic packet with your MAC sent **from `CLIENT_IP`**. If nobody is logged in yet, it remembers the wake (`/run/sunshine-on-demand/wake-pending`). |
| `sunshine-resume.service` | system | Starts Sunshine after every resume (the idle timer stops it again if nobody connects). |
| `sunshine-login.service` | user | At login: starts Sunshine if a Wake arrived while nobody was logged in. |
| `sunshine-tv-autologin.service`, `sunshine-tv-clientcheck.service`, `sunshine-tv-wake.path/.service`, `/usr/local/lib/sunshine-on-demand/sunshine-tv-*`, `/usr/share/wayland-sessions/sunshine-tv.desktop` | system | Only with `TV_SESSION=yes`: the TV session and its triggers. They edit `/etc/plasmalogin.conf` `[Autologin]` (original kept as `.pre-sunshine-on-demand`) or write an SDDM drop-in. |
| `/etc/sunshine-on-demand.env` | system | `WOL_MAC`, `CLIENT_IP`, `SUNSHINE_UNIT`, `SOD_USER`, `TV_*` for the system units. |
| `sunshine-idle-stop.timer` | user | Every minute: stops Sunshine after `IDLE_LIMIT` without a stream (reads `CLIENT CONNECTED/DISCONNECTED` in Sunshine's log). In the TV session it then suspends the PC. |
| `sunshine-stream-inhibit.service` | user | `systemd-inhibit` against sleep/idle while streaming. |
| `~/.local/bin/sunshine-*` | user | Helpers called by Sunshine's prep commands (`display-mode`, `session-lock`, `steam-reset`, `open-app`) + `sunshine-on-demand start\|stop\|status\|cleanup\|login`. |
| `~/.local/share/applications/sunshine-{start,stop}.desktop` | user | Menu entries. |
| `~/.config/sunshine-on-demand/config.env` | user | Copy of your `config.env`, read by the helpers. |
| `~/.config/sunshine/sunshine.conf`, `apps.json` | user | **Merged**, not replaced (backups `*.bak-<date>` when something changed). |
| Firewall rules | system | ufw / firewalld: TCP 47984, 47989, 48010 + UDP 47998–48000 (+ UDP 9) **from `CLIENT_IP` only**. The web UI port 47990 is not opened. |

## The streamed app
Sunshine runs the **do** steps top→bottom when a stream starts, and the **undo** steps bottom→top when it ends:

| # | do | undo |
|---|---|---|
| 1 | inhibit sleep | release |
| 2 | `sunshine-session-lock unlock` (only if locked; always in the TV session) | `relock` (only if step 2 unlocked) |
| 3 | - | `sunshine-steam-reset` (close Big Picture, restart Steam minimized; nothing in the TV session) |
| 4 | `sunshine-display-mode stream` | `restore` (runs first) |

The app's detached command is `sunshine-open-app`. It opens `APP_OPEN_CMD` (Steam Big Picture). Inside the TV session it only asks the session to start Steam.

With a **Flatpak** Sunshine, every command is prefixed with `flatpak-spawn --host`; otherwise Sunshine would run them inside its sandbox. Every helper logs to the journal (`journalctl --user -t sunshine-<name>`).

## TV session (cold boot)
Waking the PC from power-off ends at the login screen, where no user session exists, so Sunshine can't run. With `TV_SESSION=yes`, the PC logs itself into a minimal Wayland session called "Steam TV (Sunshine streaming)":

- **KWin + nothing else.** No Plasma shell, no file manager, no autostart apps.
- **Locked through logind** as the very first step (`loginctl lock-session`, waiting until `LockedHint=yes`), before anything is started. If the lock can't be confirmed, the session ends. (KWin's own `--lockscreen` isn't used: it doesn't report the lock to logind, so a stream couldn't unlock it.)
- **Sunshine starts; Steam waits.** Big Picture is only launched when a stream asks for it, so the PC makes no noise at boot.
- **A paired stream unlocks it** and it relocks afterwards. Idle for `IDLE_LIMIT` → the PC **suspends** (`TV_SESSION_IDLE_ACTION`), and the next Wake resumes straight into the locked session.
- **Someone at the PC** who unlocks it with the password ends it and lands at the normal login screen. **Quitting Steam** also ends it. Your normal desktop login always needs your password.

How the PC decides to enter it (`TV_AUTOLOGIN="auto"` uses all three; each does a **one-time** auto-login: set auto-login → restart the login screen while nobody is logged in → remove the auto-login 20 s later, serialized by a lock):

1. **The TV is on** (`sunshine-tv-clientcheck.service`): right after boot, alongside the login screen (it doesn't delay it), the PC pings `CLIENT_IP` for up to `TV_CLIENT_CHECK_SECONDS`. If the TV answers, someone pressed Wake. This gives **one press**, with the session ready ~13 s after power-on on the reference PC. It needs a TV that drops off the network in standby; check with `ping <TV IP>` while it's off.
2. **A Wake at the login screen** (`sunshine-tv-wake.path`): the fallback. Press Wake again once the PC sits at the login screen.
3. **Boot reason** (`sunshine-tv-autologin.service`): the SMBIOS Wake-up Type `LAN Remote` / `PCI PME#` (`TV_WAKE_TYPES`). Many boards always report "Power Switch", so this is a bonus only.

Limits:
- Needs **KWin**.
- Auto-login works with **Plasma Login Manager or SDDM** (others: set it up yourself).
- It runs as **your user**: it restricts what's on screen, not what your user may do (Steam's browser still works).
- **KWallet** isn't unlocked in it.
- An encrypted disk needs its password at boot anyway.

## Security model
- **Sunshine only runs when needed.** When it's stopped, nothing can connect.
- **Only the paired client can stream** (PIN pairing → client certificate), and the firewall only lets `CLIENT_IP` reach Sunshine and the Wake listener.
- **A Wake packet never unlocks anything.** It only starts Sunshine (or the locked TV session). The session is unlocked only when a paired client starts an **encrypted** stream, and is locked again afterwards.
- **The TV can't take over the PC.** With `BLOCK_CLIENT_*`, it can't type, move the mouse or (optionally) send controller input. With `REMOVE_DESKTOP_APP`, it can't show your desktop, only Big Picture.
- **Accepted risks:**
  - While you stream, the PC's own monitor shows the unlocked session.
  - If Moonlight disconnects **without quitting the app**, the session stays unlocked until you reconnect and quit, or until `IDLE_LIMIT` passes. Then `sunshine-idle-stop` stops Sunshine, and `sunshine-on-demand cleanup` restores the display, relocks and releases the inhibitor.
- **On the TV:** disable automatic content recognition (LG Live Plus, Samsung Viewing Information Services, …).

## Repository layout
```
setup.sh                  installer: configure | install | setcap | extra | status | report | uninstall
config.env.example        every option, documented (your config.env is gitignored)
bin/                      helpers linked into ~/.local/bin
lib/                      Wake-on-LAN handler (installed to /usr/local/lib/sunshine-on-demand)
systemd/user/  systemd/system/   units (*.in = templated at install)
tv-session/               the TV session and its auto-login triggers
share/applications/       "Sunshine: start/stop" menu entries
extras/                   lg-webos-devmode, rdr2-epic-heroic
skills/  .claude-plugin/  the Claude Code plugin
docs/                     these documents
```
