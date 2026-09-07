#!/usr/bin/env python3
"""
Bakedown HTTP Bridge — exposes a local recipe folder (or SMB mount) over HTTP
so the web build can access it. Browsers block raw SMB (TCP 445), so this
bridge translates HTTP -> filesystem.

Usage:
  python server.py --dir /path/to/recipes --port 8787
  python server.py --dir "Z:\\Recipes" --port 8787   # Windows UNC mounted drive
  python server.py --dir ./recipes --host 0.0.0.0 --port 8787

Then in Bakedown web: Settings -> HTTP Bridge -> http://<host>:8787 -> Test Bridge

API:
  GET  /api/folders                     -> ["Desserts", "Mains"]
  GET  /api/folders/<folder>           -> ["cake.md", "soup.md"]
  GET  /api/file/<folder>/<file>       -> text/markdown
  PUT  /api/file/<folder>/<file>       -> create/update
  DELETE /api/file/<folder>/<file>     -> delete file
  POST /api/folder/<name>              -> create folder
  DELETE /api/folder/<name>            -> delete folder (recursive)
  GET  /files/<folder>/<file>          -> raw file (images)
  GET  /api/discover                   -> [{"name","host","port":8787}] (for mDNS proxy)
  OPTIONS *                            -> CORS preflight
"""
import argparse
import json
import os
import shutil
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

class Handler(BaseHTTPRequestHandler):
    root: Path = Path(".")

    def log_message(self, fmt, *args):
        print(f"[{self.client_address[0]}] {self.command} {self.path}")

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Access-Control-Expose-Headers", "Content-Length")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self._cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _text(self, text, code=200, ctype="text/markdown; charset=utf-8"):
        body = text.encode("utf-8")
        self.send_response(code)
        self._cors()
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _err(self, msg, code=400):
        self._json({"error": msg}, code)

    def _safe_path(self, folder, filename=None):
        # Prevent traversal
        folder = urllib.parse.unquote(folder or "")
        if filename is not None:
            filename = urllib.parse.unquote(filename)
        if ".." in folder or ".." in (filename or "") or folder.startswith("/") or folder.startswith("\\"):
            return None
        # Sanitize folder/file to avoid traversal via separators
        if filename is not None and ("/" in filename or "\\" in filename):
            return None
        base = self.root.resolve()
        if filename is None:
            p = (base / folder).resolve()
        else:
            p = (base / folder / filename).resolve()
        try:
            p.relative_to(base)
        except ValueError:
            return None
        return p

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/folders":
            try:
                folders = [d.name for d in self.root.iterdir() if d.is_dir()]
                folders.sort()
                self._json(folders)
            except Exception as e:
                self._err(str(e), 500)
            return

        if path == "/api/discover":
            # Advertise this bridge for web discovery
            import socket
            host = socket.gethostname()
            self._json([{"name": f"Bakedown Bridge @ {host}", "host": f"http://{self.headers.get('Host', 'localhost')}", "port": 8787}])
            return

        if path.startswith("/api/folders/"):
            folder = path[len("/api/folders/"):]
            folder = urllib.parse.unquote(folder.split("?")[0].split("#")[0])
            # Support /subfolders suffix
            is_subfolders = False
            if folder.endswith("/subfolders"):
                folder = folder[:-len("/subfolders")]
                if folder.endswith("/"):
                    folder = folder[:-1]
                is_subfolders = True
            p = self._safe_path(folder)
            if p is None or not p.is_dir():
                self._err("folder not found", 404)
                return
            folders = [d.name for d in p.iterdir() if d.is_dir()]
            folders.sort()
            files = [f.name for f in p.iterdir() if f.is_file()]
            files.sort()
            if is_subfolders:
                self._json(folders)
            else:
                self._json({"folders": folders, "files": files})
            return

        if path.startswith("/api/file/"):
            rest = path[len("/api/file/"):]
            parts = rest.split("/", 1)
            if len(parts) != 2:
                self._err("invalid path", 400)
                return
            folder, filename = parts
            p = self._safe_path(folder, filename)
            if p is None or not p.is_file():
                self._err("file not found", 404)
                return
            try:
                text = p.read_text(encoding="utf-8", errors="replace")
                self._text(text)
            except Exception as e:
                self._err(str(e), 500)
            return

        if path.startswith("/files/"):
            rest = path[len("/files/"):]
            parts = rest.split("/", 1)
            if len(parts) != 2:
                self._err("invalid path", 400)
                return
            folder, filename = parts
            p = self._safe_path(folder, filename)
            if p is None or not p.is_file():
                self._err("file not found", 404)
                return
            # Guess mime
            mime = "application/octet-stream"
            if p.suffix.lower() in (".jpg", ".jpeg"):
                mime = "image/jpeg"
            elif p.suffix.lower() == ".png":
                mime = "image/png"
            elif p.suffix.lower() == ".webp":
                mime = "image/webp"
            elif p.suffix.lower() == ".md":
                mime = "text/markdown"
            try:
                data = p.read_bytes()
                self.send_response(200)
                self._cors()
                self.send_header("Content-Type", mime)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            except Exception as e:
                self._err(str(e), 500)
            return

        if path in ("/", "/api", "/api/"):
            self._json({"service": "bakedown-bridge", "root": str(self.root), "endpoints": ["/api/folders", "/api/folders/<folder>", "/api/file/<folder>/<file>", "/files/<folder>/<file>", "/api/discover"]})
            return

        self._err("not found", 404)

    def do_PUT(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        if path.startswith("/api/file/"):
            rest = path[len("/api/file/"):]
            parts = rest.split("/", 1)
            if len(parts) != 2:
                self._err("invalid path", 400)
                return
            folder, filename = parts
            p = self._safe_path(folder, filename)
            if p is None:
                self._err("invalid path", 400)
                return
            length = int(self.headers.get("Content-Length", "0") or "0")
            body = self.rfile.read(length).decode("utf-8", errors="replace")
            try:
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(body, encoding="utf-8")
                self._json({"ok": True})
            except Exception as e:
                self._err(str(e), 500)
            return
        self._err("not found", 404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        # Create file via JSON wrapper
        if path == "/api/file":
            length = int(self.headers.get("Content-Length", "0") or "0")
            try:
                data = json.loads(self.rfile.read(length))
                folder = data.get("folder", "")
                filename = data.get("filename", "")
                content = data.get("content", "")
                p = self._safe_path(folder, filename)
                if p is None:
                    self._err("invalid path", 400)
                    return
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(content, encoding="utf-8")
                self._json({"ok": True})
            except Exception as e:
                self._err(str(e), 500)
            return
        if path.startswith("/api/folder/"):
            name = urllib.parse.unquote(path[len("/api/folder/"):])
            p = self._safe_path(name)
            if p is None:
                self._err("invalid path", 400)
                return
            try:
                p.mkdir(parents=True, exist_ok=True)
                self._json({"ok": True})
            except Exception as e:
                self._err(str(e), 500)
            return
        if path == "/api/folders":
            length = int(self.headers.get("Content-Length", "0") or "0")
            try:
                data = json.loads(self.rfile.read(length)) if length else {}
                name = data.get("name", "")
                if not name:
                    self._err("name required", 400)
                    return
                p = self._safe_path(name)
                if p is None:
                    self._err("invalid path", 400)
                    return
                p.mkdir(parents=True, exist_ok=True)
                self._json({"ok": True})
            except Exception as e:
                self._err(str(e), 500)
            return
        self._err("not found", 404)

    def do_DELETE(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        if path.startswith("/api/file/"):
            rest = path[len("/api/file/"):]
            parts = rest.split("/", 1)
            if len(parts) != 2:
                self._err("invalid path", 400)
                return
            folder, filename = parts
            p = self._safe_path(folder, filename)
            if p is None or not p.exists():
                self._err("not found", 404)
                return
            try:
                p.unlink()
                self._json({"ok": True})
            except Exception as e:
                self._err(str(e), 500)
            return
        if path.startswith("/api/folder/"):
            name = urllib.parse.unquote(path[len("/api/folder/"):])
            p = self._safe_path(name)
            if p is None or not p.exists():
                self._err("not found", 404)
                return
            try:
                shutil.rmtree(p)
                self._json({"ok": True})
            except Exception as e:
                self._err(str(e), 500)
            return
        self._err("not found", 404)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=".", help="Recipe root folder (or SMB mount point)")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8787)
    args = ap.parse_args()

    Handler.root = Path(args.dir).resolve()
    if not Handler.root.exists():
        print(f"Creating root {Handler.root}")
        Handler.root.mkdir(parents=True, exist_ok=True)

    srv = HTTPServer((args.host, args.port), Handler)
    print(f"Bakedown bridge serving {Handler.root} at http://{args.host}:{args.port}")
    print("CORS enabled, API at /api/folders")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down")

if __name__ == "__main__":
    main()
