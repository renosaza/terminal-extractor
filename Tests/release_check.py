#!/usr/bin/env python3
"""Compile a synthetic check against production host grant and gateway channel code."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="termex-release-check-") as directory:
    binary = Path(directory) / "check"
    subprocess.run([
        "swiftc", "-emit-library", "-emit-module", "-module-name", "TermexCore",
        "-package-name", "terminal-extractor",
        *(str(path) for path in sorted((root / "Sources/TermexCore").glob("*.swift"))),
        "-emit-module-path", str(Path(directory) / "TermexCore.swiftmodule"),
        "-o", str(Path(directory) / "libTermexCore.dylib"),
    ], check=True)
    subprocess.run([
        "swiftc", "-I", directory, "-L", directory, "-lTermexCore",
        str(root / "Sources/TermexHost/ConsentFlow.swift"),
        str(root / "Sources/TermexMCP/HostChannel.swift"),
        str(root / "Tests/ReleaseCheck/main.swift"),
        "-o", str(binary),
    ], check=True)
    subprocess.run([binary], check=True, timeout=15)

# Real MCP gateway, synthetic consent replies only: no native UI or terminal access.
import json
import os
import select
import socket
import struct
import threading
import uuid

with tempfile.TemporaryDirectory(prefix="termex-release-mcp-") as directory:
    path = str(Path(directory) / "host.sock")
    listener = socket.socket(socket.AF_UNIX)
    listener.bind(path)
    os.chmod(path, 0o600)
    listener.listen(1)
    session_id = str(uuid.uuid4()).upper()
    tokens = [str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()]
    releases, reads, failures = [], [], []

    def exact(connection, count):
        data = b""
        while len(data) < count:
            chunk = connection.recv(count - len(data))
            if not chunk:
                raise EOFError()
            data += chunk
        return data

    def host():
        try:
            connection, _ = listener.accept()
            with connection:
                approvals = 0
                while True:
                    length = struct.unpack("!I", exact(connection, 4))[0]
                    request = json.loads(exact(connection, length))
                    operation = request["op"]
                    if operation == "resolve_preferences":
                        reply = {"terminal_app": "ghostty", "attach_policy": "ask", "new_session_backend": "native"}
                    elif operation == "request_ghostty_access":
                        reply = {"status": "approved", "session_id": session_id, "generation": 1,
                                 "scope": "read", "grant_token": tokens[approvals],
                                 "clipboard_export": True, "terminal_access": True}
                        approvals += 1
                    elif operation == "read_ghostty_screen":
                        assert request["session_id"] == session_id and request["generation"] == 1
                        assert request["grant_token"] == tokens[approvals - 1]
                        reads.append(request["view"])
                        if reads.count("scrollback") == 2:
                            reply = {"error": "too_large"}
                        elif reads.count("scrollback") == 3:
                            reply = {"error": "clipboard_unavailable"}
                        else:
                            reply = {"text": "synthetic", "observed_at": "2026-09-24T00:00:00Z",
                                     "source": "ghostty_screen_snapshot" if request["view"] == "screen" else "ghostty_scrollback_snapshot",
                                     "history_complete": False}
                    elif operation == "release_session":
                        assert request["session_id"] == session_id and request["generation"] == 1
                        releases.append(request["grant_token"])
                        reply = {"released": True}
                    elif operation == "ping":
                        reply = {"ok": True}
                    else:
                        raise AssertionError("unexpected IPC operation")
                    data = json.dumps(reply).encode()
                    connection.sendall(struct.pack("!I", len(data)) + data)
        except EOFError:
            pass
        except Exception as error:
            failures.append(type(error).__name__)

    worker = threading.Thread(target=host, daemon=True)
    worker.start()
    environment = {key: value for key, value in os.environ.items() if not key.startswith("TERMEX_")}
    process = subprocess.Popen([root / ".build/debug/termex-mcp", "--socket", path],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, env=environment)
    def rpc(method, params):
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}) + "\n")
        process.stdin.flush()
        assert select.select([process.stdout], [], [], 5)[0], "MCP response timeout"
        return json.loads(process.stdout.readline())["result"]

    def call(name, arguments):
        return rpc("tools/call", {"name": name, "arguments": arguments})

    try:
        rpc("initialize", {"protocolVersion": "2025-11-25", "capabilities": {},
                           "clientInfo": {"name": "release-check", "version": "0"}})
        process.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
        assert call("terminal_request_access", {})["structuredContent"]["status"] == "approved"
        target = {"session_id": session_id, "generation": 1}
        assert call("terminal_screen", target)["structuredContent"]["source"] == "ghostty_screen_snapshot"
        assert call("terminal_screen", {**target, "view": "scrollback"})["structuredContent"]["source"] == "ghostty_scrollback_snapshot"
        oversized = call("terminal_screen", {**target, "view": "scrollback"})
        assert oversized["isError"] and oversized["content"][0]["text"] == "snapshot exceeds 16 KiB"
        clipboard = call("terminal_screen", {**target, "view": "scrollback"})
        assert clipboard["isError"] and clipboard["content"][0]["text"] == "clipboard cannot be preserved for export"
        assert call("terminal_screen", {**target, "view": "invalid"})["isError"]
        assert call("terminal_screen", {**target, "other": True})["isError"]
        assert reads == ["screen", "scrollback", "scrollback", "scrollback"]
        arguments = {"session_id": session_id, "generation": 1, "request_id": "first"}
        first = call("terminal_release", arguments)
        assert first["structuredContent"] == {**arguments, "status": "released"}
        assert not first.get("isError", False)
        assert call("terminal_request_access", {})["structuredContent"]["status"] == "approved"
        assert call("terminal_release", arguments) == first
        assert releases == [tokens[0]], "replay revoked renewed grant"
        conflict = call("terminal_release", {**arguments, "generation": 2})
        assert conflict["structuredContent"]["status"] == "idempotency_conflict"
        assert conflict["isError"]
        final = call("terminal_release", {**arguments, "request_id": "second"})
        assert final["structuredContent"]["status"] == "released"
        assert releases == tokens
        process.stdin.close()
        assert process.wait(timeout=5) == 0
        worker.join(timeout=5)
        assert not worker.is_alive() and not failures
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        listener.close()
print("MCP release replay and screen/scrollback routing with synthetic host: PASS")
