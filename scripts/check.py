#!/usr/bin/env python3
"""Godot sometimes exits zero on script errors; treat its diagnostics as failures."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

def run(arguments, timeout=120):
    result = subprocess.run(["godot", "--headless", "--path", str(ROOT), *arguments],
                            capture_output=True, text=True, timeout=timeout)
    output = result.stdout + result.stderr
    print(output, end="")
    if result.returncode or "SCRIPT ERROR:" in output or "ERROR:" in output:
        sys.exit(1)

run(["--editor", "--import", "--quit"])
run(["--script", "tests/run.gd"])
