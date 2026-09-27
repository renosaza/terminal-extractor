#!/usr/bin/env python3
"""Reject malformed consent requests without opening AppKit UI."""

import json
import subprocess
from pathlib import Path

binary = Path(__file__).resolve().parents[2] / ".build/debug/termex-consent"
nonce = "DD327E2D-17E5-4025-AEB1-BC4DDE19DEAE"
handle = "B4B6E8D3-5552-47CC-8206-1005129BDA98"

invalid = [
    b"{}",
    b"{",
    b"[]",
    b'{"kind":"other","nonce":"' + nonce.encode() + b'"}',
    b'{"kind":"terminal_managed_new","nonce":"invalid"}',
    b'{"kind":"terminal_managed_new","nonce":"' + nonce.encode() + b'","choices":[]}',
    b'{"title":"Pick","choices":[{"handle":"' + handle.encode() + b'","label":"Pane","extra":"value"}]}',
    b'{"title":"Pick","choices":[],"kind":"terminal_managed_new","nonce":"' + nonce.encode() + b'"}',
    b" " * (64 * 1024 + 1),
]

for request in invalid:
    result = subprocess.run([binary], input=request, capture_output=True, timeout=5)
    assert result.returncode == 0, (request[:100], result)
    assert json.loads(result.stdout) == {"cancelled": True}, request[:100]

print("consent invalid/cancelled input: OK; approval UI: NOT_RUN")
