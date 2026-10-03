#!/usr/bin/env python3
"""Package a portable source/data mod; Godot is not needed to author data packs."""
import argparse
import json
import pathlib
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("directory", type=pathlib.Path)
parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("exports/mods"))
args = parser.parse_args()
manifest = json.loads((args.directory / "manifest.json").read_text())
assert manifest["api_version"] == 1
assert all(c in "abcdefghijklmnopqrstuvwxyz0123456789_-" for c in manifest["id"])
args.output.mkdir(parents=True, exist_ok=True)
destination = args.output / f'{manifest["id"]}-{manifest["version"]}.cbmod.zip'
with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(args.directory.rglob("*")):
        if path.is_file() and not any(part.startswith(".") for part in path.relative_to(args.directory).parts):
            archive.write(path, path.relative_to(args.directory))
print(destination)
