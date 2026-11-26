#!/usr/bin/env bash
# Undo apply.sh:  sudo ./revert.sh [--dry-run]
set -euo pipefail
DRY=no; [[ ${1:-} == --dry-run ]] && DRY=yes
[[ $DRY == yes || $EUID -eq 0 ]] || { echo "run with sudo (or --dry-run)" >&2; exit 1; }
run() { if [[ $DRY == yes ]]; then echo "[dry-run] $*"; else "$@"; fi; }
CONF=/etc/bluetooth/main.conf; STATE=/var/lib/xbox-controller-bluetooth
if [[ -e $CONF.pre-xbox-bt ]]; then run mv "$CONF.pre-xbox-bt" "$CONF"; echo "restored $CONF"; fi
run rm -f /etc/modprobe.d/btusb-no-autosuspend.conf
if [[ -e $STATE/wifi-was-on ]]; then run nmcli radio wifi on; run rm -f "$STATE/wifi-was-on"; echo "Wi-Fi radio back on"; fi
run systemctl restart bluetooth
echo "Reverted (autosuspend default returns after the next reboot)."
