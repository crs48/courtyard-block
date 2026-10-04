#!/usr/bin/env python3
"""Export the pinned Godot Web preset and its required license notices."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
(ROOT / "exports/web").mkdir(parents=True, exist_ok=True)

for arguments in (
    ["--editor", "--import", "--quit"],
    ["--export-release", "Web", "exports/web/index.html"],
    ["--script", "scripts/export_licenses.gd"],
):
    result = subprocess.run(
        ["godot", "--headless", "--path", str(ROOT), *arguments],
        capture_output=True, text=True, timeout=240,
    )
    output = result.stdout + result.stderr
    print(output, end="")
    if result.returncode or "SCRIPT ERROR:" in output or "ERROR:" in output:
        sys.exit(1)

print("Browser build and license notices ready in exports/web/.")
