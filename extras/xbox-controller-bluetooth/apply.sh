#!/usr/bin/env bash
# Make Xbox (Series / One, Bluetooth LE) controllers stay connected on Linux.
#   sudo ./apply.sh [--dry-run] [--keep-wifi]
#
# 1. BlueZ LE connection parameters in /etc/bluetooth/main.conf [LE]:
#    short connection interval + 2 s supervision timeout (Linux default ~420 ms
#    drops the link on a short radio hiccup, then takes ~1 s to reconnect).
# 2. Bluetooth USB autosuspend off (btusb), now and after reboots.
# 3. Wi-Fi radio off (combo Wi-Fi/Bluetooth chips share the antenna; idle Wi-Fi
#    scans steal airtime) - skipped with --keep-wifi or if Wi-Fi is in use.
# Undo everything with: sudo ./revert.sh
set -euo pipefail
DRY=no; KEEP_WIFI=no
for a in "$@"; do case $a in --dry-run) DRY=yes ;; --keep-wifi) KEEP_WIFI=yes ;; *) echo "unknown option $a" >&2; exit 2 ;; esac; done
[[ $DRY == yes || $EUID -eq 0 ]] || { echo "run with sudo (or --dry-run)" >&2; exit 1; }
run() { if [[ $DRY == yes ]]; then echo "[dry-run] $*"; else "$@"; fi; }
CONF=/etc/bluetooth/main.conf
STATE=/var/lib/xbox-controller-bluetooth; MODPROBE=/etc/modprobe.d/btusb-no-autosuspend.conf

echo "== BlueZ LE connection parameters ($CONF)"
[[ -e $CONF.pre-xbox-bt ]] || run cp -p "$CONF" "$CONF.pre-xbox-bt"
if [[ $DRY == yes ]]; then
  echo "[dry-run] set in [LE]: MinConnectionInterval=7 MaxConnectionInterval=9 ConnectionLatency=0 ConnectionSupervisionTimeout=200"
else
  python3 -I - "$CONF" <<'PY'
import re, sys
p = sys.argv[1]; lines = open(p).read().splitlines()
want = {"MinConnectionInterval": "7", "MaxConnectionInterval": "9",
        "ConnectionLatency": "0", "ConnectionSupervisionTimeout": "200"}
start = next((i for i, l in enumerate(lines) if l.strip() == "[LE]"), None)
if start is None:
    lines += ["", "[LE]"]; start = len(lines) - 1
end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
for k, v in want.items():
    idx = [i for i in range(start + 1, end) if re.match(rf"\s*{k}\s*=", lines[i])]
    if idx:
        lines[idx[0]] = f"{k}={v}"
    else:
        lines.insert(start + 1, f"{k}={v}"); end += 1
open(p, "w").write("\n".join(lines) + "\n")
PY
  echo "   set (backup: $CONF.pre-xbox-bt)"
fi

echo "== Bluetooth USB autosuspend off"
run sh -c "echo 'options btusb enable_autosuspend=n' > $MODPROBE"
for d in /sys/class/bluetooth/hci*/device/..; do
  [[ -w $d/power/control ]] && run sh -c "echo on > $(readlink -f "$d")/power/control"
done

echo "== Wi-Fi radio"
run mkdir -p "$STATE"
if [[ $KEEP_WIFI == yes ]]; then
  echo "   kept on (--keep-wifi)"
elif nmcli -t -f TYPE,STATE device 2>/dev/null | grep -q '^wifi:connected'; then
  echo "   Wi-Fi is in use - kept on (use Ethernet for game streaming)"
elif [[ $(nmcli radio wifi 2>/dev/null) == enabled ]]; then
  run nmcli radio wifi off; run touch "$STATE/wifi-was-on"; echo "   turned off"
else
  echo "   already off"
fi

echo "== Restart Bluetooth (the controller reconnects within a few seconds)"
run systemctl restart bluetooth
echo "Done. Autosuspend fully applies after the next reboot. Undo: sudo $(dirname "$0")/revert.sh"
