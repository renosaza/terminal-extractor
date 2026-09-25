#!/usr/bin/env python3
"""Check tmux read-only attach with two synthetic PTY clients."""

import fcntl
import os
import pty
import shlex
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path


TMUX = os.environ.get("TERMEX_TMUX_BIN", "/opt/homebrew/bin/tmux")
SESSION = "te-read-only-clients"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def wait_for(predicate, message):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.02)
    raise TimeoutError(message)


def fixture(path):
    # All input is synthetic; no pane bytes are sent to the probe's stdout.
    with open(path, "ab", buffering=0) as output:
        output.write(b"READY\n")
        while line := sys.stdin.buffer.readline():
            output.write(line)


def probe():
    with tempfile.TemporaryDirectory(prefix="te-read-only-") as directory:
        os.chmod(directory, 0o700)
        socket = str(Path(directory) / "socket")
        evidence = Path(directory) / "input"
        clients = []

        def mux(*args):
            result = subprocess.run([TMUX, "-S", socket, "-f", "/dev/null", *args],
                                    check=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.DEVNULL, text=True, timeout=5)
            return result.stdout.strip()

        def attach(rows, columns, flags=None):
            master, slave = pty.openpty()
            tty = os.ttyname(slave)
            try:
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))

                def controlling_tty():
                    os.setsid()
                    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

                process = subprocess.Popen(
                    [TMUX, "-S", socket, "-f", "/dev/null", "attach-session",
                     *(["-f", flags] if flags else []), "-t", "=" + SESSION],
                    stdin=slave, stdout=slave, stderr=slave, preexec_fn=controlling_tty,
                    close_fds=True, env={**os.environ, "TERM": "xterm-256color"})
            except BaseException:
                os.close(master)
                raise
            finally:
                os.close(slave)
            clients.append((process, master, tty))
            return master, tty

        try:
            command = shlex.join([sys.executable, str(Path(__file__).resolve()),
                                  "--fixture", str(evidence)])
            mux("new-session", "-d", "-s", SESSION, command)
            mux("set-option", "-g", "status", "off")
            wait_for(lambda: evidence.exists() and evidence.read_bytes() == b"READY\n",
                     "fixture did not start")

            normal, normal_tty = attach(24, 80)
            window_size = lambda: mux("list-windows", "-t", "=" + SESSION,
                                      "-F", "#{window_width}x#{window_height}")
            try:
                wait_for(lambda: window_size() == "80x24", "normal client did not set window size")
            except TimeoutError:
                raise RuntimeError(f"normal client window size={window_size()}") from None
            readonly, readonly_tty = attach(10, 20, "read-only,ignore-size")

            def clients_match():
                lines = mux("list-clients", "-F", "#{client_tty}\t#{client_readonly}").splitlines()
                modes = dict(line.split("\t", 1) for line in lines)
                return modes.get(normal_tty) == "0" and modes.get(readonly_tty) == "1"

            wait_for(clients_match, "both client modes were not observed")
            require(window_size() == "80x24",
                    f"read-only client window size={window_size()}")
            os.write(normal, b"NORMAL_1\n")
            wait_for(lambda: evidence.read_bytes() == b"READY\nNORMAL_1\n",
                     "normal client input did not reach pane")
            os.write(readonly, b"READ_ONLY\n")
            time.sleep(0.3)
            require(evidence.read_bytes() == b"READY\nNORMAL_1\n",
                    "read-only client input reached pane")
            os.write(normal, b"NORMAL_2\n")
            wait_for(lambda: evidence.read_bytes() == b"READY\nNORMAL_1\nNORMAL_2\n",
                     "normal client stopped delivering input")
            time.sleep(0.3)
            require(evidence.read_bytes() == b"READY\nNORMAL_1\nNORMAL_2\n",
                    "read-only client input reached pane later")
            require(window_size() == "80x24", "read-only client changed window size later")
        finally:
            for _, _, tty in clients:
                try:
                    mux("detach-client", "-t", tty)
                except (OSError, subprocess.SubprocessError):
                    pass
            try:
                mux("kill-session", "-t", "=" + SESSION)
            except (OSError, subprocess.SubprocessError):
                pass
            for process, master, _ in clients:
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    process.wait(timeout=2)
                finally:
                    os.close(master)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--fixture":
        fixture(sys.argv[2])
    elif len(sys.argv) == 1:
        try:
            probe()
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            print(f"read_only_clients=FAIL ({type(error).__name__}: {error})", file=sys.stderr)
            raise SystemExit(1) from None
        print("normal_client_input=PASS read_only_client_blocked=PASS client_modes=PASS geometry=PASS")
    else:
        raise SystemExit("usage: read_only_clients.py")
