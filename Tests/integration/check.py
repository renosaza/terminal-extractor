#!/usr/bin/env python3
"""Check host lifetime, bounded IPC rejection, and MCP gateway reconnect."""

import json
import os
import select
import socket
import struct
import subprocess
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parents[2]
host_binary = root / ".build/debug/termex-host"
gateway_binary = root / ".build/debug/termex-mcp"
consent_binary = root / ".build/debug/termex-consent"
clean_environment = {key: value for key, value in os.environ.items() if not key.startswith("TERMEX_")}


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


def stop(path):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(5)
        connection.connect(path + ".stop")
        size = struct.unpack("!I", exact(connection, 4))[0]
        return json.loads(exact(connection, size))


def rejected(path, header, body=b""):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(5)
        connection.connect(path)
        connection.sendall(header + body)
        response = exact(connection, 4)
        size = struct.unpack("!I", response)[0]
        assert json.loads(exact(connection, size)) == {"ok": False}


def gateway(path, preferences=None, request_access=False):
    environment = clean_environment.copy()
    environment.update(preferences or {})
    process = subprocess.Popen([gateway_binary, "--socket", path], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                               env=environment)
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
        assert [tool["name"] for tool in listed["result"]["tools"]] == ["terminal_capabilities", "terminal_request_access", "terminal_release", "terminal_screen"], listed
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {
            "name": "terminal_capabilities", "arguments": {}}}) + "\n")
        process.stdin.flush()
        capability = json.loads(process.stdout.readline())["result"]["structuredContent"]
        expected = {
            "runtime": "foundation", "terminal_access": False,
            "terminal_app": (preferences or {}).get("TERMEX_TERMINAL", "terminal"),
            "attach_policy": (preferences or {}).get("TERMEX_ATTACH_POLICY", "ask"),
            "new_session_backend": (preferences or {}).get("TERMEX_NEW_BACKEND", "managed_tmux"),
        }
        assert capability == expected, capability
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {
            "name": "terminal_screen", "arguments": {
                "session_id": "11111111-1111-4111-8111-111111111111", "generation": 1}}}) + "\n")
        process.stdin.flush()
        assert json.loads(process.stdout.readline())["result"]["isError"] is True
        target = {"session_id": "11111111-1111-4111-8111-111111111111", "generation": 1, "request_id": "release-1"}
        invalid_releases = [
            {}, {**target, "session_id": "invalid"}, {**target, "generation": 0},
            {**target, "generation": True}, {**target, "request_id": ""},
            {**target, "request_id": "x" * 129}, {**target, "extra": True},
        ]
        for release_index, arguments in enumerate(invalid_releases + [target, target, {**target, "generation": 2}]):
            process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": {
                "name": "terminal_release", "arguments": arguments}}) + "\n")
            process.stdin.flush()
            result = json.loads(process.stdout.readline())["result"]
            assert result["isError"] is True, result
            if release_index in [len(invalid_releases), len(invalid_releases) + 1]:
                assert result["structuredContent"] == {**target, "status": "denied"}, result
            elif release_index == len(invalid_releases) + 2:
                assert result["structuredContent"]["status"] == "idempotency_conflict", result
        if request_access:
            process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {
                "name": "terminal_request_access", "arguments": {}}}) + "\n")
            process.stdin.flush()
            selection = json.loads(process.stdout.readline())["result"]["structuredContent"]
            assert selection == {"status": "no_sessions"}, selection
        process.stdin.close()
        assert process.wait(timeout=5) == 0, process.stderr.read()
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


with tempfile.TemporaryDirectory(prefix="termex-ipc-") as temporary:
    path = str(Path(temporary) / "host.sock")
    config_path = Path(temporary) / "config.json"
    missing = subprocess.run([host_binary, "--socket", path, "--config", str(config_path)],
                             stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert missing.returncode != 0 and not Path(path).exists()
    config_path.write_text('{"schema_version":1,"allowed_apps":["terminal","ghostty"]}')
    config_path.chmod(0o600)
    host = subprocess.Popen([host_binary, "--socket", path, "--config", str(config_path)], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for _ in range(100):
            if Path(path).exists() and Path(path + ".stop").exists():
                break
            assert host.poll() is None, host.stderr.read().decode()
            time.sleep(0.05)
        assert Path(path).exists()
        assert Path(path + ".stop").exists()
        assert Path(path).stat().st_mode & 0o077 == 0
        assert Path(path + ".stop").stat().st_mode & 0o077 == 0
        assert Path(path).stat().st_uid == os.getuid()
        assert Path(path + ".stop").stat().st_uid == os.getuid()
        gateway(path)
        assert host.poll() is None
        gateway(path, {"TERMEX_TERMINAL": "ghostty", "TERMEX_ATTACH_POLICY": "existing",
                       "TERMEX_NEW_BACKEND": "native"})
        denied = subprocess.run([gateway_binary, "--socket", path], stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env={**clean_environment, "TERMEX_ALLOWED_APPS": "ghostty"})
        assert denied.returncode != 0 and not denied.stdout
        probe_path = str(Path(temporary) / "probe.sock")
        with socket.socket(socket.AF_UNIX) as probe:
            probe.bind(probe_path)
            probe.listen(1)
            denied = subprocess.run([gateway_binary, "--socket", probe_path], stdin=subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    env={**clean_environment, "TERMEX_SECRET": "must-not-cross-ipc"})
            assert denied.returncode != 0 and not denied.stdout
            assert not select.select([probe], [], [], 0)[0], "unknown env reached IPC"
        assert exchange(path, b'{}') == {"ok": False}
        assert exchange(path, b'{"op":"ping","clientInfo":{"name":"trusted"}}') == {"ok": False}
        assert exchange(path, b'{"op":"ping"}') == {"ok": True}
        assert exchange(path, b'{"op":"access_status"}') == {"sessions": []}
        assert exchange(path, b'{"op":"read_ghostty_screen","session_id":"11111111-1111-4111-8111-111111111111","generation":1,"grant_token":"22222222-2222-4222-8222-222222222222"}') == {"ok": False}
        for invalid_generation in [True, 1.0, 1.5]:
            payload = json.dumps({"op": "release_session", "session_id": "11111111-1111-4111-8111-111111111111",
                                  "generation": invalid_generation, "grant_token": "22222222-2222-4222-8222-222222222222"}).encode()
            assert exchange(path, payload) == {"ok": False}
        first_stop = stop(path)
        second_stop = stop(path)
        assert first_stop == {"stopped": True, "epoch": 1}, first_stop
        assert second_stop == {"stopped": True, "epoch": 2}, second_stop
        assert exchange(path, b'{"op":"access_status"}') == {"sessions": []}
        stopped = subprocess.run([host_binary, "--stop", "--socket", path], capture_output=True, text=True)
        assert stopped.returncode == 0 and stopped.stdout == "Access revoked\n", stopped
        assert stop(path) == {"stopped": True, "epoch": 4}
        invalid_consent = subprocess.run([consent_binary], input=b'{}', capture_output=True, timeout=5)
        assert invalid_consent.returncode == 0 and json.loads(invalid_consent.stdout) == {"cancelled": True}
        with socket.socket(socket.AF_UNIX) as persistent:
            persistent.settimeout(5)
            persistent.connect(path)
            for _ in range(2):
                message = b'{"op":"ping"}'
                persistent.sendall(struct.pack("!I", len(message)) + message)
                size = struct.unpack("!I", exact(persistent, 4))[0]
                assert json.loads(exact(persistent, size)) == {"ok": True}
            assert exchange(path, b'{"op":"ping"}') == {"ok": True}
        with socket.socket(socket.AF_UNIX) as half_closed:
            half_closed.settimeout(5)
            half_closed.connect(path)
            message = b'{"op":"ping"}'
            half_closed.sendall(struct.pack("!I", len(message)) + message)
            half_closed.shutdown(socket.SHUT_WR)
            size = struct.unpack("!I", exact(half_closed, 4))[0]
            assert json.loads(exact(half_closed, size)) == {"ok": True}
        holders = []
        try:
            for _ in range(8):
                connection = socket.socket(socket.AF_UNIX)
                connection.settimeout(5)
                connection.connect(path)
                holders.append(connection)
                message = b'{"op":"ping"}'
                connection.sendall(struct.pack("!I", len(message)) + message)
                size = struct.unpack("!I", exact(connection, 4))[0]
                assert json.loads(exact(connection, size)) == {"ok": True}
            with socket.socket(socket.AF_UNIX) as excess:
                excess.settimeout(5)
                excess.connect(path)
                assert excess.recv(1) == b"", "ninth client was not rejected"
            assert stop(path) == {"stopped": True, "epoch": 5}, "Stop was blocked by eight clients"
            for connection in holders:
                assert connection.recv(1) == b"", "Stop left a client connected"
        finally:
            for connection in holders:
                connection.close()
        with socket.socket(socket.AF_UNIX) as active:
            active.settimeout(5)
            active.connect(path)
            active.sendall(struct.pack("!I", 16) + b"x")
            started = time.monotonic()
            assert stop(path) == {"stopped": True, "epoch": 6}
            assert time.monotonic() - started < 3, "partial request delayed Stop"
            assert active.recv(1) == b"", "Stop left an active client connected"
        for attempt in range(20):
            try:
                assert exchange(path, b'{"op":"ping"}') == {"ok": True}
                break
            except (OSError, AssertionError):
                if attempt == 19:
                    raise
                time.sleep(0.05)
        rejected(path, struct.pack("!I", 65537))
        rejected(path, struct.pack("!I", 0))
        gateway(path)
        assert host.poll() is None
        with socket.socket(socket.AF_UNIX) as slow:
            slow.connect(path)
            slow.sendall(struct.pack("!I", 16) + b"x")
            time.sleep(5.2)
            assert exchange(path, b'{"op":"ping"}') == {"ok": True}
        with socket.socket(socket.AF_UNIX) as partial:
            partial.settimeout(5)
            partial.connect(path)
            message = b'{"op":"ping"}'
            partial.sendall(struct.pack("!I", len(message)) + message)
            size = struct.unpack("!I", exact(partial, 4))[0]
            assert json.loads(exact(partial, size)) == {"ok": True}
            partial.sendall(struct.pack("!I", 16) + b"x")
            time.sleep(0.3)
            started = time.monotonic()
            host.terminate()
            assert host.wait(timeout=3) == 0
            assert time.monotonic() - started < 3, "partial client delayed host stop"
        assert not Path(path).exists()
        assert not Path(path + ".stop").exists()
        config_path.write_text('{"schema_version":1,"allowed_apps":["terminal"]}')
        config_path.chmod(0o600)
        restricted = subprocess.Popen([host_binary, "--socket", path, "--config", str(config_path)],
                                      stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                if Path(path).exists() and Path(path + ".stop").exists():
                    break
                assert restricted.poll() is None
                time.sleep(0.05)
            assert Path(path).exists()
            rejected_app = subprocess.run([gateway_binary, "--socket", path], stdin=subprocess.DEVNULL,
                                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                          env={**clean_environment, "TERMEX_TERMINAL": "ghostty"})
            assert rejected_app.returncode != 0 and not rejected_app.stdout
            gateway(path, request_access=True)
            assert exchange(path, b'{"op":"request_ghostty_access"}') == {"status": "no_sessions"}
            restricted.terminate()
            assert restricted.wait(timeout=5) == 0
        finally:
            if restricted.poll() is None:
                restricted.kill()
                restricted.wait()
        print("host_lifetime=PASS persistent_client=PASS client_limit=PASS fast_stop=PASS local_revoke=PASS gateway_reconnect=PASS capabilities=PASS env_policy=PASS peer_owner=PASS no_env_leak=PASS invalid_payload=PASS slow_frame=PASS cleanup=PASS")
    finally:
        if host.poll() is None:
            host.kill()
            host.wait()
