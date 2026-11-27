# Manual install on Linux

The [Claude Code plugin](../README.md#install-with-claude-code-recommended) does all of this for you, interactively. This page is the manual route.

## 1. Install Sunshine
| Distro | Install | Service name (detected automatically) |
|---|---|---|
| **Arch / CachyOS / Manjaro** | CachyOS repo: `sudo pacman -S sunshine` · AUR: `sunshine` / `sunshine-bin` | `app-dev.lizardbyte.app.Sunshine.service` (newer) or `sunshine.service` |
| **Fedora / Nobara** | LizardByte's COPR (`sudo dnf copr enable lizardbyte/stable`, then install the Sunshine package; see Sunshine's [Getting Started](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html)) | as above |
| **Debian / Ubuntu / Mint / Pop!_OS** | `.deb` from [Sunshine releases](https://github.com/LizardByte/Sunshine/releases) → `sudo apt install ./sunshine-*.deb` | `sunshine.service` (some builds ship no unit; see Sunshine docs) |
| **Bazzite / immutable / any distro** | Flatpak: `flatpak install flathub dev.lizardbyte.app.Sunshine` | `app-dev.lizardbyte.app.Sunshine.service` |

Check that it runs: `systemctl --user start app-dev.lizardbyte.app.Sunshine.service || systemctl --user start sunshine.service`.

## 2. Configure and install
```bash
git clone https://github.com/NichoBricko/tv-streaming ~/.local/share/sunshine-on-demand
cd ~/.local/share/sunshine-on-demand
./setup.sh configure                       # --client-ip <TV IP> optional (needed for FIREWALL_SCOPE="client")
$EDITOR config.env                         # review; TV_SESSION="yes" for cold-boot streaming
./setup.sh install --dry-run               # preview
./setup.sh install --user                  # no sudo
./setup.sh install --system                # asks for sudo: run in a normal terminal
```
Changed `config.env` later? Run `./setup.sh install` again; it's idempotent. To use several configs: `SOD_SETUP_CONFIG=other.env ./setup.sh install`.

## 3. Wake-on-LAN in the BIOS/UEFI
The installer sets `wake-on-lan magic` on your NetworkManager connection. **You must also enable it in the firmware:**

| Board vendor | Setting (names vary by model) |
|---|---|
| **ASUS** | Advanced → APM Configuration → **Power On By PCI-E** = Enabled, **ErP Ready** = Disabled |
| **MSI** | Settings → Advanced → Wake Up Event Setup → **Resume By PCI-E Device** = Enabled; **ErP Ready** = Disabled |
| **Gigabyte** | Settings → Platform Power → **Wake on LAN** = Enabled; **ErP** = Disabled |
| **ASRock** | Advanced → ACPI Configuration → **PCIE Devices Power On** = Enabled; **Deep Sleep** = Disabled |
| Laptops / prebuilts | often "Wake on LAN" under Power; some don't support it from sleep |

No NetworkManager? Use systemd-networkd (`[Link] WakeOnLan=magic` in a `.link` file) or `ethtool -s <iface> wol g` at boot, and set `NM_CONNECTION=""`. Use **Ethernet**: Wake-on-LAN over Wi-Fi rarely works.

## 4. Pair Moonlight
1. Run `sunshine-on-demand start`.
2. Open <https://localhost:47990> and create the Sunshine login.
3. In Moonlight on the TV, select the PC and enter the PIN it shows under **PIN** in Sunshine's web UI.

Client setup per TV: [tv-clients.md](tv-clients.md).

## 5. Test
1. **Wake while awake:** run `sunshine-on-demand stop`, then press **Wake** in Moonlight → the PC is online within 10–20 s.
2. **Wake from sleep:** put the PC to sleep, then press Wake.
3. **Wake from power-off** (with `TV_SESSION=yes`): shut down, then press Wake once and wait.
4. `./setup.sh status` shows every part; `./setup.sh report` collects the logs.

## Desktop support
| Desktop | Display switching (`DISPLAY_BACKEND`) | Unlock for stream | TV session | Status |
|---|---|---|---|---|
| **KDE Plasma 6** (Wayland/X11) | `kscreen` - detected | ✅ | ✅ | **Fully tested** |
| **GNOME** (Wayland) | `custom`: your command in `DISPLAY_SET_CMD`/`DISPLAY_RESTORE_CMD` using `{W}`, `{H}`, `{R}`. Newer Mutter ships `gdctl`; older: see Sunshine's [App Examples](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2app__examples.html). Or `none`. | ✅ (logind) | needs KWin | Untested |
| **Sway / Hyprland / other wlroots** | `wlr-randr` - detected | depends on your locker (needs logind support) | needs KWin | Untested |
| **X11 (any WM)** | `xrandr` - detected | depends on locker | needs KWin | Untested |
| Headless / dedicated TV output | `none` | - | - | - |

**Capture:** a native install can use **KMS capture** (fastest) after `./setup.sh setcap`. **Repeat that after every Sunshine update.** Flatpak can't use setcap; use portal capture there.

**Encoder:** automatic. Force it only if needed: `vaapi` (AMD/Intel), `nvenc` (NVIDIA). With an iGPU + dGPU, set `SUNSHINE_ADAPTER` to the dGPU's render node (`ls -l /dev/dri/by-path`).

If your monitor doesn't accept the stream resolution, set `STREAM_MODE` to a mode it supports (the TV upscales), or use `DISPLAY_BACKEND="none"`.

## Everyday use and uninstall
- **Play:** on the TV, open Moonlight → your PC → **Wake** if it's offline → **Steam Big Picture**. Quit the stream when done.
- **By hand:** use the app menu → **Sunshine: start/stop streaming host**, or `sunshine-on-demand start|stop|status`.
- **Uninstall:** `./setup.sh uninstall --dry-run`, then `./setup.sh uninstall`. Sunshine's own config is kept, with backups.
