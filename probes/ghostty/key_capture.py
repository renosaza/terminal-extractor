#!/usr/bin/env python3
"""Capture bounded terminal input bytes in a disposable Ghostty surface."""

import json
import os
import select
import sys
import termios
import time

path, seconds = sys.argv[1], max(1, min(int(sys.argv[2]), 90))
fd = sys.stdin.fileno()
original = termios.tcgetattr(fd)
raw = termios.tcgetattr(fd)
raw[0] &= ~(termios.BRKINT | termios.ICRNL | termios.INPCK | termios.ISTRIP | termios.IXON)
raw[1] &= ~termios.OPOST
raw[2] |= termios.CS8
raw[3] &= ~(termios.ECHO | termios.ICANON | termios.IEXTEN | termios.ISIG)
raw[6][termios.VMIN] = 0
raw[6][termios.VTIME] = 0
termios.tcsetattr(fd, termios.TCSANOW, raw)
try:
    output = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(output, "w") as stream:
        print("KEY_CAPTURE_READY", flush=True)
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if select.select([fd], [], [], 0.2)[0]:
                data = os.read(fd, 4096)
                if data:
                    stream.write(json.dumps({"at_ms": int(time.monotonic() * 1000), "hex": data.hex()}) + "\n")
                    stream.flush()
finally:
    termios.tcsetattr(fd, termios.TCSANOW, original)
