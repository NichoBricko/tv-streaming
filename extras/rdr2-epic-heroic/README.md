# Red Dead Redemption 2 (Epic Games) through Heroic on Linux

Fixes needed to get the **Epic** version of RDR2 running through **Heroic Games Launcher** with Proton. They should carry over to other Rockstar titles bought on Epic (GTA V and others). Tested with Heroic 2.22, legendary 0.21, Proton-CachyOS 11 and GE-Proton 11.

| Symptom | Cause | Fix |
|---|---|---|
| Rockstar Launcher: *"Steam failed to initialize"*, exits with code 1 | umu passes `GAMEID=umu-1174180`, i.e. RDR2's **Steam** app ID, so the launcher thinks it's the Steam copy | Heroic → game → Settings → **Legacy** tab → **Disable umu**. A `GAMEID` environment variable does **not** work, because Heroic overrides it. |
| Heroic runs `Launcher.exe` directly; `title.rgl` missing | An "alternative executable" points at the Rockstar Launcher | Clear **Alternative EXE / target executable**, so `PlayRDR2.exe` is started |
| `PlayRDR2.exe` crashes: *unimplemented function ucrtbase.dll._strerror_s* | `PlayRDR2.exe` fails to format a log line containing a **non-ASCII Epic display name** (e.g. `ǫ`), then crashes in Wine's `_strerror_s` stub | Change your Epic display name to plain ASCII, then log out and back in to Epic in Heroic. (Or edit `displayName` in `~/.config/heroic/legendaryConfig/legendary/user.json`, after a backup.) |
| `vcrun2022` install fails (DNS timeouts inside the runtime) | Downloads time out inside the Steam runtime container | Download `https://aka.ms/vs/17/release/vc_redist.x86.exe` and `vc_redist.x64.exe` yourself, verify the sha256 against winetricks, and put them in `~/.cache/winetricks/vcrun2022/` |
| Rockstar Launcher shows **"Buy now"** for a game you own | It only grants Epic ownership when `EpicGamesLauncher.exe` is the **parent process**. Heroic sets `LEGENDARY_WRAPPER_EXE` for this, but the bundled legendary 0.21 **ignores it**. | Use `rdr2-fake-egl-wrapper.sh` (below) |
| Story Mode loads forever (one CPU thread at 100%, no disk I/O) | Vulkan renderer hang under Proton | Set the graphics API to **DX12**: `<API>kSettingAPI_DX12</API>` in `<prefix>/drive_c/users/steamuser/Documents/Rockstar Games/Red Dead Redemption 2/Settings/system.xml` |

## The wrapper
`rdr2-fake-egl-wrapper.sh` rewrites Proton's launch command from

`proton waitforexitandrun /path/PlayRDR2.exe <args>`

to

`proton waitforexitandrun C:\windows\command\EpicGamesLauncher.exe Z:\path\PlayRDR2.exe <args>`

It uses the fake `EpicGamesLauncher.exe` that Heroic copies into the prefix when `USE_FAKE_EPIC_EXE` is set. Heroic's built-in RDR2 fix sets it.

```
./setup.sh extra rdr2-epic-heroic        # links it to ~/Games/Heroic/rdr2-fake-egl-wrapper.sh
```
Then go to Heroic → RDR2 → Settings → Advanced → **Wrapper command** → set it to that path, with no arguments.

- Keep **Disable umu** on. The wrapper expects the plain Proton command line.
- Each launch is logged to `~/.cache/rdr2-debug/wrapper.log`, with the auth code redacted. `inserted=1` means it worked.

## Adding it to Steam (for Big Picture / streaming)
Heroic → game → ⋮ → **Add to Steam**. The shortcut runs `heroic --no-gui "heroic://launch?appName=Heather&runner=legendary"`, so all of Heroic's settings still apply. Leave "Force a specific compatibility tool" **off** in Steam.

## Graphics notes
- Stay on **DX12** under Proton. vkd3d-proton translates it to Vulkan anyway.
- **MSAA off**, TAA High.
- FSR 2 Quality at 4K for headroom when streaming.
