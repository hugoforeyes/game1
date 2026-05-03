#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/Users/dinhhuynh/Documents/GameV1"
EXPORT_DIR="$PROJECT_DIR/exports/web"
GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
PORT="${1:-8000}"

cd "$PROJECT_DIR"
mkdir -p "$EXPORT_DIR"

echo "Exporting web build..."
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --export-release Web exports/web/index.html

echo "Starting local server on http://localhost:$PORT"
cd "$EXPORT_DIR"
python3 -m http.server "$PORT"
