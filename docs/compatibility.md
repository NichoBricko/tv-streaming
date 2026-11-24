# Compatibility

✅ tested on the [reference setup](reference-setup.md) · 🟡 should work, untested · 🛠 guided/manual steps · ❌ not supported

## Host PC
| Feature | Linux + KDE Plasma 6 | Linux + GNOME | Linux + Sway/Hyprland | Linux + X11 WM | Windows 10/11 | macOS |
|---|---|---|---|---|---|---|
| Automated install (`setup.sh` / Claude plugin) | ✅ | 🟡 | 🟡 | 🟡 | 🛠 [guided](windows.md) | ❌ |
| Sunshine on demand (Wake starts it, idle stop) | ✅ | 🟡 | 🟡 | 🟡 | ❌ (always-on service) | ❌ |
| Wake from sleep | ✅ | 🟡 | 🟡 | 🟡 | 🛠 | ❌ |
| Wake from power-off | ✅ | 🟡 | 🟡 | 🟡 | 🛠 (Fast Startup off) | ❌ |
| One-press cold boot (TV session) | ✅ | ❌ needs KWin | ❌ needs KWin | ❌ needs KWin | ❌ ([alternatives](windows.md#login-after-a-cold-boot)) | ❌ |
| Display switches to TV resolution | ✅ kscreen | 🛠 your command (`gdctl`…) | 🟡 wlr-randr | 🟡 xrandr | 🛠 Sunshine display settings / Apollo | ❌ |
| Unlock for stream / relock after | ✅ | 🟡 (logind) | 🟡 depends on locker | 🟡 depends on locker | ❌ | ❌ |
| Steam window fix after stream | ✅ | 🟡 | 🟡 | 🟡 | not needed | ❌ |
| Firewall limited to the TV | ✅ ufw | 🟡 ufw/firewalld | 🟡 | 🟡 | 🛠 PowerShell | ❌ |

**Login manager** for the TV session's auto-login: Plasma Login Manager ✅ · SDDM 🟡 · others 🛠 (configure auto-login to the `sunshine-tv` session yourself).
**Sunshine package:** native (pacman/AUR/COPR/deb) ✅ · Flatpak 🟡 (prep commands run via `flatpak-spawn --host`; no KMS capture).
**GPU:** AMD (VAAPI) ✅ · Intel (VAAPI) 🟡 · NVIDIA (NVENC) 🟡.
**Network:** the PC on **Ethernet** is required for Wake-on-LAN.

## TV / client
| Client | Moonlight | Install | Claude automates it | One-press cold boot¹ | Controller on the TV |
|---|---|---|---|---|---|
| LG webOS 3+ | Moonlight TV | sideload (Developer Mode) | ✅ `ares` | ✅ (drops off network in standby) | works, but laggy in our test |
| Android TV / Google TV (Sony, TCL, Philips, …) | official | Play Store / APK | 🟡 `adb` | 🟡 check standby | 🟡 usually good |
| Nvidia Shield / Google TV Streamer | official | Play Store | 🟡 `adb` | 🟡 check standby | 🟡 good |
| Samsung Tizen 5.5+ (2020+) | community port | sideload (Developer Mode) | 🛠 guided | 🟡 check "Instant On" | 🟡 |
| Apple TV 4K | official | App Store | ❌ manual | 🟡 check standby | 🟡 good |
| Fire TV on Fire OS | official (Android) | Appstore / APK | 🟡 `adb` | 🟡 check standby | 🟡 |
| Fire TV on Vega OS, Hisense VIDAA, Roku | ❌ no client | - | - | - | - |

¹ One press works when the client is **not reachable by ping in standby** ([standby check](tv-clients.md#standby-check)). Otherwise use `TV_AUTOLOGIN="on-wake"` (two presses).
