#!/usr/bin/env python3
"""Probe addressed Ghostty keys in one disposable window; never touches existing surfaces."""

import json
import os
import shlex
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / ".build/debug/termex-host"
CAPTURE = ROOT / "probes/ghostty/key_capture.py"
NEW = 'tell application id "com.mitchellh.ghostty" to get id of (new window)'
NEW_TAB = '''on run argv
set wid to item 1 of argv
tell application id "com.mitchellh.ghostty" to get id of (new tab in (first window whose id is wid))
end run'''
CLOSE = '''on run argv
set wid to item 1 of argv
tell application id "com.mitchellh.ghostty" to close window (first window whose id is wid)
end run'''
CLOSE_TAB = '''on run argv
set wid to item 1 of argv
set tid to item 2 of argv
tell application id "com.mitchellh.ghostty" to close tab (first tab of (first window whose id is wid) whose id is tid)
end run'''
INPUT = '''on run argv
set wid to item 1 of argv
set sid to item 2 of argv
set payload to item 3 of argv
tell application id "com.mitchellh.ghostty"
set t to first terminal of (first window whose id is wid) whose id is sid
input text payload to t
end tell
end run'''
KEY = '''on run argv
set wid to item 1 of argv
set sid to item 2 of argv
set keyname to item 3 of argv
set mods to item 4 of argv
set actionName to item 5 of argv
tell application id "com.mitchellh.ghostty"
set t to first terminal of (first window whose id is wid) whose id is sid
if actionName is "release" then
send key keyname action release modifiers mods to t
else if mods is "" then
send key keyname to t
else
send key keyname modifiers mods to t
end if
end tell
end run'''
ACTION = '''on run argv
set wid to item 1 of argv
set sid to item 2 of argv
set actionName to item 3 of argv
tell application id "com.mitchellh.ghostty"
set t to first terminal of (first window whose id is wid) whose id is sid
return perform action actionName on t
end tell
end run'''


def ae(script, *args):
    return subprocess.check_output(["osascript", "-e", script, *args], text=True, timeout=8).strip()


def surfaces(wid):
    rows = json.loads(subprocess.check_output([HOST, "--list-ghostty"], timeout=8))
    return {row["surfaceID"]: row for row in rows if row["windowID"] == wid}


def captured(path):
    return [json.loads(line)["hex"] for line in path.read_text().splitlines()] if path.exists() else []


with tempfile.TemporaryDirectory(prefix="termex-keys-") as temporary:
    os.chmod(temporary, 0o700)
    output = Path(temporary) / "bytes.jsonl"
    assert subprocess.run(["pgrep", "-x", "ghostty"], capture_output=True).returncode == 0, "Ghostty must already be running"
    wid = ae(NEW)
    try:
        for _ in range(40):
            starting = surfaces(wid)
            if len(starting) == 1:
                break
            time.sleep(0.1)
        assert len(starting) == 1, "test window did not get one surface"
        primary = next(iter(starting))
        command = f"python3 -u {shlex.quote(str(CAPTURE))} {shlex.quote(str(output))} 75"
        ae(INPUT, wid, primary, command)
        ae(KEY, wid, primary, "enter", "", "press")
        for _ in range(40):
            if output.exists():
                break
            time.sleep(0.1)
        assert output.exists(), "raw capture did not start"

        matrix = [
            ("tab", ""), ("tab", "shift"), ("c", "control"),
            ("a", ""), ("a", "shift"), ("e", ""), ("digit2", ""),
            ("a", "option"), ("digit2", "option"), ("e", "option"),
            ("a", "option,shift"), ("a", "control,option"),
            ("a", "control,shift"), ("a", "control,option,shift"),
            ("a", "command,control,option,shift"), ("digit2", "option,shift"),
            ("tab", "control"), ("tab", "control,shift"), ("a", "command"),
        ]
        for key, mods in matrix:
            before = captured(output)
            prior = set(surfaces(wid))
            ae(KEY, wid, primary, key, mods, "press")
            time.sleep(0.2)
            after = captured(output)
            current = set(surfaces(wid))
            print(json.dumps({"key": key, "modifiers": mods, "new_hex": after[len(before):],
                              "new_surfaces": len(current - prior), "closed_surfaces": len(prior - current)}))
            assert primary in current, "primary test surface unexpectedly closed"
        before = captured(output)
        ae(KEY, wid, primary, "e", "option", "press")
        ae(KEY, wid, primary, "e", "", "press")
        time.sleep(0.2)
        print(json.dumps({"sequence": "option+e,e", "new_hex": captured(output)[len(before):]}))
        before = captured(output)
        ae(KEY, wid, primary, "tab", "shift", "release")
        time.sleep(0.2)
        print(json.dumps({"key": "tab", "modifiers": "shift", "action": "release",
                          "new_hex": captured(output)[len(before):]}))
        before = captured(output)
        ae(INPUT, wid, primary, "é")
        time.sleep(0.2)
        print(json.dumps({"input_text": "unicode_control", "new_hex": captured(output)[len(before):]}))

        before = captured(output)
        prior = set(surfaces(wid))
        ae(KEY, wid, primary, "d", "command", "press")
        time.sleep(0.4)
        current = set(surfaces(wid))
        print(json.dumps({"key": "d", "modifiers": "command", "new_hex": captured(output)[len(before):],
                          "new_surfaces": len(current - prior)}))
        created = current - prior
        if not created:
            print(json.dumps({"perform_action": "new_split:right", "result": ae(ACTION, wid, primary, "new_split:right")}))
            time.sleep(0.4)
            created = set(surfaces(wid)) - prior
        assert len(created) == 1, "no exact test split created"
        split = next(iter(created))
        split_row = surfaces(wid)[split]
        split_output = Path(temporary) / "split.jsonl"
        split_command = f"python3 -u {shlex.quote(str(CAPTURE))} {shlex.quote(str(split_output))} 6"
        ae(INPUT, wid, split, split_command)
        ae(KEY, wid, split, "enter", "", "press")
        for _ in range(40):
            if split_output.exists():
                break
            time.sleep(0.1)
        assert split_output.exists(), "split raw capture did not start"
        original_before, split_before = captured(output), captured(split_output)
        ae(KEY, wid, primary, "tab", "", "press")
        time.sleep(0.2)
        assert captured(output)[len(original_before):] == ["09"]
        assert captured(split_output) == split_before
        original_before, split_before = captured(output), captured(split_output)
        ae(KEY, wid, split, "tab", "", "press")
        time.sleep(0.2)
        assert captured(split_output)[len(split_before):] == ["09"]
        assert captured(output) == original_before
        print(json.dumps({"inactive_split_routing": "PASS", "neighbor_untouched": "PASS"}))
        time.sleep(6)
        before = captured(output)
        ae(KEY, wid, split, "w", "command", "press")
        time.sleep(0.4)
        remaining = set(surfaces(wid))
        print(json.dumps({"key": "w", "modifiers": "command", "new_hex_primary": captured(output)[len(before):],
                          "split_closed": split not in remaining, "primary_retained": primary in remaining}))
        if split in remaining:
            print(json.dumps({"perform_action": "close_surface", "result": ae(ACTION, wid, split, "close_surface")}))
            time.sleep(0.4)
            remaining = set(surfaces(wid))
        assert split not in remaining and primary in remaining, "split cleanup or isolation failed"
        # A closed split must not resolve to the neighboring surface.
        stale = subprocess.run([HOST, "--resolve-ghostty", split_row["appInstanceID"],
                                split_row["windowID"], split_row["tabID"], split], capture_output=True, timeout=8)
        assert stale.returncode != 0 and not stale.stdout, "closed split resolved to another surface"

        tab_id = ae(NEW_TAB, wid)
        time.sleep(0.4)
        new_tab = {sid: row for sid, row in surfaces(wid).items() if row["tabID"] == tab_id}
        assert len(new_tab) == 1 and primary in surfaces(wid), "new tab not distinct from primary"
        tab_surface, tab_row = next(iter(new_tab.items()))
        tab_output = Path(temporary) / "tab.jsonl"
        tab_command = f"python3 -u {shlex.quote(str(CAPTURE))} {shlex.quote(str(tab_output))} 5"
        ae(INPUT, wid, tab_surface, tab_command)
        ae(KEY, wid, tab_surface, "enter", "", "press")
        for _ in range(40):
            if tab_output.exists():
                break
            time.sleep(0.1)
        assert tab_output.exists(), "tab raw capture did not start"
        original_before, tab_before = captured(output), captured(tab_output)
        ae(KEY, wid, primary, "tab", "", "press")
        time.sleep(0.2)
        assert captured(output)[len(original_before):] == ["09"] and captured(tab_output) == tab_before
        original_before, tab_before = captured(output), captured(tab_output)
        ae(KEY, wid, tab_surface, "tab", "", "press")
        time.sleep(0.2)
        assert captured(tab_output)[len(tab_before):] == ["09"] and captured(output) == original_before
        print(json.dumps({"inactive_tab_routing": "PASS", "neighbor_tab_untouched": "PASS"}))
        time.sleep(5)
        ae(CLOSE_TAB, wid, tab_id)
        time.sleep(0.4)
        assert set(surfaces(wid)) == {primary}, "closing test tab changed primary"
        stale = subprocess.run([HOST, "--resolve-ghostty", tab_row["appInstanceID"],
                                tab_row["windowID"], tab_id, tab_surface], capture_output=True, timeout=8)
        assert stale.returncode != 0 and not stale.stdout, "closed tab resolved to another surface"
    finally:
        ae(CLOSE, wid)
        for _ in range(40):
            rows = json.loads(subprocess.check_output([HOST, "--list-ghostty"], timeout=8))
            if all(row["windowID"] != wid for row in rows):
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("disposable Ghostty window remained open after close")
