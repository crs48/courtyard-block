#!/usr/bin/env python3
"""Export an unsigned simulator project without requiring an Apple team identity."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "exports/ios"
OUTPUT.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="courtyard-ios-") as temporary:
    project = Path(temporary)
    for name in ("core", "world", "ui", "assets", "content", "mods", "scripts"):
        shutil.copytree(ROOT / name, project / name)
    shutil.copy(ROOT / "project.godot", project / "project.godot")
    # Godot validates a nonempty team even for project-only export. This placeholder
    # is confined to the temporary project and never used to sign an application.
    presets = (ROOT / "export_presets.cfg").read_text().replace(
        'application/app_store_team_id=""', 'application/app_store_team_id="SIMULATOR"'
    )
    (project / "export_presets.cfg").write_text(presets)
    subprocess.run(["godot", "--headless", "--path", str(project), "--editor", "--quit"], check=True)
    subprocess.run(["godot", "--headless", "--path", str(project), "--export-debug", "iOS", str(OUTPUT / "CourtyardBlock.zip")], check=True)
print("Build the exported project with CODE_SIGNING_ALLOWED=NO and -sdk iphonesimulator.")
