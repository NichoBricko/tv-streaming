# Moonlight on your TV

Sunshine works with any Moonlight client. What differs between TVs is how Moonlight gets onto the TV, how fast its network port is, and whether it stays on the network in standby. That last one decides whether a single **Wake** press can start a cold PC (see [Standby check](#standby-check)).

## Which client for your TV
| TV / device | Moonlight client | How to install | Claude can do it | Notes |
|---|---|---|---|---|
| **Android TV / Google TV**: Sony, TCL, Philips, Sharp, Xiaomi, Hisense (Android models); **Nvidia Shield**, **Google TV Streamer**, Chromecast with Google TV | Moonlight Game Streaming (official) | Google Play Store, or the APK from [moonlight-android releases](https://github.com/moonlight-stream/moonlight-android/releases) | **Yes** via `adb` ([below](#android-tv--google-tv--fire-os-via-adb)) | Easiest platform; `adb logcat` shows Moonlight's own log. Shield and Google TV Streamer have gigabit Ethernet; most TVs 100 Mb/s. |
| **LG webOS** (webOS 3+) | [Moonlight TV](https://github.com/mariotaku/moonlight-tv) (community) | Sideload via LG Developer Mode | **Yes** via LG's `ares` tools: [extras/lg-webos-devmode](../extras/lg-webos-devmode/README.md) | Developer Mode must be renewed (automated). 100 Mb/s Ethernet, weak SoC: use decoder **NDL** + `SUNSHINE_STRICT_RC`; **60 Mbps** verified on the reference TV (start at 40 on an unknown TV); measure with `lgtv-stream-stats` ([stutter](troubleshooting.md#stream-stutter-on-smart-tvs)). The TV's Bluetooth added noticeable controller lag. Standby drops off the network (verified). |
| **Samsung Tizen** (2020+, Tizen 5.5+) | [Moonlight for Tizen](https://github.com/brightcraft/moonlight-tizen) (community) | Developer Mode on the TV, then **Apps2Samsung** (easiest) or Tizen Studio / `sdb`; follow the project's [Installation Guide](https://github.com/brightcraft/moonlight-tizen/wiki/Installation-Guide) | Partly (guided; the certificate step is manual) | Steps change between Tizen versions. Turn off "Instant On" if the TV answers pings in standby. |
| **Apple TV 4K** (2021+) | Moonlight Game Streaming (official) | App Store | No (manual) | 128 GB model has gigabit Ethernet (the 3rd-gen 64 GB has none). Good controller support. |
| **Amazon Fire TV on Fire OS**: Fire TV Stick 4K / 4K Max (older generations), Fire TV Cube, Fire OS TVs | Moonlight (Android build) | Amazon Appstore, or APK via `adb` | **Yes** via `adb` | Sticks have no Ethernet; use a USB Ethernet adapter for stable 4K. |
| **Fire TV on Vega OS** (Fire TV Stick 4K Select, some Stick HD) | - | - | - | **Not supported:** Vega OS can't run Android apps or sideload. |
| **Hisense VIDAA, Roku, Panasonic (own OS), other smart TVs** | - | no Moonlight client exists | - | Plug one of the devices above into an HDMI input. |
| Any TV with **Steam Link** | Steam Link (Valve) | TV app store | - | Different technology (Steam Remote Play), not covered by this project. |

## Android TV / Google TV / Fire OS via adb
Claude (or you) can install and launch Moonlight from the PC:
1. **On the TV, enable developer options:**
   - **Android/Google TV:** Settings → System → About → click **Build** 7 times. Then Developer options → **USB debugging** + **Network debugging**. On Android TV 11+ it's **Wireless debugging**, which shows a pairing code.
   - **Fire OS:** Settings → My Fire TV → Developer options → **ADB debugging** + **Apps from Unknown Sources**.
2. **On the PC:** install `adb` (`android-tools` / `adb` package), then:
   ```bash
   adb pair <TV-IP>:<pair-port>     # Wireless debugging only, enter the code shown on the TV
   adb connect <TV-IP>:5555          # (or the port shown under Wireless debugging); accept the prompt on the TV
   adb install moonlight-*.apk       # APK from the moonlight-android GitHub releases (verify the release page)
   adb shell monkey -p com.limelight -c android.intent.category.LAUNCHER 1   # launch
   adb logcat | grep -i limelight    # Moonlight's log while testing
   ```
3. **Turn developer options off again** when you're done (or at least network debugging).

## Recommended Moonlight settings
- **Resolution / fps:** your TV's native resolution, usually **3840x2160 @ 60**.
- **Bitrate:**
  - smart TVs with 100 Mb/s Ethernet: **60 Mbps** with decoder **NDL** and `SUNSHINE_STRICT_RC="yes"` (verified on the reference LG: 0 dropped packets in 46 min incl. fast driving, versus 170/min at 55 Mbps with decoder Auto). On an unknown TV start at **40** (Moonlight TV's FAQ calls 35–40 the webOS sweet spot), then raise it while `lgtv-stream-stats` stays at ~0 drops;
  - **80–150 Mbps** on gigabit boxes;
  - Wi-Fi: 5 GHz only, start around 40.
- **Codec:** HEVC (Auto usually picks it). HDR off unless the PC streams HDR.
- **LG webOS decoder:** set **NDL** explicitly rather than Auto (Moonlight TV: NDL always performs better than SMP).
- **Picture vs. bitrate:** about 13 Mbps goes to error correction and audio: 60 Mbps → ~47 Mbps of video ("very clear" on the reference TV), 40 → ~31 (clean, softer in fast motion). If your TV only manages 40, **1440p** is sharper in motion at that bitrate (the TV upscales).
- **Network:** wired Ethernet on both ends if at all possible.
- **TV picture mode:** **Game / Game Optimizer**.

## LG privacy settings
Worth turning off for privacy. **No evidence that they improve streaming**: the reference TV used 5% CPU at idle.
- **With the remote:**
  - Settings → General → System → Additional Settings → **Live Plus** off (screen-content recognition) and **Home Settings → Home Promotion / Content Recommendation** off;
  - User Agreements: decline the optional ones;
  - **Limit AD Tracking** on;
  - AI recommendations off;
  - **Quick Start+** off (it also keeps the standby check reliable).
- **Optional DNS blocking** (router / Pi-hole / AdGuard Home):
  - safe to block: `lgads.tv`, `lgsmartad.com`, `ad.lgappstv.com`, `alphonso.tv`, `lgsmartplatform.com`, `elastic.lgwebostv.com`;
  - **don't** block `wiselg.com` (apps break), `us.lgtvsdp.com` (clock), `lgappstv.com` (Content Store) or `ngfts.lge.com`.
- **Debloat tools:** `cleanyourtv` (popular, Claude/Codex-driven) works over ADB and therefore only on **Android/Google TV**; on those it's careful (disables apps, has a restore). Its webOS ports only replace the home screen.

## Pairing (same on every client)
1. Give the client a **fixed IP** (DHCP reservation in your router). The firewall and the Wake listener only accept `CLIENT_IP`.
2. On the PC: `sunshine-on-demand start`, open <https://localhost:47990>, and create the login the first time.
3. In Moonlight, select the PC (or add it by IP). Moonlight shows a **PIN**; enter it in Sunshine's web UI under **PIN**.

## Standby check
The one-press cold boot (`TV_AUTOLOGIN="auto"`) works because the PC pings the client right after boot: **"it answers" = "someone is on the TV and pressed Wake"**. Test this once:

1. Put the TV/box in **standby** with the remote, and wait 30 s.
2. On the PC: `ping -c3 <TV-IP>`.
   - **No answer** → keep `TV_AUTOLOGIN="auto"` (one press).
   - **Answers** → the device stays on the network in standby. Turn that setting off, for example LG **Quick Start+**, Samsung **Instant On**, or Android TV's "network standby" / "remote start" options (names vary by brand). If it can't be turned off, set `TV_AUTOLOGIN="on-wake"`: press Wake once to power on, and again at the login screen.

## Controller: TV or PC?
| Paired to | Latency | Config |
|---|---|---|
| **The PC** (Bluetooth or USB) | Lowest | `BLOCK_CLIENT_CONTROLLER="yes"`, so the TV can send no input at all |
| **The TV / box** | Depends on the device (LG TV: laggy; Shield / Apple TV: good) | `BLOCK_CLIENT_CONTROLLER="no"` |

Xbox controller firmware, antennas and `bluetoothctl` pairing: see [troubleshooting.md](troubleshooting.md#controller).
