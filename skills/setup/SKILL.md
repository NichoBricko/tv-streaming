---
name: setup
description: Set up couch game streaming from the user's PC to their TV with Sunshine + Moonlight (sunshine-on-demand) - one Wake press on the TV starts the PC/Sunshine, a locked "TV session" for cold boots, on-demand Sunshine, firewall limited to the TV, display switching, Steam Big Picture. Interviews the user, detects the PC, checks compatibility, installs (Linux automated, Windows guided), installs Moonlight on the TV (LG webOS / Android TV via adb), pairs and tests.
when_to_use: User wants to stream games from their PC to a TV/streaming box, set up Sunshine/Moonlight, Wake-on-LAN game streaming, or install/update/uninstall sunshine-on-demand.
argument-hint: "[install|update|uninstall]"
---

# sunshine-on-demand setup

You are setting up **sunshine-on-demand** on the user's own PC and TV. The finished result: the user presses **Wake** in Moonlight on the TV. The PC wakes or boots, starts Sunshine (or a locked TV session on a cold boot) and becomes available. Starting "Steam Big Picture" unlocks the session for the stream, and everything is restored and relocked afterwards.

Project files are in `${CLAUDE_PLUGIN_ROOT}`. Read the docs there when a step needs details. Don't guess:
- `docs/compatibility.md`: what works on which host/desktop/client. **Read this before promising anything.**
- `docs/linux.md`: Linux install, BIOS Wake-on-LAN table, desktop support
- `docs/windows.md`: Windows host (experimental, guided)
- `docs/tv-clients.md`: Moonlight per TV platform, adb steps, pairing, standby check
- `docs/how-it-works.md`: components, TV session, security model
- `docs/troubleshooting.md`: symptoms and fixes
- `config.env.example`: every option, documented
- `extras/lg-webos-devmode/README.md`, `extras/rdr2-epic-heroic/README.md`

## Ground rules (always)
1. **Detect read-only first. Change nothing until the user has seen the plan and agreed.** Always run `setup.sh install --dry-run` before installing.
2. **sudo/admin steps: hand them to the user.** You can't answer a password prompt, and the `!` prefix can't either. Give the exact command and ask them to run it **in a separate terminal window** (Konsole, GNOME Terminal…; on Windows, an *admin* PowerShell), then continue once they confirm.
3. **Be honest about status.** Tell the user what's tested (✅), untested (🟡) and unsupported (❌) for *their* setup, from `docs/compatibility.md`. Don't claim untested paths work.
4. **Privacy:** never write the user's IPs, MACs, emails, tokens or keys into the plugin folder or any git repo. `config.env` is per-machine and gitignored.
5. **Existing setups:** if sunshine-on-demand is already installed (`~/.config/sunshine-on-demand/config.env` exists), explain that and offer update or reconfigure. Don't reinstall blindly.
6. **Stop and explain blockers:** for example a PC on Wi-Fi only (no Wake-on-LAN), a TV with no Moonlight client (recommend a box), macOS (unsupported), or Fire TV on Vega OS.

## 1. Interview
Use AskUserQuestion, at most 4 questions per round:
- **Host:** Windows or Linux? (Detect it; just confirm.) Is the PC on **Ethernet**?
- **Client:** which TV or box? (LG, Samsung, Android/Google TV brand, Shield, Apple TV, Fire TV model, other). Its **IP address**. Recommend a DHCP reservation in the router; you can find the device with `ip neigh` / `avahi-browse -art` if needed.
- **Controller:** paired with the **PC** (lowest latency; the TV becomes display-only) or with the **TV**?
- **Cold boot:** should Wake from **power-off** work without typing a password (TV session, KDE only), or is wake from sleep enough?
- **Launcher:** Steam (Big Picture) by default. Heroic/Epic games work as non-Steam shortcuts; see the RDR2 extra for Rockstar/Epic quirks.

## 2. Detect (read-only)
**Linux:**
```bash
. /etc/os-release; echo "$PRETTY_NAME"; echo "$XDG_CURRENT_DESKTOP $XDG_SESSION_TYPE"
systemctl show display-manager.service -p Id --value
for u in app-dev.lizardbyte.app.Sunshine.service sunshine.service; do systemctl --user cat "$u" >/dev/null 2>&1 && echo "sunshine unit: $u"; done
command -v sunshine; flatpak info dev.lizardbyte.app.Sunshine 2>/dev/null | head -2
lspci | grep -Ei 'vga|3d|display'
ip route show default; ip -br link; nmcli -t -f NAME,DEVICE con show --active
systemctl is-active ufw firewalld 2>/dev/null
```
`${CLAUDE_PLUGIN_ROOT}/setup.sh configure` (in step 4) does the rest of the detection.

**Windows:** run read-only PowerShell (`Get-ComputerInfo -Property OsName`, `Get-NetAdapter -Physical`, `winget list LizardByte.Sunshine`, `Get-CimInstance Win32_VideoController`), then follow `docs/windows.md`.

Summarize what works for this setup and what doesn't (per `docs/compatibility.md`), and get a go-ahead.

## 3. Install Sunshine (if missing)
Give the user the right command for their distro from `docs/linux.md` (they run it, since it needs sudo). Then confirm with `systemctl --user start <unit>` and `systemctl --user is-active <unit>`.

## 4. Linux: install sunshine-on-demand
1. **Copy the project to a stable folder.** The plugin folder changes on updates, and installed symlinks point into this copy:
   ```bash
   D=~/.local/share/sunshine-on-demand; mkdir -p "$D"
   rsync -a --delete --exclude .git --exclude config.env "${CLAUDE_PLUGIN_ROOT}/" "$D/" \
     || (cd "${CLAUDE_PLUGIN_ROOT}" && tar --exclude=.git --exclude=config.env -cf - . | tar -C "$D" -xf -)
   ```
2. `cd ~/.local/share/sunshine-on-demand && ./setup.sh configure --client-ip <IP>`. Show the "Detected" summary.
3. **Edit `config.env`** with the interview answers:
   - `BLOCK_CLIENT_CONTROLLER` (yes if the controller is on the PC);
   - `TV_SESSION="yes"` for cold boot (KDE + Plasma Login Manager/SDDM only);
   - `APP_OPEN_CMD`/`STEAM_CMD` for Flatpak Steam.

   Explain each change briefly.
4. `./setup.sh install --dry-run`: walk the user through it.
5. `./setup.sh install --user` (no sudo, you run it).
6. **User runs in their terminal:** `~/.local/share/sunshine-on-demand/setup.sh install --system`. This covers the system units, the firewall limited to the TV, Wake-on-LAN on the network card, the TV session, and setcap.
7. **BIOS/UEFI:** give them their board vendor's Wake-on-LAN setting from `docs/linux.md`. This needs a reboot into the firmware setup, so they can do it later.

## 5. Client (TV)
Follow `docs/tv-clients.md` for their platform:
- **Android/Google TV, Fire OS:**
  - guide them through enabling developer options;
  - then you run `adb connect` / `adb install` with the moonlight-android release APK. Download it to its own empty folder and check the release page;
  - remind them to turn developer options off afterwards.
- **LG webOS:**
  - they enable Developer Mode + Key Server;
  - you install `@webos-tools/cli` with `npm install -g --prefix ~/.local` (needs nodejs/npm), `ares-setup-device`, `ares-novacom --getkey` (they tell you the passphrase), then `ares-install` of the Moonlight TV release `.ipk` (verify the sha256);
  - then `./setup.sh extra lg-webos-devmode` for the daily renewal.
- **Samsung Tizen:** guide them through the project's installation guide (Apps2Samsung).
- **Apple TV / Fire OS Appstore:** they install it from the store.
- **No client available** (VIDAA, Roku, Vega OS): recommend a box from the table and stop here.

Moonlight settings: bitrate ≤ 65 Mbps on 100 Mb/s Ethernet (most TVs), 80–150 on gigabit; 4K60; HEVC.

## 6. Pair, then the standby check
1. `sunshine-on-demand start`. The user opens https://localhost:47990, creates a login, and enters the PIN Moonlight shows.
2. **Standby check**, only if `TV_SESSION=yes`:
   - the user puts the TV in standby and waits 30 s; you run `ping -c3 <IP>`;
   - **no reply** → keep `TV_AUTOLOGIN="auto"` (one press);
   - **replies** → suggest turning off Quick Start+/Instant On/network standby, or set `TV_AUTOLOGIN="on-wake"`, and the user re-runs `install --system`.
3. If the TV session is used: on the TV, turn off automatic content recognition (privacy).

## 7. Test with the user, in order
1. **Wake while awake:** `sunshine-on-demand stop`, then Wake in Moonlight → online within ~10–20 s.
2. **Stream** Steam Big Picture → the display switches, the controller works → quit → the display is restored.
3. **Wake from sleep.**
4. **Cold boot** (TV session): shut down, then press Wake once and wait. Expect the locked TV session ~15 s after power-on. Then the **power button with the TV off** → the normal login screen.

After each test, read `./setup.sh status` / `./setup.sh report` (use `report -1` after a reboot) and explain what happened. Problems → follow the `troubleshoot` skill / `docs/troubleshooting.md`.

## Update / uninstall
- **Update:** re-run the rsync in step 4.1, then `./setup.sh install --user`, and the user runs `install --system`. `config.env` is kept.
- **Uninstall:** `./setup.sh uninstall --dry-run`, then the user runs `./setup.sh uninstall` (it asks for sudo). Extras are removed per their READMEs.
