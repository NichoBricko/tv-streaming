#!/usr/bin/python3 -I
"""Start Sunshine when Moonlight's "Wake PC" packet arrives.

Socket-activated by sunshine-wol.socket (UDP 9, datagram, Accept=no): the
listening socket is passed in as fd 3. Every pending datagram is read; a
packet starts Sunshine only if

  * it comes from the local network - FIREWALL_SCOPE=lan (default): any private
    IPv4 address, so the TV may use any address, cable or Wi-Fi; FIREWALL_SCOPE=client:
    only the addresses in CLIENT_IP - and
  * it is a Wake-on-LAN magic packet (6 x 0xFF + 16 x MAC) for this PC's MAC.

Moonlight TV sends exactly this: a 102-byte broadcast to 255.255.255.255:9
(mariotaku/commons-c net/wol/wol.c). Anything else is logged and ignored.

Runs as the desktop user, so starting the Sunshine *user* service needs no
root privileges.
"""
import ipaddress
import os
import socket
import subprocess
import sys

SD_LISTEN_FDS_START = 3

mac = bytes.fromhex(os.environ["WOL_MAC"].replace(":", ""))
scope = os.environ.get("FIREWALL_SCOPE", "lan")
client_ips = set(os.environ.get("CLIENT_IP", "").replace(",", " ").split())
PRIVATE = [ipaddress.ip_network(n) for n in
           ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16")]
unit = os.environ["SUNSHINE_UNIT"]
if len(mac) != 6:
    sys.exit(f"WOL_MAC must be a 6-byte MAC address, got {os.environ['WOL_MAC']!r}")
expected = b"\xff" * 6 + mac * 16


def log(msg: str) -> None:
    print(msg, flush=True)


def allowed(src: str) -> bool:
    """A Wake only starts Sunshine (which still needs a paired client), so on
    the LAN scope any private source is fine; IPs are spoofable anyway."""
    if scope == "client":
        return src in client_ips
    try:
        addr = ipaddress.ip_address(src)
    except ValueError:
        return False
    return any(addr in net for net in PRIVATE)


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
        if not allowed(src):
            log(f"ignored packet from {src}: not the allowed client"
                + (" (CLIENT_IP)" if scope == "client" else " (not a private LAN address)"))
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
        # It may be running but broken (no display/encoder found at startup,
        # e.g. right after resume): let the health check restart it if so.
        subprocess.run(["systemctl", "--user", "start", "--no-block",
                        "sunshine-healthcheck.service"], capture_output=True)
        log(f"{unit} already running; health check requested")
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
