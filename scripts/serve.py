#!/usr/bin/env python3
"""Serve the single-threaded web export locally with correct Wasm MIME type."""
import argparse
import http.server
import pathlib

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=8060)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1] / "exports" / "web"

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}
    def __init__(self, *arguments, **keywords):
        super().__init__(*arguments, directory=str(root), **keywords)

print(f"Courtyard Block: http://localhost:{args.port}", flush=True)
http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
