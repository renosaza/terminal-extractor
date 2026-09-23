#!/usr/bin/env python3
"""Exercise the project-local Swift SDK probe over MCP stdio."""

import json
import select
import subprocess
from pathlib import Path


binary = Path(__file__).parent / ".build/release/TermexMCPProbe"
process = subprocess.Popen([str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, bufsize=0)


def request(message):
    process.stdin.write(json.dumps(message, separators=(",", ":")).encode() + b"\n")
    process.stdin.flush()
    if "id" not in message:
        return None
    if not select.select([process.stdout], [], [], 5)[0]:
        raise AssertionError("MCP response timed out")
    response = json.loads(process.stdout.readline())
    assert response["id"] == message["id"], response
    return response


try:
    initialized = request({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2026-07-28", "capabilities": {},
        "clientInfo": {"name": "termex-feasibility", "version": "0.0.0"}}})
    assert initialized["result"]["protocolVersion"] == "2025-11-25", initialized
    request({"jsonrpc": "2.0", "method": "notifications/initialized"})
    listed = request({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
    assert [tool["name"] for tool in listed["result"]["tools"]] == ["probe_accept"]
    called = request({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {
        "name": "probe_accept", "arguments": {"text": "x" * 100_000}}})
    assert called["result"]["structuredContent"] == {"ok": True}, called
    assert len(json.dumps(called)) < 1024, "tool result exceeded the probe bound"
    print("protocol=2025-11-25 tools/list=PASS structured_output=PASS bounded_output=PASS")
finally:
    process.stdin.close()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.terminate()
        process.wait(timeout=5)
    if process.returncode:
        raise AssertionError(f"MCP server exit {process.returncode}: {process.stderr.read()[-1000:]!r}")
