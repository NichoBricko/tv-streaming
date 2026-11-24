#!/usr/bin/env bash
# sunshine-on-demand installer
#
#   ./setup.sh configure [--client-ip IP] [--force]   detect this PC, write config.env
#   ./setup.sh install   [--user|--system] [--dry-run] apply config.env
#   ./setup.sh setcap    [--dry-run]                  (re)grant Sunshine KMS capture caps
#   ./setup.sh extra <lg-webos-devmode|rdr2-epic-heroic> [--dry-run]
#   ./setup.sh status                                 show what's installed / running
#   ./setup.sh uninstall [--dry-run]                  remove everything this installed
#
# User-level parts need no root. System-level parts call sudo (run them in a real
# terminal so sudo can ask for your password).

set -euo pipefail
REPO=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
CONFIG_SRC=${SOD_SETUP_CONFIG:-$REPO/config.env}   # override to keep several configs
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sunshine-on-demand"
SUN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sunshine"
BIN_DIR="$HOME/.local/bin"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
SYS_LIB=/usr/local/lib/sunshine-on-demand
SYS_ENV=/etc/sunshine-on-demand.env
SUNSHINE_TCP="47984,47989,48010"
SUNSHINE_UDP="47998:48000"
DRY=no

c_bold=$'\e[1m'; c_dim=$'\e[2m'; c_red=$'\e[31m'; c_yel=$'\e[33m'; c_grn=$'\e[32m'; c_off=$'\e[0m'
say()  { echo "${c_bold}==${c_off} $*"; }
info() { echo "   $*"; }
warn() { echo "   ${c_yel}! $*${c_off}"; }
die()  { echo "${c_red}error:${c_off} $*" >&2; exit 1; }
run()  { if [[ $DRY == yes ]]; then echo "   ${c_dim}[dry-run]${c_off} $*"; else "$@"; fi; }
sudo_run() { run sudo "$@"; }
has()  { command -v "$1" >/dev/null 2>&1; }

load_config() {
  [[ -r $CONFIG_SRC ]] || die "no config.env - run: ./setup.sh configure --client-ip <IP>"
  # shellcheck source=/dev/null
  . "$CONFIG_SRC"
  [[ ${CLIENT_IP:-} =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] \
    || die "set CLIENT_IP in config.env to your TV/streaming box's IP"
  if [[ $WAKE_ON_LAN == yes && ! ${WOL_MAC:-} =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
    die "WAKE_ON_LAN=yes needs a valid WOL_MAC (aa:bb:cc:dd:ee:ff) in config.env"
  fi
  SUNSHINE_FLATPAK=${SUNSHINE_FLATPAK:-no}
  TV_SESSION=${TV_SESSION:-no}; TV_AUTOLOGIN=${TV_AUTOLOGIN:-wol}
  TV_WAKE_TYPES=${TV_WAKE_TYPES:-LAN Remote,PCI PME#}
}

# ------------------------------------------------------------------ detection
sunshine_conf_get() {  # value of a key in the existing sunshine.conf
  [[ -r $SUN_DIR/sunshine.conf ]] || return 0
  sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\1/p" "$SUN_DIR/sunshine.conf" | tail -1
}

detect() {
  local d
  # Sunshine service
  D_SUNSHINE_UNIT=""
  for u in app-dev.lizardbyte.app.Sunshine.service sunshine.service; do
    if systemctl --user cat "$u" >/dev/null 2>&1; then D_SUNSHINE_UNIT=$u; break; fi
  done
  D_SUNSHINE_FLATPAK=no
  has flatpak && flatpak info dev.lizardbyte.app.Sunshine >/dev/null 2>&1 && D_SUNSHINE_FLATPAK=yes

  # Firewall
  D_FIREWALL=none
  if systemctl is-active --quiet ufw 2>/dev/null && has ufw; then D_FIREWALL=ufw
  elif systemctl is-active --quiet firewalld 2>/dev/null; then D_FIREWALL=firewalld; fi

  # Display backend + output + current mode
  d=${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:-}
  D_BACKEND=none; D_OUTPUT=""; D_MODE=""
  if [[ $d == *KDE* ]] && has kscreen-doctor; then
    D_BACKEND=kscreen
    read -r D_OUTPUT D_MODE < <(kscreen-doctor -j 2>/dev/null | python3 -I -c '
import json, sys
outs = [o for o in json.load(sys.stdin)["outputs"] if o.get("enabled")]
outs.sort(key=lambda o: o.get("priority", 99))
if outs:
    o = outs[0]; m = {x["id"]: x for x in o["modes"]}[o["currentModeId"]]
    print(o["name"], "%dx%d@%d" % (m["size"]["width"], m["size"]["height"], round(m["refreshRate"])))') || true
  elif [[ $d == *GNOME* ]]; then
    D_BACKEND=custom
  elif [[ ${XDG_SESSION_TYPE:-} == wayland ]] && has wlr-randr; then
    D_BACKEND=wlr-randr
    read -r D_OUTPUT D_MODE < <(wlr-randr --json 2>/dev/null | python3 -I -c '
import json, sys
for o in json.load(sys.stdin):
    if o.get("enabled"):
        for m in o["modes"]:
            if m.get("current"):
                print(o["name"], "%dx%d@%d" % (m["width"], m["height"], round(m["refresh"]))); sys.exit()') || true
  elif [[ ${XDG_SESSION_TYPE:-} == x11 ]] && has xrandr; then
    D_BACKEND=xrandr
    read -r D_OUTPUT D_MODE < <(xrandr --query | awk '
      / connected/ {o=$1; p=($3=="primary")} o && /\*/ {for(i=2;i<=NF;i++) if($i~/\*/){r=$i; gsub(/[*+]/,"",r); m=sprintf("%s@%d",$1,r+0.5)}
        if(p||!first){first=o" "m} o=""} END{print first}') || true
  fi

  # Steam
  D_STEAM=""; D_APP_OPEN=""
  if has steam; then D_STEAM="steam"
  elif has flatpak && flatpak info com.valvesoftware.Steam >/dev/null 2>&1; then D_STEAM="flatpak run com.valvesoftware.Steam"; fi
  [[ -n $D_STEAM ]] && D_APP_OPEN="$D_STEAM steam://open/bigpicture"

  # Network card for Wake-on-LAN
  D_IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
  D_MAC=""; D_NM=""; D_IFACE_WIFI=no
  if [[ -n $D_IFACE ]]; then
    D_MAC=$(cat "/sys/class/net/$D_IFACE/address" 2>/dev/null || true)
    [[ -d /sys/class/net/$D_IFACE/wireless ]] && D_IFACE_WIFI=yes
    has nmcli && D_NM=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | awk -F: -v d="$D_IFACE" '$2==d{print $1; exit}')
  fi

  # Keep choices already made in sunshine.conf
  D_ENCODER=$(sunshine_conf_get encoder); D_CAPTURE=$(sunshine_conf_get capture)
  D_ADAPTER=$(sunshine_conf_get adapter_name)
  D_BLOCK_CTRL=no; [[ $(sunshine_conf_get controller) == disabled ]] && D_BLOCK_CTRL=yes
  D_SETCAP=no
  local bin; bin=$(readlink -f "$(command -v sunshine 2>/dev/null || true)" 2>/dev/null || true)
  if [[ -n $bin && $D_SUNSHINE_FLATPAK == no ]] && getcap "$bin" 2>/dev/null | grep -q cap_sys_admin; then D_SETCAP=yes; fi
}

cmd_configure() {
  local client_ip="" force=no
  while (($#)); do case $1 in
    --client-ip) client_ip=${2:-}; shift; shift || true ;;
    --force) force=yes; shift ;;
    *) die "unknown option $1" ;;
  esac; done
  [[ -e $CONFIG_SRC && $force == no ]] && die "config.env exists (use --force to regenerate)"
  detect

  if [[ -z $client_ip && -t 0 ]]; then
    read -r -p "IP address of your TV / streaming box (give it a fixed IP in your router): " client_ip
  fi
  [[ -n $client_ip ]] || warn "no --client-ip given; set CLIENT_IP in config.env before installing"

  say "Detected"
  info "Sunshine unit:    ${D_SUNSHINE_UNIT:-NOT FOUND (install Sunshine first)}  flatpak=$D_SUNSHINE_FLATPAK"
  info "Firewall:         $D_FIREWALL"
  info "Display:          backend=$D_BACKEND output=${D_OUTPUT:-?} current=${D_MODE:-?}"
  info "Steam:            ${D_STEAM:-not found}"
  info "Wake-on-LAN NIC:  ${D_IFACE:-?} ${D_MAC:-?} (NetworkManager: ${D_NM:-none})"
  info "Encoder/capture:  ${D_ENCODER:-auto}/${D_CAPTURE:-auto} adapter=${D_ADAPTER:-auto} setcap=$D_SETCAP"
  [[ $D_BACKEND == custom ]] && warn "GNOME: set DISPLAY_SET_CMD/DISPLAY_RESTORE_CMD in config.env (see README) or DISPLAY_BACKEND=none"
  [[ $D_IFACE_WIFI == yes ]] && warn "$D_IFACE is Wi-Fi - Wake-on-LAN over Wi-Fi rarely works; use Ethernet or set WAKE_ON_LAN=no"
  [[ -z $D_STEAM ]] && warn "Steam not found - set APP_NAME/APP_OPEN_CMD for the app you want to stream"

  local wol=yes; [[ -z $D_MAC || $D_IFACE_WIFI == yes ]] && wol=no
  CFG_CLIENT_IP=$client_ip CFG_UNIT=${D_SUNSHINE_UNIT:-app-dev.lizardbyte.app.Sunshine.service} \
  CFG_FIREWALL=$D_FIREWALL CFG_BACKEND=$D_BACKEND CFG_OUTPUT=$D_OUTPUT CFG_MODE=$D_MODE \
  CFG_STEAM=${D_STEAM:-steam} CFG_APP_OPEN=${D_APP_OPEN:-steam steam://open/bigpicture} \
  CFG_IFACE=$D_IFACE CFG_MAC=$D_MAC CFG_NM=$D_NM CFG_WOL=$wol CFG_BLOCK_CTRL=$D_BLOCK_CTRL \
  CFG_ENCODER=$D_ENCODER CFG_CAPTURE=$D_CAPTURE CFG_ADAPTER=$D_ADAPTER CFG_SETCAP=$D_SETCAP \
  CFG_FLATPAK=$D_SUNSHINE_FLATPAK \
  python3 -I - "$REPO/config.env.example" "$CONFIG_SRC" <<'EOF'
import os, re, shlex, sys
src, dst = sys.argv[1:3]
e = os.environ
values = {
    "SUNSHINE_UNIT": e["CFG_UNIT"], "CLIENT_IP": e["CFG_CLIENT_IP"],
    "BLOCK_CLIENT_CONTROLLER": e["CFG_BLOCK_CTRL"], "FIREWALL": e["CFG_FIREWALL"],
    "APP_OPEN_CMD": e["CFG_APP_OPEN"], "STEAM_CMD": e["CFG_STEAM"],
    "DISPLAY_BACKEND": e["CFG_BACKEND"],
    "WAKE_ON_LAN": e["CFG_WOL"], "NM_CONNECTION": e["CFG_NM"],
    "SUNSHINE_ENCODER": e["CFG_ENCODER"], "SUNSHINE_CAPTURE": e["CFG_CAPTURE"],
    "SUNSHINE_ADAPTER": e["CFG_ADAPTER"], "SETCAP": e["CFG_SETCAP"],
    "SUNSHINE_FLATPAK": e["CFG_FLATPAK"],
}
for k, env in (("DISPLAY_OUTPUT", "CFG_OUTPUT"), ("RESTORE_MODE", "CFG_MODE"),
               ("WOL_IFACE", "CFG_IFACE"), ("WOL_MAC", "CFG_MAC")):
    if e[env]:
        values[k] = e[env]
out = []
for line in open(src):
    m = re.match(r"^([A-Z_]+)=", line)
    if m and m.group(1) in values:
        v = values[m.group(1)]
        line = f"{m.group(1)}={v if re.fullmatch(r'[0-9]+', v) else shlex.quote(v) if v else chr(34)*2}\n"
    out.append(line)
open(dst, "w").writelines(out)
EOF
  say "Wrote $CONFIG_SRC - review it, then run: ./setup.sh install"
}

# ------------------------------------------------------------------ install: user
link() {  # link <src in repo> <dst>
  local src=$1 dst=$2
  run mkdir -p "$(dirname "$dst")"
  if [[ -e $dst && ! -L $dst ]]; then run mv "$dst" "$dst.pre-sunshine-on-demand"; warn "backed up existing $dst"; fi
  run ln -sfn "$src" "$dst"
  info "linked $dst"
}

BACKUP=""
backup() {  # copy $1 aside; drop_unchanged_backup removes the copy again if nothing changed
  BACKUP=""
  [[ -e $1 ]] || return 0
  BACKUP="$1.bak-$(date +%Y%m%d-%H%M%S)"
  run cp -p "$1" "$BACKUP"
}
drop_unchanged_backup() {
  if [[ $DRY == no && -n $BACKUP ]] && cmp -s "$1" "$BACKUP"; then rm -f "$BACKUP"; info "$(basename "$1") unchanged"
  elif [[ -n $BACKUP ]]; then info "backup: $BACKUP"; fi
}

configure_sunshine_conf() {
  local f=$SUN_DIR/sunshine.conf
  run mkdir -p "$SUN_DIR"; [[ -e $f ]] || run touch "$f"
  backup "$f"
  local kbm=enabled ctrl=enabled; [[ $BLOCK_CLIENT_KEYBOARD_MOUSE == yes ]] && kbm=disabled
  [[ $BLOCK_CLIENT_CONTROLLER == yes ]] && ctrl=disabled
  local enc=""; [[ $REQUIRE_ENCRYPTION == yes ]] && enc=2
  local web=""; [[ $WEB_UI_LOCAL_ONLY == yes ]] && web=pc
  if [[ $DRY == yes ]]; then
    info "[dry-run] sunshine.conf: keyboard=$kbm mouse=$kbm controller=$ctrl lan_encryption_mode=${enc:-default} origin_web_ui_allowed=${web:-default} encoder=${SUNSHINE_ENCODER:-auto} capture=${SUNSHINE_CAPTURE:-auto} adapter_name=${SUNSHINE_ADAPTER:-auto}"
    return
  fi
  python3 -I - "$f" keyboard="$kbm" mouse="$kbm" controller="$ctrl" lan_encryption_mode="$enc" \
    origin_web_ui_allowed="$web" encoder="${SUNSHINE_ENCODER:-}" capture="${SUNSHINE_CAPTURE:-}" \
    adapter_name="${SUNSHINE_ADAPTER:-}" <<'EOF'
import re, sys
path, pairs = sys.argv[1], [a.split("=", 1) for a in sys.argv[2:]]
lines = open(path).read().splitlines()
for key, val in pairs:
    pat = re.compile(rf"^\s*{key}\s*=")
    idx = [i for i, l in enumerate(lines) if pat.match(l)]
    for i in reversed(idx[1:]):
        del lines[i]
    if val == "":                       # empty = let Sunshine use its default
        if idx: del lines[idx[0]]
    elif idx:
        lines[idx[0]] = f"{key} = {val}"
    else:
        lines.append(f"{key} = {val}")
open(path, "w").write("\n".join(lines) + "\n")
EOF
  drop_unchanged_backup "$f"
}

configure_apps_json() {
  local f=$SUN_DIR/apps.json
  backup "$f"
  if [[ $DRY == yes ]]; then info "[dry-run] apps.json: app '$APP_NAME'$( [[ $REMOVE_DESKTOP_APP == yes ]] && echo ', remove Desktop')"; return; fi
  APP_NAME=$APP_NAME APP_OPEN_CMD=$APP_OPEN_CMD BIN=$BIN_DIR INHIBIT=$INHIBIT_SLEEP UNLOCK=$UNLOCK_FOR_STREAM \
  BACKEND=$DISPLAY_BACKEND REMOVE_DESKTOP=$REMOVE_DESKTOP_APP FLATPAK=$SUNSHINE_FLATPAK \
  python3 -I - "$f" <<'EOF'
import json, os, sys
path = sys.argv[1]; e = os.environ; b = e["BIN"]
try:
    data = json.load(open(path))
except (FileNotFoundError, json.JSONDecodeError):
    data = {"env": {}, "apps": []}
# Sunshine runs "do" top-to-bottom and "undo" bottom-to-top.
prep = []
if e["INHIBIT"] == "yes":
    prep.append({"do": "systemctl --user start sunshine-stream-inhibit.service",
                 "undo": "systemctl --user stop sunshine-stream-inhibit.service"})
if e["UNLOCK"] == "yes":
    prep.append({"do": f"{b}/sunshine-session-lock unlock", "undo": f"{b}/sunshine-session-lock relock"})
if "bigpicture" in e["APP_OPEN_CMD"]:
    # undo runs after the display is restored, so Steam re-lays out for the normal mode
    prep.append({"do": "", "undo": f"{b}/sunshine-steam-reset"})
if e["BACKEND"] != "none":
    prep.append({"do": f"{b}/sunshine-display-mode stream", "undo": f"{b}/sunshine-display-mode restore"})
detached = [f"setsid {e['APP_OPEN_CMD']}"]
if e["FLATPAK"] == "yes":
    # Flatpak Sunshine runs commands inside its sandbox; run them on the host instead
    host = lambda c: f"flatpak-spawn --host {c}" if c else c
    prep = [{"do": host(x["do"]), "undo": host(x["undo"])} for x in prep]
    detached = [host(c) for c in detached]
app = {"name": e["APP_NAME"], "prep-cmd": prep, "detached": detached}
if "bigpicture" in e["APP_OPEN_CMD"]:
    app["image-path"] = "steam.png"
apps = [a for a in data.get("apps", []) if a.get("name") != e["APP_NAME"]]
if e["REMOVE_DESKTOP"] == "yes":
    apps = [a for a in apps if a.get("name") != "Desktop"]
data["apps"] = [app] + apps
json.dump(data, open(path, "w"), indent=2)
open(path, "a").write("\n")
EOF
  drop_unchanged_backup "$f"
}

install_user() {
  say "User files"
  run mkdir -p "$CONF_DIR"; run install -m 600 "$CONFIG_SRC" "$CONF_DIR/config.env"; info "copied config to $CONF_DIR/config.env"
  for s in "$REPO"/bin/*; do link "$s" "$BIN_DIR/$(basename "$s")"; done
  for u in "$REPO"/systemd/user/*; do link "$u" "$UNIT_DIR/$(basename "$u")"; done
  run mkdir -p "$APP_DIR"
  for a in "$REPO"/share/applications/*.desktop; do
    [[ -L $APP_DIR/$(basename "$a") ]] && run rm "$APP_DIR/$(basename "$a")"
    if [[ $DRY == yes ]]; then info "[dry-run] render $APP_DIR/$(basename "$a")"
    else sed "s#@BIN@#$BIN_DIR#g" "$a" > "$APP_DIR/$(basename "$a")"; info "wrote $APP_DIR/$(basename "$a")"; fi
  done

  say "Sunshine configuration"
  configure_sunshine_conf
  configure_apps_json

  say "User services"
  run systemctl --user daemon-reload
  run systemctl --user enable sunshine-login.service
  if (( IDLE_LIMIT > 0 )); then run systemctl --user enable --now sunshine-idle-stop.timer
  else run systemctl --user disable --now sunshine-idle-stop.timer 2>/dev/null || true; fi
  if [[ $ON_DEMAND == yes ]]; then run systemctl --user disable "$SUNSHINE_UNIT" 2>/dev/null || true; info "Sunshine no longer starts at login"; fi
  if systemctl --user is-active --quiet "$SUNSHINE_UNIT"; then warn "Sunshine is running - restart it to load the new config: sunshine-on-demand stop; sunshine-on-demand start"; fi
}

# ------------------------------------------------------------------ install: system
render_unit() {  # render_unit <template> <dest>
  local tmp; tmp=$(mktemp)
  sed -e "s/@USER@/$(id -un)/g" -e "s/@UID@/$(id -u)/g" "$1" > "$tmp"
  sudo_run install -m 644 "$tmp" "$2"; rm -f "$tmp"
}

firewall_rules() {  # firewall_rules add|delete
  local action=$1
  case $FIREWALL in
    ufw)
      ufw_rule() {  # ufw_rule <ports> <proto> <comment>
        if [[ $action == add ]]; then
          sudo_run ufw allow from "$CLIENT_IP" to any port "$1" proto "$2" comment "sunshine-on-demand: $3"
        else
          sudo_run ufw delete allow from "$CLIENT_IP" to any port "$1" proto "$2" || true
        fi
      }
      ufw_rule "$SUNSHINE_TCP" tcp "Sunshine"
      ufw_rule "$SUNSHINE_UDP" udp "Sunshine stream"
      if [[ $WAKE_ON_LAN == yes ]]; then ufw_rule 9 udp "Wake-on-LAN"; fi ;;
    firewalld)
      local op=--add-rich-rule; [[ $action == delete ]] && op=--remove-rich-rule
      local p
      for p in "47984 tcp" "47989 tcp" "48010 tcp" "47998-48000 udp" "9 udp"; do
        [[ $p == "9 udp" && $WAKE_ON_LAN != yes ]] && continue
        sudo_run firewall-cmd --permanent "$op=rule family=\"ipv4\" source address=\"$CLIENT_IP\" port port=\"${p% *}\" protocol=\"${p#* }\" accept"
      done
      sudo_run firewall-cmd --reload ;;
    none) info "no firewall configured (FIREWALL=none)" ;;
    *) warn "unknown FIREWALL '$FIREWALL'" ;;
  esac
}

install_system() {
  say "System units (sudo)"
  local tmp; tmp=$(mktemp)
  printf 'WOL_MAC=%s\nCLIENT_IP=%s\nSUNSHINE_UNIT=%s\nSOD_USER=%s\nTV_AUTOLOGIN=%s\nTV_WAKE_TYPES="%s"\n' \
    "$WOL_MAC" "$CLIENT_IP" "$SUNSHINE_UNIT" "$(id -un)" "$TV_AUTOLOGIN" "$TV_WAKE_TYPES" > "$tmp"
  sudo_run install -m 644 "$tmp" "$SYS_ENV"; rm -f "$tmp"
  sudo_run install -D -m 755 "$REPO/lib/sunshine-wol-handler.py" "$SYS_LIB/sunshine-wol-handler.py"
  sudo_run install -m 644 "$REPO/systemd/system/sunshine-wol.socket" /etc/systemd/system/sunshine-wol.socket
  render_unit "$REPO/systemd/system/sunshine-wol.service.in" /etc/systemd/system/sunshine-wol.service
  render_unit "$REPO/systemd/system/sunshine-resume.service.in" /etc/systemd/system/sunshine-resume.service
  [[ -d /usr/local/lib/sunshine-wol ]] && sudo_run rm -rf /usr/local/lib/sunshine-wol   # pre-generalization layout
  sudo_run systemctl daemon-reload
  if [[ $WAKE_ON_LAN == yes ]]; then
    sudo_run systemctl enable --now sunshine-wol.socket
    sudo_run systemctl enable sunshine-resume.service
  else
    sudo_run systemctl disable --now sunshine-wol.socket sunshine-resume.service 2>/dev/null || true
  fi

  install_tv_session

  say "Firewall ($FIREWALL): only $CLIENT_IP may reach Sunshine"
  firewall_rules add

  if [[ $WAKE_ON_LAN == yes && -n ${NM_CONNECTION:-} ]]; then
    say "Network card: wake on magic packet"
    if [[ $(nmcli -g 802-3-ethernet.wake-on-lan connection show "$NM_CONNECTION" 2>/dev/null) == magic ]]; then
      info "already set on '$NM_CONNECTION'"
    else
      sudo_run nmcli connection modify "$NM_CONNECTION" 802-3-ethernet.wake-on-lan magic
      sudo_run nmcli connection up "$NM_CONNECTION"
    fi
    info "also enable Wake-on-LAN in your BIOS/UEFI (see README)"
  fi
  [[ $SETCAP == yes ]] && cmd_setcap
  return 0
}

install_tv_session() {
  if [[ $TV_SESSION != yes ]]; then
    if [[ -e /etc/systemd/system/sunshine-tv-autologin.service ]]; then remove_tv_session; fi
    return 0
  fi
  say "TV session (cold boot via Wake-on-LAN -> locked Steam Big Picture kiosk)"
  local f
  for f in sunshine-tv-session sunshine-tv-session-inner sunshine-tv-autologin; do
    sudo_run install -D -m 755 "$REPO/tv-session/$f" "$SYS_LIB/$f"
  done
  sudo_run install -D -m 644 "$REPO/tv-session/sunshine-tv.desktop" /usr/share/wayland-sessions/sunshine-tv.desktop
  sudo_run install -m 644 "$REPO/tv-session/sunshine-tv-autologin.service" /etc/systemd/system/sunshine-tv-autologin.service
  if [[ -e /etc/plasmalogin.conf && ! -e /etc/plasmalogin.conf.pre-sunshine-on-demand ]]; then
    sudo_run cp -p /etc/plasmalogin.conf /etc/plasmalogin.conf.pre-sunshine-on-demand
  fi
  sudo_run systemctl daemon-reload
  sudo_run systemctl enable sunshine-tv-autologin.service
  info "auto-login mode: $TV_AUTOLOGIN (takes effect at the next boot)"
}

remove_tv_session() {
  say "Removing the TV session"
  sudo_run systemctl disable sunshine-tv-autologin.service 2>/dev/null || true
  # clear an auto-login this project set up
  if [[ -x $SYS_LIB/sunshine-tv-autologin ]]; then sudo_run env TV_AUTOLOGIN=no "$SYS_LIB/sunshine-tv-autologin"; fi
  sudo_run rm -f /etc/systemd/system/sunshine-tv-autologin.service /usr/share/wayland-sessions/sunshine-tv.desktop \
    "$SYS_LIB/sunshine-tv-session" "$SYS_LIB/sunshine-tv-session-inner" "$SYS_LIB/sunshine-tv-autologin"
  sudo_run systemctl daemon-reload
}

cmd_setcap() {
  local bin; bin=$(readlink -f "$(command -v sunshine 2>/dev/null || true)" 2>/dev/null || true)
  [[ -n $bin && $bin != *flatpak* ]] || { warn "no native sunshine binary (Flatpak can't use setcap; use portal capture)"; return 0; }
  say "Granting $bin cap_sys_admin (KMS capture) + cap_sys_nice"
  sudo_run setcap cap_sys_admin,cap_sys_nice+p "$bin"
}

cmd_install() {
  local what=all
  while (($#)); do case $1 in
    --user) what=user; shift ;; --system) what=system; shift ;; --dry-run) DRY=yes; shift ;;
    *) die "unknown option $1" ;;
  esac; done
  load_config
  [[ $what != system ]] && install_user
  [[ $what != user ]] && install_system
  say "${c_grn}Done.${c_off} Check with: ./setup.sh status"
}

# ------------------------------------------------------------------ extras
cmd_extra() {
  local name=${1:-}; shift || true
  [[ ${1:-} == --dry-run ]] && DRY=yes
  case $name in
    lg-webos-devmode)
      has ares-novacom || [[ -x $BIN_DIR/ares-novacom ]] || warn "ares-novacom not found - see extras/lg-webos-devmode/README.md"
      link "$REPO/extras/lg-webos-devmode/lgtv-devmode-extend" "$BIN_DIR/lgtv-devmode-extend"
      for u in lgtv-devmode-extend.service lgtv-devmode-extend.timer; do link "$REPO/extras/lg-webos-devmode/$u" "$UNIT_DIR/$u"; done
      run systemctl --user daemon-reload
      run systemctl --user enable --now lgtv-devmode-extend.timer ;;
    rdr2-epic-heroic)
      local dst="${HEROIC_WRAPPER_DIR:-$HOME/Games/Heroic}/rdr2-fake-egl-wrapper.sh"
      link "$REPO/extras/rdr2-epic-heroic/rdr2-fake-egl-wrapper.sh" "$dst"
      info "now set it as the wrapper command in Heroic -> RDR2 -> Settings -> Advanced (see extras/rdr2-epic-heroic/README.md)" ;;
    *) die "usage: ./setup.sh extra lg-webos-devmode|rdr2-epic-heroic [--dry-run]" ;;
  esac
}

# ------------------------------------------------------------------ status / uninstall
cmd_status() {
  # shellcheck source=/dev/null
  [[ -r $CONFIG_SRC ]] && . "$CONFIG_SRC"
  local u=${SUNSHINE_UNIT:-app-dev.lizardbyte.app.Sunshine.service} s
  say "Sunshine ($u)"
  info "active=$(systemctl --user is-active "$u" 2>/dev/null)  autostart=$(systemctl --user is-enabled "$u" 2>/dev/null)"
  say "User units"
  for s in sunshine-idle-stop.timer sunshine-login.service sunshine-stream-inhibit.service lgtv-devmode-extend.timer; do
    info "$s: $(systemctl --user is-enabled "$s" 2>/dev/null || true) / $(systemctl --user is-active "$s" 2>/dev/null || true)"
  done
  say "System units"
  for s in sunshine-wol.socket sunshine-resume.service sunshine-tv-autologin.service; do
    info "$s: $(systemctl is-enabled "$s" 2>/dev/null || true) / $(systemctl is-active "$s" 2>/dev/null || true)"
  done
  if [[ -n ${NM_CONNECTION:-} ]] && has nmcli; then
    say "Wake-on-LAN"; info "$NM_CONNECTION: $(nmcli -g 802-3-ethernet.wake-on-lan connection show "$NM_CONNECTION" 2>/dev/null)"
  fi
  local bin; bin=$(readlink -f "$(command -v sunshine 2>/dev/null || true)" 2>/dev/null || true)
  [[ -n $bin ]] && { say "Capabilities"; info "$(getcap "$bin" 2>/dev/null || true)"; }
  say "Last events"
  journalctl --user -t sunshine-tv-session -t sunshine-on-demand -t sunshine-session-lock -t sunshine-steam-reset -t sunshine-display-mode -n 6 --no-pager -o short 2>/dev/null | sed 's/^/   /'
  journalctl -u sunshine-tv-autologin -b --no-pager -o cat 2>/dev/null | grep 'wake-up type' | sed 's/^/   /' || true
  journalctl -u sunshine-wol -n 3 --no-pager -o cat 2>/dev/null | grep -v -e '^Starting' -e '^Finished' | sed 's/^/   /' || true
}

cmd_uninstall() {
  [[ ${1:-} == --dry-run ]] && DRY=yes
  load_config
  say "User side"
  run systemctl --user disable --now sunshine-idle-stop.timer 2>/dev/null || true
  run systemctl --user disable sunshine-login.service 2>/dev/null || true
  local f
  if [[ $DRY == no ]]; then "$BIN_DIR/sunshine-on-demand" cleanup 2>/dev/null || true; fi
  for f in "$REPO"/bin/*; do
    if [[ -L $BIN_DIR/$(basename "$f") ]]; then run rm "$BIN_DIR/$(basename "$f")"; fi
  done
  for f in "$REPO"/systemd/user/*; do
    if [[ -L $UNIT_DIR/$(basename "$f") ]]; then run rm "$UNIT_DIR/$(basename "$f")"; fi
  done
  for f in "$REPO"/share/applications/*; do
    if [[ -e $APP_DIR/$(basename "$f") ]]; then run rm "$APP_DIR/$(basename "$f")"; fi
  done
  run rm -rf "$CONF_DIR"
  run systemctl --user daemon-reload
  info "Sunshine's own config was left in place (backups: $SUN_DIR/*.bak-*)."
  info "To start Sunshine at login again: systemctl --user enable $SUNSHINE_UNIT"
  say "System side (sudo)"
  remove_tv_session
  sudo_run systemctl disable --now sunshine-wol.socket sunshine-resume.service 2>/dev/null || true
  sudo_run rm -f /etc/systemd/system/sunshine-wol.socket /etc/systemd/system/sunshine-wol.service \
    /etc/systemd/system/sunshine-resume.service "$SYS_ENV"
  sudo_run rm -rf "$SYS_LIB"
  sudo_run systemctl daemon-reload
  firewall_rules delete || true
  if [[ -n ${NM_CONNECTION:-} ]]; then sudo_run nmcli connection modify "$NM_CONNECTION" 802-3-ethernet.wake-on-lan default; fi
  say "Done. Extras (LG renewal timer, RDR2 wrapper) are removed separately - see their READMEs."
}

[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0   # sourced (tests): define functions only

case "${1:-}" in
  configure) shift; cmd_configure "$@" ;;
  install)   shift; cmd_install "$@" ;;
  setcap)    shift; [[ ${1:-} == --dry-run ]] && DRY=yes; cmd_setcap ;;
  extra)     shift; cmd_extra "$@" ;;
  status)    cmd_status ;;
  uninstall) shift; cmd_uninstall "$@" ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
