#!/usr/bin/env python3
"""Signal custom Waybar workspace buttons from Hyprland IPC events."""

import os
import signal
import socket
import subprocess
import time


def signal_waybar() -> None:
    subprocess.run(
        ["pkill", "-RTMIN+9", "-x", "waybar"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def main() -> None:
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not signature:
        return
    path = os.path.join(runtime, "hypr", signature, ".socket2.sock")

    while True:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as ipc:
                ipc.connect(path)
                buffer = b""
                while True:
                    chunk = ipc.recv(4096)
                    if not chunk:
                        break
                    buffer += chunk
                    lines = buffer.split(b"\n")
                    buffer = lines.pop()
                    for line in lines:
                        event = line.decode("utf-8", "replace")
                        if event.startswith(("workspace>>", "createworkspace>>", "destroyworkspace>>")):
                            signal_waybar()
        except (ConnectionError, FileNotFoundError, OSError):
            time.sleep(1)


if __name__ == "__main__":
    main()
