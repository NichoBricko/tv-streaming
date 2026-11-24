#!/usr/bin/python3 -I
"""Start Sunshine when Moonlight's "Wake PC" packet arrives.

Socket-activated by sunshine-wol.socket (UDP 9, datagram, Accept=no): the
listening socket is passed in as fd 3. Every pending datagram is read; a
packet starts Sunshine only if

  * it comes from the allowed client IP (the TV), and
  * it is a Wake-on-LAN magic packet (6 x 0xFF + 16 x MAC) for this PC's MAC.

Moonlight TV sends exactly this: a 102-byte broadcast to 255.255.255.255:9
(mariotaku/commons-c net/wol/wol.c). Anything else is logged and ignored.

Runs as the desktop user, so starting the Sunshine *user* service needs no
root privileges.
"""
import os
import socket
import subprocess
import sys

SD_LISTEN_FDS_START = 3

mac = bytes.fromhex(os.environ["WOL_MAC"].replace(":", ""))
allowed_src = os.environ["CLIENT_IP"]
unit = os.environ["SUNSHINE_UNIT"]
if len(mac) != 6:
    sys.exit(f"WOL_MAC must be a 6-byte MAC address, got {os.environ['WOL_MAC']!r}")
expected = b"\xff" * 6 + mac * 16


def log(msg: str) -> None:
    print(msg, flush=True)


def main() -> int:
    if os.environ.get("LISTEN_FDS") != "1":
        log("not socket-activated (LISTEN_FDS != 1); exiting")
        return 1

    sock = socket.socket(fileno=SD_LISTEN_FDS_START)
    sock.setblocking(False)

    wake = False
    while True:
        try:
            data, (src, _port) = sock.recvfrom(2048)
        except BlockingIOError:
            break
        if src != allowed_src:
            log(f"ignored packet from {src}: not the allowed client")
            continue
        if expected not in data:
            log(f"ignored packet from {src}: not a magic packet for this PC")
            continue
        log(f"Wake-on-LAN packet from {src} accepted")
        wake = True

    if not wake:
        return 0

    state = subprocess.run(["systemctl", "--user", "is-active", unit],
                           capture_output=True, text=True).stdout.strip()
    if state == "active":
        log(f"{unit} already running")
        return 0

    result = subprocess.run(["systemctl", "--user", "start", "--no-block", unit],
                            capture_output=True, text=True)
    if result.returncode != 0 and not os.path.exists(f"/run/user/{os.getuid()}/bus"):
        # Nobody logged in yet (PC booted to the login screen): remember the
        # wake; sunshine-login.service starts Sunshine right after login.
        pending = os.path.join(os.environ.get("RUNTIME_DIRECTORY", "/run/sunshine-on-demand"),
                               "wake-pending")
        open(pending, "w").close()
        os.utime(pending)
        log(f"no user session yet; wake remembered in {pending}")
        return 0
    if result.returncode != 0:
        log(f"failed to start {unit}: {result.stderr.strip()}")
        return 1
    log(f"started {unit}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
