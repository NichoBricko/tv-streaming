# sunshine-on-demand

**Stream your Linux gaming PC to the TV with [Sunshine](https://github.com/LizardByte/Sunshine) + [Moonlight](https://moonlight-stream.org), with Sunshine only running when you actually play.**

Pick up the TV remote, open Moonlight, press **Wake**. The PC wakes up (or just starts Sunshine if it's already on), unlocks for the stream, switches its display to 4K and opens Steam Big Picture. When you quit, everything goes back: normal resolution, Steam resized, screen locked again if it was locked, and Sunshine shuts itself off 10 minutes later.

## What it does
| Feature | How |
|---|---|
| **Sunshine on demand** | Not started at login. Started by Moonlight's **Wake PC** button (a Wake-on-LAN listener on UDP 9), after resume from sleep, or from the app menu. |
| **Wake from sleep** | Moonlight's Wake-on-LAN packet wakes the PC; a resume hook starts Sunshine |
| **Auto stop** | Sunshine stops after `IDLE_LIMIT` (default 10 min) without a connected stream |
| **Unlock for the stream** | If the PC is locked (e.g. it was asleep), the session is unlocked when a **paired** client starts a stream, and locked again afterwards. If you were already logged in, it is left alone. |
| **Display switching** | The PC's display switches to the client's resolution/fps and back to the previous mode afterwards (KDE, X11, wlroots; GNOME via your own command) |
| **Steam fix-up** | Steam is restarted minimized after the stream, so it doesn't keep its 4K layout on a 1080p monitor. Skipped while a game is still running. |
| **No sleep mid-game** | A `systemd-inhibit` lock is held while streaming (controller input doesn't count as desktop activity) |
| **Locked down** | Only one app (Steam Big Picture) is offered; keyboard/mouse (optionally also controller) input from the TV is blocked; stream encryption required; web UI local-only; firewall open **only** to the TV's IP |

Optional extras: [Moonlight on LG webOS TVs](extras/lg-webos-devmode/README.md) (with automatic Developer Mode renewal) and [RDR2 (Epic) via Heroic fixes](extras/rdr2-epic-heroic/README.md).

```
 TV / streaming box                         Linux PC
 ┌──────────────┐  "Wake PC" (UDP 9)   ┌─────────────────────────────────────────┐
 │  Moonlight   │ ───────────────────► │ sunshine-wol.socket → start Sunshine    │
 │              │                      │ (asleep? NIC wakes PC → sunshine-resume) │
 │              │ ◄══ 4K60 HEVC ══════ │ Sunshine ─ prep: inhibit sleep, unlock,  │
 │              │     (encrypted)      │          display → 4K, Big Picture       │
 └──────────────┘                      │ stream ends → restore, Steam reset, lock │
                                       │ idle 10 min → sunshine-idle-stop         │
                                       └─────────────────────────────────────────┘
```

## Requirements
- Linux with **systemd** and a graphical session; the installer targets **KDE Plasma** best (fully tested), with GNOME, wlroots compositors and X11 supported (see [Desktop support](#desktop-support)).
- **Sunshine** installed (see below) and a **Moonlight** client on the TV ([which client for your TV](docs/tv-clients.md)).
- **Wired Ethernet** on the PC for Wake-on-LAN (Wi-Fi WoL rarely works), ideally on the TV too.
- Python 3, `loginctl`, `logger`, NetworkManager (for automatic WoL setup; others: see below).

## Quick start
```bash
# 1. Install Sunshine for your distro (table below) and check it runs:
systemctl --user start app-dev.lizardbyte.app.Sunshine.service || systemctl --user start sunshine.service

# 2. Get this repo
git clone <this repo> ~/sunshine-on-demand && cd ~/sunshine-on-demand

# 3. Detect your PC and write config.env (give the TV/box a fixed IP in your router first)
./setup.sh configure --client-ip 192.168.1.50
$EDITOR config.env          # review: display output, controller, app, firewall ...

# 4. Preview, then install (the system part asks for sudo - run in a normal terminal)
./setup.sh install --dry-run
./setup.sh install

# 5. Enable Wake-on-LAN in your BIOS/UEFI (table below), then pair Moonlight:
sunshine-on-demand start    # open https://localhost:47990, create a login, enter the PIN Moonlight shows
./setup.sh status
```
Changed `config.env` later? Run `./setup.sh install` again (it's idempotent). Several TVs/configs: `SOD_SETUP_CONFIG=other.env ./setup.sh install`.

Then test: quit Moonlight, wait until Sunshine stops (or `sunshine-on-demand stop`), press **Wake** in Moonlight → the PC shows up within ~10–20 s. Put the PC to sleep and try again.

## Installing Sunshine
| Distro | Install | Service name (detected automatically) |
|---|---|---|
| **Arch / CachyOS / Manjaro** | CachyOS repo: `sudo pacman -S sunshine` · AUR: `sunshine` / `sunshine-bin` | `app-dev.lizardbyte.app.Sunshine.service` (newer) or `sunshine.service` |
| **Fedora / Nobara** | LizardByte's COPR (`sudo dnf copr enable lizardbyte/stable`, then install the Sunshine package - see Sunshine's [Getting Started](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html)) | as above |
| **Debian / Ubuntu / Mint / Pop!_OS** | `.deb` from [Sunshine releases](https://github.com/LizardByte/Sunshine/releases) → `sudo apt install ./sunshine-*.deb` | `sunshine.service` (some builds ship no unit - see Sunshine docs) |
| **Bazzite / immutable / any distro** | Flatpak: `flatpak install flathub dev.lizardbyte.app.Sunshine` (Bazzite also offers Sunshine itself - see the Bazzite docs) | `app-dev.lizardbyte.app.Sunshine.service` |

**Flatpak Sunshine:** detected by `configure` (`SUNSHINE_FLATPAK=yes`); the installer then prefixes every prep command with `flatpak-spawn --host`, because Flatpak Sunshine otherwise runs them inside its sandbox where `systemctl`, `loginctl` and the helpers don't exist.

**Capture:** a native install can use **KMS capture** (fastest; needed on many Wayland setups) after
`./setup.sh setcap` (= `sudo setcap cap_sys_admin,cap_sys_nice+p $(readlink -f $(which sunshine))`). **Repeat after every Sunshine update.** Flatpak can't use setcap; use portal capture there.

**Encoder:** Sunshine picks one automatically. Set `SUNSHINE_ENCODER` only to force it: `vaapi` (AMD, Intel), `nvenc` (NVIDIA with the proprietary driver). On PCs with an iGPU + dGPU set `SUNSHINE_ADAPTER` to the dGPU's render node (`ls -l /dev/dri/by-path`).

## Desktop support
| Desktop | Display switching (`DISPLAY_BACKEND`) | Unlock for stream | Status |
|---|---|---|---|
| **KDE Plasma 6** (Wayland/X11) | `kscreen` (kscreen-doctor) - detected | ✅ | **Fully tested** |
| **GNOME** (Wayland) | `custom`: put your command in `DISPLAY_SET_CMD`/`DISPLAY_RESTORE_CMD` using `{W}`, `{H}`, `{R}`. Newer Mutter ships `gdctl` (check `gdctl set --help`); for older versions Sunshine's [App Examples](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2app__examples.html) list GNOME tools (displayconfig-mutter, gnome-randr). Or `none`. | ✅ (logind) | Untested |
| **Sway / Hyprland / other wlroots** | `wlr-randr` - detected | depends on your locker (needs logind support, e.g. swaylock via swayidle `unlock` hook) | Untested |
| **X11 (any WM)** | `xrandr` - detected | depends on locker | Untested |
| Headless / dedicated TV output | `none` | - | - |

If your monitor doesn't accept the stream resolution, set `STREAM_MODE` to a mode it does support (the TV upscales), or `DISPLAY_BACKEND="none"` and let Moonlight scale.

## Wake-on-LAN
The installer sets `wake-on-lan magic` on your NetworkManager connection. **You must also enable it in the BIOS/UEFI**:

| Board vendor | Setting (names vary by model) |
|---|---|
| **ASUS** | Advanced → APM Configuration → **Power On By PCI-E** = Enabled, **ErP Ready** = Disabled |
| **MSI** | Settings → Advanced → Wake Up Event Setup → **Resume By PCI-E Device** = Enabled; **ErP Ready** = Disabled |
| **Gigabyte** | Settings → Platform Power → **Wake on LAN** = Enabled; **ErP** = Disabled |
| **ASRock** | Advanced → ACPI Configuration → **PCIE Devices Power On** = Enabled; **Deep Sleep** = Disabled |
| Laptops / prebuilts | often "Wake on LAN" under Power; some don't support it from sleep |

No NetworkManager? Use systemd-networkd (`[Link] WakeOnLan=magic` in a `.link` file) or `ethtool -s <iface> wol g` at boot, and set `NM_CONNECTION=""`.

Waking **from sleep** works from suspend (S3/s2idle with a capable NIC); waking from **power-off** (S5) also works on most desktops with the BIOS setting, but then you land at the display manager login - this project doesn't auto-login (enable auto-login in your DM if you want that).

## Everyday use
1. TV: open **Moonlight** → your PC. Offline? Choose **Wake** and wait ~10–20 s.
2. Start **Steam Big Picture**, play.
3. Quit the stream in Moonlight. Sunshine stops by itself after `IDLE_LIMIT`.

By hand: app menu → **Sunshine: start/stop streaming host**, or `sunshine-on-demand start|stop|status` (also handy as KDE Connect run commands from your phone).

## What gets installed
| Component | Scope | What it does |
|---|---|---|
| `sunshine-wol.socket` + `sunshine-wol.service` | system | Listens on UDP 9; `sunshine-wol-handler.py` (runs as you) starts Sunshine **only** for a magic packet with your MAC sent **from `CLIENT_IP`**. Logs: `journalctl -u sunshine-wol` |
| `sunshine-resume.service` | system | Starts Sunshine after every resume (the idle timer stops it again if nobody connects) |
| `/etc/sunshine-on-demand.env` | system | `WOL_MAC`, `CLIENT_IP`, `SUNSHINE_UNIT` for the system units |
| `sunshine-idle-stop.timer` | user | Every minute: stops Sunshine after `IDLE_LIMIT` without a stream (reads `CLIENT CONNECTED/DISCONNECTED` in Sunshine's log) |
| `sunshine-stream-inhibit.service` | user | `systemd-inhibit` against sleep/idle while streaming |
| `~/.local/bin/sunshine-*` | user | Helpers called by Sunshine's prep commands (`display-mode`, `session-lock`, `steam-reset`) + `sunshine-on-demand start\|stop\|status\|cleanup` (symlinks into the repo) |
| `~/.local/share/applications/sunshine-{start,stop}.desktop` | user | Menu entries (written with absolute paths) |
| `~/.config/sunshine-on-demand/config.env` | user | Copy of your `config.env` read by the helpers |
| `~/.config/sunshine/sunshine.conf`, `apps.json` | user | **Merged**, not replaced (backups `*.bak-<date>`): input blocking, encryption, web UI origin, encoder/capture; the app with its prep commands; Desktop app removed |
| Firewall rules | system | ufw / firewalld: TCP 47984, 47989, 48010 + UDP 47998–48000 (+ UDP 9) **from `CLIENT_IP` only**; web UI port 47990 is not opened |

Prep commands of the app (Sunshine runs **do** top→bottom at stream start, **undo** bottom→top at the end):

| # | do | undo |
|---|---|---|
| 1 | inhibit sleep | release |
| 2 | `sunshine-session-lock unlock` (only if locked) | `relock` (only if step 2 unlocked) |
| 3 | - | `sunshine-steam-reset` (close Big Picture, restart Steam minimized) |
| 4 | `sunshine-display-mode stream` | `restore` (runs first) |

Every helper logs to the journal: `journalctl --user -t sunshine-display-mode -t sunshine-session-lock -t sunshine-steam-reset`.

## Security model
- Sunshine only runs when needed; when it's stopped nothing can connect.
- Only the paired client (PIN pairing → client certificate) can stream; the firewall only lets `CLIENT_IP` reach Sunshine and the Wake listener.
- A Wake packet only **starts** Sunshine - it never unlocks anything. The session is unlocked only when a paired client starts an **encrypted** stream, and locked again afterwards.
- With `BLOCK_CLIENT_*`, the TV can't type, move the mouse or (optionally) send controller input; with `REMOVE_DESKTOP_APP` it can't show your desktop - only Big Picture.
- Accepted risks: while you stream, the PC's own monitor shows the unlocked session. If Moonlight **disconnects without quitting the app** (back button, network drop), Sunshine keeps the app running so you can resume - the session stays unlocked and in the stream resolution until you reconnect and quit, or until `IDLE_LIMIT` passes; then `sunshine-idle-stop` stops Sunshine and `sunshine-on-demand cleanup` restores the display, re-locks and releases the inhibitor. **Quit** the stream from Moonlight's menu to undo everything immediately; lower `IDLE_LIMIT` to shorten the window.
- On the TV side: disable automatic content recognition (LG Live Plus, Samsung Viewing Information Services, …).

## Troubleshooting
| Symptom | Check |
|---|---|
| **Wake** does nothing (PC awake) | `journalctl -u sunshine-wol -n 20`: packet "accepted"? "not the allowed client" → the TV's IP changed (fix `CLIENT_IP` + reinstall, or DHCP reservation). Nothing logged → firewall rule for UDP 9 / socket not active (`./setup.sh status`). |
| **Wake** doesn't wake a sleeping PC | BIOS settings above; `nmcli -g 802-3-ethernet.wake-on-lan con show "<conn>"` → `magic`; use Ethernet |
| Stream shows the **lock screen** | `journalctl --user -t sunshine-session-lock`; your locker must honour `loginctl unlock-session` (KDE/GNOME do) |
| Black screen / no capture | `./setup.sh setcap` (after every Sunshine update) or set `SUNSHINE_CAPTURE` (portal/wlr/x11) |
| Display didn't switch / restore | `journalctl --user -t sunshine-display-mode`; `sunshine-display-mode current`; check `DISPLAY_OUTPUT` and that the mode exists |
| Steam window wrong size after a stream | `journalctl --user -t sunshine-steam-reset` - skipped because a game was still running? Run `sunshine-steam-reset` by hand |
| PC still unlocked / in 4K after leaving the stream | You disconnected without quitting the app (see Security model). Quit from Moonlight, or run `sunshine-on-demand stop` (stops Sunshine + cleanup) |
| Sunshine stopped during a stream | `journalctl --user -u sunshine-idle-stop` (it only stops after a disconnect + `IDLE_LIMIT`) |
| Blocky picture | Moonlight bitrate too low (default can be ~10 Mbps) - set 50–80 Mbps (≤ 65 on 100 Mb/s TVs) |
| Controller lag / drop-outs | See [controller notes](docs/tv-clients.md#controller-tv-or-pc) - antennas, firmware, pair to the PC |

## Uninstall
```bash
./setup.sh uninstall --dry-run   # preview
./setup.sh uninstall             # units, links, env file, firewall rules, NM WoL setting
```
Sunshine's own config is left in place (with backups). Extras are removed per their READMEs.

## Repository layout
```
setup.sh                  installer: configure | install | setcap | extra | status | uninstall
config.env.example        every option, documented (your config.env is gitignored)
bin/                      helpers linked into ~/.local/bin
lib/                      Wake-on-LAN handler (installed to /usr/local/lib/sunshine-on-demand)
systemd/user/             user units      systemd/system/   system units (*.in = templated)
share/applications/       "Sunshine: start/stop" menu entries
extras/                   lg-webos-devmode, rdr2-epic-heroic
docs/                     tv-clients.md, reference-setup.md
```

## Reference setup
Built and tested on CachyOS + KDE Plasma 6 (Wayland), AMD RX 9070 XT, LG webOS 22 TV - see [docs/reference-setup.md](docs/reference-setup.md) for the hardware, what was verified, and lessons learned.

## Credits
[Sunshine](https://github.com/LizardByte/Sunshine) (LizardByte), [Moonlight](https://moonlight-stream.org), [Moonlight TV](https://github.com/mariotaku/moonlight-tv) (mariotaku), [Heroic Games Launcher](https://heroicgameslauncher.com).
