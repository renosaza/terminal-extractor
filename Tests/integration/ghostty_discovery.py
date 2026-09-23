#!/usr/bin/env python3
"""Read-only local discovery check; requires a running Ghostty with a surface."""

import json
import subprocess
from pathlib import Path

host = Path(__file__).resolve().parents[2] / ".build/debug/termex-host"
choices = json.loads(subprocess.check_output([host, "--list-ghostty"]))
if not choices:
    print("ghostty_discovery=SKIP (no running surface)")
else:
    keys = ("appInstanceID", "windowID", "tabID", "surfaceID")
    identities = [tuple(choice[key] for key in keys) for choice in choices]
    assert len(set(identities)) == len(identities)
    for choice in choices:
        resolved = json.loads(subprocess.check_output([host, "--resolve-ghostty", *(choice[key] for key in keys)]))
        assert tuple(resolved[key] for key in keys) == tuple(choice[key] for key in keys)
    choice = choices[0]
    stale = subprocess.run([host, "--resolve-ghostty", choice["appInstanceID"], choice["windowID"],
                            choice["tabID"], "missing-surface"], capture_output=True)
    assert stale.returncode != 0 and not stale.stdout
    print(f"ghostty_discovery=PASS exact_choice=PASS stale_choice=PASS choices={len(choices)}")
