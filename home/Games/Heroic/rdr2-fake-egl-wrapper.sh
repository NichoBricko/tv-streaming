#!/usr/bin/env bash
# Heroic wrapper for Red Dead Redemption 2 (Epic).
#
# The Rockstar Launcher only grants Epic ownership when EpicGamesLauncher.exe is
# the parent of the game. Heroic tries to do this via LEGENDARY_WRAPPER_EXE, but
# the bundled legendary (0.21.0) ignores that variable. This script rewrites
#   proton waitforexitandrun /path/PlayRDR2.exe <args>
# into
#   proton waitforexitandrun C:\windows\command\EpicGamesLauncher.exe Z:\path\PlayRDR2.exe <args>
# using the fake EpicGamesLauncher.exe that Heroic already copies into the prefix.

LOG="$HOME/.cache/rdr2-debug/wrapper.log"
mkdir -p "$(dirname "$LOG")"

FAKE_EGL='C:\windows\command\EpicGamesLauncher.exe'

args=()
inserted=0
prev=""
for a in "$@"; do
  if [[ $inserted == 0 && ( $prev == waitforexitandrun || $prev == run ) && ${a,,} == *.exe ]]; then
    if [[ $a == /* ]]; then
      win="Z:${a//\//\\}"   # unix path -> Windows path on the Z: (root) drive
    else
      win="$a"
    fi
    args+=("$FAKE_EGL" "$win")
    inserted=1
  else
    args+=("$a")
  fi
  prev=$a
done

{
  echo "=== $(date '+%F %T') inserted=$inserted"
  printf '%q ' "${args[@]}" | sed -E 's/-AUTH_PASSWORD=[^ ]+/-AUTH_PASSWORD=<redacted>/'
  echo
} >>"$LOG"

exec "${args[@]}"
