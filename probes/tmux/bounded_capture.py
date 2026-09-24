#!/usr/bin/env python3
"""Private tmux pipe-pane probe. Never prints captured bytes."""

import os
import shlex
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

TMUX = os.environ.get("TERMEX_TMUX_BIN", "/opt/homebrew/bin/tmux")


def create_private(path):
    return os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)


def marker(path):
    os.close(create_private(path))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sink(segment, ready, gap, clean_eof, limit):
    paths = [Path(value) for value in (segment, ready, gap, clean_eof)]
    root = paths[0].parent
    info = os.stat(root, follow_symlinks=False)
    require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid() and info.st_mode & 0o077 == 0,
            "private recorder directory required")
    require(all(path.is_absolute() and path.parent == root for path in paths), "invalid recorder path")
    require(1 <= limit <= 1_048_576, "invalid recorder limit")
    fd = create_private(segment)
    try:
        marker(ready)  # The pipe reader has opened its private segment before workload starts.
        written = 0
        lost = False
        marked = False
        while chunk := os.read(0, 8192):
            if not lost:
                remaining = max(0, limit - written)
                pending = memoryview(chunk[:remaining])
                while pending:
                    try:
                        count = os.write(fd, pending)
                    except OSError:
                        lost = True
                        break
                    if count <= 0:
                        lost = True
                        break
                    written += count
                    pending = pending[count:]
                if len(chunk) > remaining:
                    lost = True
            if lost and not marked:
                try:
                    marker(gap)
                    marked = True
                except OSError:
                    pass  # Missing gap and clean-EOF markers mean unknown coverage.
        if not lost:
            marker(clean_eof)
    finally:
        os.close(fd)


def wait_for(predicate, label):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.02)
    raise TimeoutError(label)


def fixture(command, expected, limit, overflow):
    with tempfile.TemporaryDirectory(prefix="te-capture-", dir="/tmp") as directory:
        root = Path(directory)
        os.chmod(root, 0o700)
        socket = root / "socket"
        segment, ready, gap, clean_eof = (root / name for name in ("segment", "ready", "gap", "clean_eof"))

        def mux(*args):
            result = subprocess.run([TMUX, "-S", str(socket), "-f", "/dev/null", *args],
                                    check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                    text=True, timeout=5)
            return result.stdout.strip()

        try:
            pane = mux("new-session", "-d", "-P", "-F", "#{pane_id}", "-s", "te-capture", "/bin/sleep", "3600")
            require(pane.startswith("%"), "invalid pane ID")
            mux("set-option", "-p", "-t", pane, "remain-on-exit", "on")
            sink_args = [sys.executable, str(Path(__file__).resolve()), "--sink",
                         str(segment), str(ready), str(gap), str(clean_eof), str(limit)]
            require(all("#{" not in arg and "#(" not in arg for arg in sink_args),
                    "tmux format token in recorder path")
            sink_command = shlex.join(sink_args)
            mux("pipe-pane", "-O", "-t", pane, sink_command)
            wait_for(ready.exists, "recorder readiness")
            require(mux("display-message", "-p", "-t", pane, "#{pane_pipe}") == "1",
                    "recorder pipe not attached")
            mux("respawn-pane", "-k", "-t", pane, command)
            if overflow:
                wait_for(gap.exists, "quota gap")
                require(not clean_eof.exists(), "clean EOF despite quota gap")
                require(segment.stat().st_size == limit, "incorrect quota boundary")
            else:
                wait_for(lambda: segment.exists() and segment.stat().st_size == len(expected), "exact bytes")
                require(segment.read_bytes() == expected, "captured bytes differ")
                require(not gap.exists(), "unexpected capture gap")
            mux("kill-session", "-t", "=te-capture")
            if not overflow:
                wait_for(clean_eof.exists, "clean EOF marker")
        finally:
            subprocess.run([TMUX, "-S", str(socket), "kill-server"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)


if __name__ == "__main__":
    if len(sys.argv) == 7 and sys.argv[1] == "--sink":
        sink(*sys.argv[2:6], int(sys.argv[6]))
    elif len(sys.argv) == 1:
        corpus = b"A\rB\x1b[31mC\x1b[0m\xe2\x82\xac\n"
        fixture(r"stty -echo -onlcr; printf 'A\rB\033[31mC\033[0m\342\202\254\n'; sleep 2",
                corpus, 1024, False)
        fixture("stty -echo -onlcr; printf '%0200d' 0; sleep 2", b"", 64, True)
        print("ready_before_workload=PASS exact_pty_bytes=PASS quota_gap=PASS")
    else:
        raise SystemExit("usage: bounded_capture.py [--sink segment ready gap clean_eof limit]")
