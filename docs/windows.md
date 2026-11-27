# Windows host (experimental, untested)

> **Status:** this project's automation is Linux-only. This guide is the Windows equivalent of each feature, assembled from Sunshine/Apollo docs and community reports. **None of it has been tested by this project yet.** Reports are welcome. The Claude Code plugin walks you through these steps; it gives you each admin command to run, because it can't elevate itself.

## What's the same, what's different
| Feature | Linux (this project) | Windows |
|---|---|---|
| Moonlight client, pairing, bitrate | same | same |
| Wake-on-LAN from sleep / power-off | ✅ | ✅ with the NIC + Fast Startup settings below |
| Sunshine only when needed | on demand + idle stop | Sunshine runs as an **always-on Windows service** (normal on Windows) |
| Cold boot without typing a password | TV session | no direct equivalent; see [Login after a cold boot](#login-after-a-cold-boot) |
| Display switching to the TV resolution | `sunshine-display-mode` | Sunshine's **display device** settings, or Apollo's virtual display |
| Firewall limited to the TV | ufw/firewalld | `New-NetFirewallRule` (below) |
| Steam window fix, sleep inhibit, unlock helper | ✅ | not needed / not available |

## 1. Install the host
**Sunshine** (winget): `winget install LizardByte.Sunshine`. It installs as a service and starts at boot.

Alternative: **[Apollo](https://github.com/ClassicOldSong/Apollo)**, a Windows-focused Sunshine fork with a built-in **virtual display** that matches the client's resolution and HDR automatically. Moonlight works with it, but enable all of the client's permissions in Apollo after pairing.

## 2. Wake-on-LAN
In an **admin PowerShell**, Claude gives you these one at a time:
```powershell
Get-NetAdapter -Physical | Where-Object Status -eq Up          # find your Ethernet adapter name
Get-NetAdapterAdvancedProperty -Name "Ethernet" | Where-Object DisplayName -match "Wake|WOL"
Set-NetAdapterAdvancedProperty -Name "Ethernet" -DisplayName "Wake on Magic Packet" -DisplayValue "Enabled"
# Realtek: also "Shutdown Wake-On-Lan" = Enabled; Intel: "Wake on Magic Packet from power off state"
powercfg /deviceenablewake "<adapter description from Get-NetAdapter>"
# Fast Startup breaks Wake-on-LAN from shutdown - turn it off:
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f
```
Then enable it in the **BIOS/UEFI** (vendor table in [linux.md](linux.md#3-wake-on-lan-in-the-biosuefi)). Property names differ per driver, so check the list from the second command. Updating the NIC driver often helps.

## 3. Firewall: local network only
Only the paired TV can stream (pairing certificate), so it's enough to keep Sunshine off the internet; the TV may then change IP or switch between cable and Wi-Fi.
```powershell
New-NetFirewallRule -DisplayName "Sunshine LAN (TCP)" -Direction Inbound -Protocol TCP -LocalPort 47984,47989,48010 -RemoteAddress LocalSubnet -Profile Private -Action Allow
New-NetFirewallRule -DisplayName "Sunshine LAN (UDP)" -Direction Inbound -Protocol UDP -LocalPort 47998-48000 -RemoteAddress LocalSubnet -Profile Private -Action Allow
```
Mark your home network as **Private** in Windows. Stricter: `-RemoteAddress <TV IP>` instead of `LocalSubnet` (breaks when the TV's IP changes).
The Sunshine installer may already have added broad rules. Review them in "Windows Defender Firewall with Advanced Security", and limit or remove the ones open to everything.

## 4. Sunshine settings (web UI, https://localhost:47990)
- **Input:** disable keyboard/mouse from clients if the controller is on the PC (same idea as `BLOCK_CLIENT_*` on Linux).
- **Encryption:** require encryption on the LAN.
- **Web UI:** allow access from this PC only.
- **Display:** in the **Audio/Video → Display device** options, let Sunshine change the resolution **automatically** to the client's. Moonlight's **"Optimize game settings"** must be enabled for this. With Apollo, use its virtual display instead.
- **Apps:** keep only **Steam Big Picture** if you want the TV limited to that.

## Login after a cold boot
Windows boots to the sign-in screen, and Sunshine runs as a service even there. Options:
1. **Sign in through the stream:** Sunshine's default capture (WGC) **can't** show the lock/sign-in screen; DDX capture reportedly can (community tools switch automatically). Then you type your PIN with Moonlight's on-screen keyboard. **Untested.**
2. **Auto sign-in + lock:** Sysinternals **Autologon** (stores the password encrypted), plus a scheduled task "at log on" that runs `rundll32.exe user32.dll,LockWorkStation`. This weakens security: the account signs in without a password at every boot, and is only locked moments later.
3. **Use sleep instead of shutdown.** Wake from sleep keeps you signed in; the screen is just locked, which brings you back to option 1.

## Not available on Windows (yet)
- The locked "TV session" kiosk.
- Starting Sunshine on demand + idle stop. Sunshine stays a service; you can set it to manual and start it via the Wake listener, but that's not implemented here.
- Automatic unlock for a paired stream.
- `setup.sh`.

**macOS** is not supported: Sunshine on macOS is experimental and has no gamepad support.
