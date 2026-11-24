# Moonlight on an LG webOS TV (Developer Mode)

[Moonlight TV](https://github.com/mariotaku/moonlight-tv) is the webOS port of Moonlight. It is not a regular LG Content Store app, so it's **sideloaded** through LG's official **Developer Mode**. Tested on a 55NANO766QA (webOS 22). The port supports webOS 3 and newer.

> First search the LG Content Store for "Moonlight". If it's listed in your region, install it from there and skip everything below.

## 1. Developer Mode on the TV
1. Create a free account at <https://webostv.developer.lge.com>.
2. On the TV, open the LG Content Store and install **Developer Mode**. The seller is "LGE", the official app.
3. Open it, sign in, and turn on **Dev Mode Status**. The TV restarts.
4. Open it again and turn on **Key Server**. Note the **IP** and **passphrase** it shows.

## 2. LG's CLI tools on the PC (no root)
```
npm install -g --prefix ~/.local @webos-tools/cli        # needs nodejs + npm
ares-setup-device -a lgtv -i "host=<TV_IP>" -i "port=9922" -i "username=prisoner" -i "default=true"
ares-novacom --device lgtv --getkey                       # enter the passphrase
ares-setup-device -m lgtv -i "privatekey=lgtv_webos" -i "passphrase=<PASSPHRASE>"
ares-device -i -d lgtv                                    # should print model + webOS version
```
The key is saved in `~/.ssh/lgtv_webos`. Never commit it.

## 3. Install Moonlight TV
```
mkdir -p ~/Downloads/moonlight-tv && cd ~/Downloads/moonlight-tv
# download com.limelight.webos_<version>_arm.ipk from
# https://github.com/mariotaku/moonlight-tv/releases and check its sha256 against the release page
ares-install -d lgtv com.limelight.webos_*_arm.ipk
ares-launch  -d lgtv com.limelight.webos
```
To update later, run `ares-install` again with the new `.ipk`.

## 4. Keep Developer Mode alive
The Developer Mode session expires (currently after **1000 hours**), and then sideloaded apps are removed. This module renews it daily:
```
./setup.sh extra lg-webos-devmode
```
- It installs `lgtv-devmode-extend` plus a daily user timer.
- The script reads the session token from the TV (`/var/luna/preferences/devmode_enabled`, over the Dev Mode SSH channel) and caches it in `~/.config/lgtv-devmode/token` (mode 600).
- It then calls LG's `ResetDevModeSession` endpoint, so renewal also works while the TV is off.
- Different device name? Set `LGTV_DEVICE` in the timer's service.
- Check it with `journalctl --user -u lgtv-devmode-extend`. "After: … 999:59:59" means it worked.

Remove it with `systemctl --user disable --now lgtv-devmode-extend.timer` and delete the links in `~/.local/bin` and `~/.config/systemd/user`.

## Moonlight TV settings that worked well
- Resolution 3840x2160 and 60 fps. The codec picks HEVC automatically.
- **Bitrate ~55 Mbps.** LG TVs have **100 Mb/s Ethernet**; the maximum offered is 65.
- HDR off unless your PC streams HDR.
- This version has **no stats overlay**. Check bitrate on the PC side instead, e.g. in Sunshine's log ("Streaming bitrate is …").
- **The TV's Bluetooth adds noticeable input lag** for controllers. Pairing the controller with the PC was much better. If you do that, set `BLOCK_CLIENT_CONTROLLER="yes"`.

## Privacy
Turn off **Live Plus** (LG's automatic content recognition). It analyses what's on screen, including HDMI and apps. Find it in Settings → General → System → Additional Settings; menu names vary by firmware.
