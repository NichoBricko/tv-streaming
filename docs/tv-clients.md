# Moonlight on your TV: which client, and how

Sunshine works with any Moonlight client. What differs between TVs is how you get Moonlight onto them, and how well their hardware decodes 4K HEVC.

| TV / device | Moonlight client | How to install | Notes |
|---|---|---|---|
| **Android TV / Google TV** (Sony, Philips, TCL, Hisense, Xiaomi, **Nvidia Shield**, **Google TV Streamer**, Chromecast w/ Google TV) | Moonlight Game Streaming (official) | Google Play Store | The easiest option. Shield and Google TV Streamer have gigabit Ethernet and strong decoders. |
| **Apple TV 4K** (2nd gen 2021, 3rd gen 2022) | Moonlight Game Streaming (official) | App Store | Very good decoder. The 3rd-gen **64 GB has no Ethernet**; get the 128 GB model. |
| **Amazon Fire TV** (Stick 4K / 4K Max, Cube) | Moonlight (official Android build) | Amazon Appstore | The Cube has Ethernet; sticks need a USB Ethernet adapter for a stable 4K stream. |
| **LG webOS** (webOS 3+) | [Moonlight TV](https://github.com/mariotaku/moonlight-tv) (community port) | Sideload via LG Developer Mode, see [`extras/lg-webos-devmode`](../extras/lg-webos-devmode/README.md) | Works well. Developer Mode must be renewed (automated by the extra). LG Ethernet is 100 Mb/s, so keep bitrate ≤ ~65 Mbps. TV Bluetooth controller lag was high in our test. |
| **Samsung Tizen** (2020+, Tizen 5.5+) | Moonlight for Tizen (community, [brightcraft/moonlight-tizen](https://github.com/brightcraft/moonlight-tizen)) | Sideload: enable Developer Mode on the TV, then use the **Apps2Samsung** installer or Tizen Studio (see the project's Installation Guide) | The community also reports HDR/120 fps on newer Tizen. Steps change between Tizen versions, so follow the project's current guide. |
| **Roku**, older/other smart TVs | none | Use one of the boxes above on an HDMI input | |
| Any TV, no extra box | **Steam Link** app (Valve) | Most app stores, incl. LG/Samsung | An alternative to Moonlight that uses Steam Remote Play instead of Sunshine. Not covered by this repo. |

## Recommended Moonlight settings
- **Resolution / fps:** your TV's native resolution, usually **3840x2160 @ 60**.
- **Bitrate:**
  - **50–80 Mbps** for 4K60 HEVC on gigabit Ethernet;
  - **≤ 65 Mbps** if the device has 100 Mb/s Ethernet (most TVs);
  - Wi-Fi: 5 GHz only, start around 40 Mbps.
- **Codec:** HEVC (or AV1 if both the GPU and the client support it). Auto usually picks correctly.
- **Wired Ethernet** on both ends if at all possible.
- **TV picture mode: Game / Game Optimizer** for low input lag.

## Pairing
1. On the PC, start Sunshine (`sunshine-on-demand start`) and open <https://localhost:47990>. Create the login the first time.
2. In Moonlight, the PC appears automatically. If it doesn't, add it by IP.
3. Moonlight shows a **PIN**. Enter it in Sunshine's web UI under **PIN**.
4. Give the client a **fixed IP** in your router. The firewall rules and the Wake listener only accept `CLIENT_IP`.

## Controller: TV or PC?
| Paired to | Latency | Wake the PC with it | Config |
|---|---|---|---|
| **The PC** (Bluetooth or USB) | Lowest | Possible (Bluetooth wake) | `BLOCK_CLIENT_CONTROLLER="yes"`, so the TV can send no input at all |
| **The TV / box** | Depends on the device; the LG TV was noticeably laggy, Shield and Apple TV are good | No | `BLOCK_CLIENT_CONTROLLER="no"` |

**Xbox controllers on Linux Bluetooth:**
- **Update the controller firmware first** (Xbox Accessories app on Windows or Xbox). Pairing failed on firmware 5.09 and worked on 5.17.
- If desktop pairing fails, pair with `bluetoothctl`: `agent NoInputNoOutput`, `default-agent`, `scan le`, `pair <MAC>`, `trust <MAC>`, `connect <MAC>`.
- **Attach the Wi-Fi/Bluetooth antennas** to the motherboard. Without them we got a disconnect every 8–30 s.
