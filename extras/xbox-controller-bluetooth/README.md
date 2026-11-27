# Xbox controller dropouts over Bluetooth (Linux)

**Symptom:** an Xbox Series or Xbox One controller connected to the PC over Bluetooth disconnects for about a second, now and then. The kernel log shows `failed to send FF report` (a rumble command failing), then the controller reappears:
```bash
journalctl -k -b | grep -E 'failed to send FF report|input: Xbox Wireless Controller'
```
(`./setup.sh report` counts these under "Controller".)

## Likely causes
- **Linux's default LE supervision timeout is only ~420 ms.** A short radio hiccup drops the link, and the reconnect takes about a second. xpadneo's docs recommend shorter connection intervals and a longer timeout for Series controllers.
- **Wi-Fi + Bluetooth combo chips share one antenna.** If Wi-Fi is enabled but unused, its background scans still steal airtime from Bluetooth.
- **Bluetooth USB autosuspend** (`btusb`): rarely the cause, but cheap to rule out.

> ⚠️ **Known problem (open): after `apply.sh`, new pairings and reconnects can fail completely.** See [below](#known-problem-the-pc-cant-connect-to-the-controller-any-more). Until it's resolved, prefer `--keep-wifi`, and run `revert.sh` first if the controller stops connecting.

## Fix (free, reversible)
```bash
sudo ./apply.sh --dry-run    # preview
sudo ./apply.sh              # LE parameters, autosuspend off, Wi-Fi radio off (only if unused)
```
- It **backs up** `/etc/bluetooth/main.conf` as `main.conf.pre-xbox-bt` and restarts Bluetooth; the controller reconnects by itself. Reboot once so the autosuspend change fully applies.
- **Want to keep Wi-Fi?** Use `--keep-wifi`. If Wi-Fi is connected (in use), the script leaves it on anyway.
- **Undo everything:** `sudo ./revert.sh`.

## Find the real reason if it still drops
Record one gaming session with the Bluetooth monitor, in a terminal:
```bash
sudo btmon -w ~/btmon-session.snoop     # Ctrl+C when done
btmon -r ~/btmon-session.snoop | grep -B2 -A6 'Disconnect Complete'
```
The `Reason:` field says why:
- **Connection Timeout (0x08)** = the radio link was lost: placement, interference, antenna;
- **Remote User Terminated (0x13)** = the controller ended it itself, e.g. idle power-off or low battery.

## Known problem: the PC can't connect to the controller any more
**Seen on the reference PC (onboard Realtek RTL8851BE/BU Wi-Fi + Bluetooth combo, BlueZ 5.88, kernel 7.3.6), 2026-11-27, about one day after `apply.sh`.** Status: **open**, root cause not isolated.

- **Symptom:** KDE "Connect" fails instantly ("could not connect"); after removing the device, pairing fails with `org.bluez.Error.AuthenticationCanceled`. The controller advertises with a strong signal (about −49 dBm), the PC opens a connection, and about 50 ms later it ends with **`Connection Failed to be Established (0x3e)`** (`btmon`). 36 of 36 attempts failed. The same controller paired with a phone instantly, so it was the PC side.
- **Ruled out:**
  - the TV (off);
  - controller batteries and a controller reset;
  - signal strength;
  - scanning during the connection;
  - the `[LE]` parameters alone (default `main.conf` + `modprobe -r btusb && modprobe btusb` still failed);
  - kernel, firmware and BlueZ updates (identical to the last working boot).
- **What fixed it:** `revert.sh` + `nmcli radio wifi on` + driver reload + restarting bluetooth and NetworkManager. The controller paired at once. That leaves two suspects:
  - **the Wi-Fi radio being off** (on a combo chip, Bluetooth and Wi-Fi share the radio, and the Wi-Fi side's power state can affect Bluetooth coexistence);
  - **btusb autosuspend being off**;
  - or the combination after some uptime/suspend cycles. Note: the controller *did* reconnect fine for one evening with all three changes active, so it doesn't fail immediately.
- **Not yet done (to resolve it later):**
  1. Re-apply one change at a time (first only `[LE]`, then autosuspend, then Wi-Fi off) and test a fresh pairing plus a reconnect after each, including after suspend/resume and a cold boot via Wake-on-LAN.
  2. Watch `dmesg` for `rtw89`/`btrtl` coexistence messages while Wi-Fi is off.
  3. Decide the default: most likely **don't** turn the Wi-Fi radio off in `apply.sh` (make it opt-in).
- **Quick recovery:** `sudo ./revert.sh && sudo nmcli radio wifi on && sudo modprobe -r btusb && sudo modprobe btusb && sudo systemctl restart bluetooth`, then pair again. If even that fails: a full power cut (PSU off for 30 s), because Wake-on-LAN keeps the onboard chip powered through shutdowns and reboots.

## If dropouts continue
1. **USB-C data cable** to a **rear** port: zero risk, lowest latency.
2. **Microsoft Xbox Wireless Adapter** (model 1790). It works with the normal console controllers; there's no "PC version". It uses its own radio (it can use 5 GHz) instead of Bluetooth.
   - Linux driver: `xone` (CachyOS: `sudo pacman -S xone-dkms xone-dongle-firmware`).
   - ⚠️ **xone has been unmaintained since July 2026.** Kernel 7.4 is known to break it, and 7.3 is unverified. Keep an LTS kernel installed as a fallback boot entry, and check that xone builds before each kernel upgrade.
   - The controller remembers one Xbox-protocol device (adapter or console) plus one Bluetooth device; double-tap Pair to switch.
3. **Another Bluetooth dongle** is a lottery on Linux. The common Realtek RTL8761B dongles (TP-Link UB500, Asus BT500) have the same "disconnects after a while" reports. Check xpadneo's [dongle list](https://github.com/atar-axis/xpadneo/blob/master/docs/BT_DONGLES.md) before buying.

Sources: [xpadneo troubleshooting](https://github.com/atar-axis/xpadneo/blob/master/docs/TROUBLESHOOTING.md), [xone](https://github.com/dlundqvist/xone), [Xbox Wireless Adapter compatibility](https://www.microsoft.com/en-us/d/xbox-wireless-adapter-for-windows/91dqrb97l130).
