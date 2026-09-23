#!/usr/bin/env python3
"""Check host lifetime, bounded IPC rejection, and MCP gateway reconnect."""

import json
import os
import socket
import struct
import subprocess
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parents[2]
host_binary = root / ".build/debug/termex-host"
gateway_binary = root / ".build/debug/termex-mcp"


def exact(connection, count):
    data = b""
    while len(data) < count:
        chunk = connection.recv(count - len(data))
        assert chunk, "socket closed mid-frame"
        data += chunk
    return data


def exchange(path, payload):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(5)
        connection.connect(path)
        connection.sendall(struct.pack("!I", len(payload)) + payload)
        header = exact(connection, 4)
        size = struct.unpack("!I", header)[0]
        return json.loads(exact(connection, size))


def rejected(path, header, body=b""):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(5)
        connection.connect(path)
        connection.sendall(header + body)
        response = exact(connection, 4)
        size = struct.unpack("!I", response)[0]
        assert json.loads(exact(connection, size)) == {"ok": False}


def gateway(path):
    process = subprocess.Popen([gateway_binary, "--socket", path], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-11-25", "capabilities": {},
            "clientInfo": {"name": "integration", "version": "0"}}}) + "\n")
        process.stdin.flush()
        reply = json.loads(process.stdout.readline())
        assert reply["result"]["protocolVersion"] == "2025-11-25", reply
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}) + "\n")
        process.stdin.flush()
        listed = json.loads(process.stdout.readline())
        assert listed["result"]["tools"] == [], listed
        process.stdin.close()
        assert process.wait(timeout=5) == 0, process.stderr.read()
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


with tempfile.TemporaryDirectory(prefix="termex-ipc-") as temporary:
    path = str(Path(temporary) / "host.sock")
    host = subprocess.Popen([host_binary, "--socket", path], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for _ in range(100):
            if Path(path).exists():
                break
            assert host.poll() is None, host.stderr.read().decode()
            time.sleep(0.05)
        assert Path(path).exists()
        assert Path(path).stat().st_mode & 0o077 == 0
        gateway(path)
        assert host.poll() is None
        assert exchange(path, b'{}') == {"ok": False}
        assert exchange(path, b'{"op":"ping"}') == {"ok": True}
        rejected(path, struct.pack("!I", 65537))
        rejected(path, struct.pack("!I", 0))
        gateway(path)
        assert host.poll() is None
        with socket.socket(socket.AF_UNIX) as slow:
            slow.connect(path)
            slow.sendall(struct.pack("!I", 16) + b"x")
            time.sleep(5.2)
            assert exchange(path, b'{"op":"ping"}') == {"ok": True}
        host.terminate()
        assert host.wait(timeout=5) == 0
        assert not Path(path).exists()
        print("host_lifetime=PASS gateway_reconnect=PASS empty_tools=PASS invalid_payload=PASS slow_frame=PASS cleanup=PASS")
    finally:
        if host.poll() is None:
            host.kill()
            host.wait()
