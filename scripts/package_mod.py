#!/usr/bin/env python3
"""Package v1 trusted source mods or v2 single-manifest data mods."""
import argparse
import json
import pathlib
import re
import zipfile
from urllib.parse import quote

parser = argparse.ArgumentParser()
parser.add_argument("directory", type=pathlib.Path)
parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("exports/mods"))
args = parser.parse_args()
manifest_path = args.directory / "manifest.json"
manifest = json.loads(manifest_path.read_text())
version = manifest.get("api_version")
pack_id = manifest.get("id", "")
if version not in (1, 2) or not isinstance(pack_id, str) or not re.fullmatch(r"[a-z0-9_-]{1,64}", pack_id):
    parser.error("Expected API version 1 or 2 and a lowercase namespaced pack ID.")
if not isinstance(manifest.get("version"), str) or not manifest["version"]:
    parser.error("Expected a nonempty pack version.")
if version == 2:
    if manifest_path.stat().st_size > 8 * 1024 * 1024:
        parser.error("Data packs must be smaller than 8 MiB.")
    if set(manifest) - {"api_version", "model", "id", "name", "version", "dependencies", "content"}:
        parser.error("API v2 accepts only manifest data, with no scripts or asset entrypoints.")
    paths = [manifest_path]
else:
    paths = sorted(path for path in args.directory.rglob("*")
                   if path.is_file() and not any(part.startswith(".") for part in path.relative_to(args.directory).parts))
args.output.mkdir(parents=True, exist_ok=True)
destination = args.output / f'{manifest["id"]}-{quote(manifest["version"], safe="")}.cbmod.zip'
with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in paths:
        archive.write(path, path.relative_to(args.directory))
print(destination)
if version == 2:
    print("Data archive only. Validate definitions with scripts/run_lab.gd --validate-pack=<archive> or the in-game Workshop.")
