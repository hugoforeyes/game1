#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPORT_DIR="$PROJECT_DIR/exports/web"
GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
PORT="${1:-8000}"

cd "$PROJECT_DIR"
mkdir -p "$EXPORT_DIR"

echo "Clearing stale Godot export cache..."
rm -rf "$PROJECT_DIR/.godot/exported"

echo "Exporting web build..."
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --export-release Web exports/web/index.html

echo "Starting local server on http://localhost:$PORT"
cd "$EXPORT_DIR"

python3 - "$PORT" <<'PYEOF'
import http.server, sys, mimetypes, shutil, urllib.parse, urllib.request

mimetypes.add_type("application/wasm", ".wasm")

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
BACKEND_ORIGIN = "http://127.0.0.1:5001"

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def do_HEAD(self):
        if self.path.startswith("/api/"):
            self.proxy_backend(head_only=True)
            return
        super().do_HEAD()

    def do_GET(self):
        if self.path.startswith("/api/"):
            self.proxy_backend()
            return
        super().do_GET()

    def proxy_backend(self, head_only=False):
        target = BACKEND_ORIGIN + self.path
        try:
            req = urllib.request.Request(target, method="HEAD" if head_only else "GET")
            with urllib.request.urlopen(req, timeout=120) as resp:
                self.send_response(resp.status)
                skip_headers = {"connection", "transfer-encoding", "content-encoding"}
                for key, value in resp.headers.items():
                    if key.lower() not in skip_headers:
                        self.send_header(key, value)
                self.end_headers()
                if not head_only:
                    shutil.copyfileobj(resp, self.wfile)
        except Exception as exc:
            message = f"Backend proxy failed: {exc}\n".encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(message)))
            self.end_headers()
            if not head_only:
                self.wfile.write(message)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()

    def log_message(self, fmt, *args):
        pass  # suppress per-request noise

    def handle_one_request(self):
        try:
            super().handle_one_request()
        except (BrokenPipeError, ConnectionResetError):
            pass

print(f"Serving http://localhost:{PORT}  (COOP/COEP + .wasm MIME + /api proxy enabled)")
with http.server.ThreadingHTTPServer(("", PORT), Handler) as httpd:
    httpd.serve_forever()
PYEOF
