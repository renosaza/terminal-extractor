#!/usr/bin/env python3
"""Inspect installed app bundles without launching or automating either app."""

import hashlib
import json
import plistlib
import xml.etree.ElementTree as ET
from pathlib import Path


APPS = {
    "terminal": (Path("/System/Applications/Utilities/Terminal.app"), "Terminal.sdef"),
    "ghostty": (Path("/Applications/Ghostty.app"), "Ghostty.sdef"),
}


for name, (bundle, dictionary_name) in APPS.items():
    info_path = bundle / "Contents/Info.plist"
    dictionary_path = bundle / "Contents/Resources" / dictionary_name
    if not info_path.is_file() or not dictionary_path.is_file():
        print(json.dumps({"app": name, "status": "not_installed"}))
        continue
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    data = dictionary_path.read_bytes()
    root = ET.fromstring(data)
    classes = {
        item.get("name"): sorted(prop.get("name") for prop in item.findall("property"))
        for item in root.findall(".//class")
        if item.get("name") in {"window", "tab", "terminal"}
    }
    commands = sorted({item.get("name") for item in root.findall(".//command")})
    print(json.dumps({
        "app": name,
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "sdef_sha256": hashlib.sha256(data).hexdigest(),
        "classes": classes,
        "commands": commands,
    }, ensure_ascii=False, sort_keys=True))
