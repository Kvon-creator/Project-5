#!/usr/bin/env bash
# Export the game for the web (GitHub Pages) into build/web/.
#
#   ./pipeline/export_web.sh [path-to-godot]
#
# Uses the "Web" preset in export_presets.cfg: thread support OFF, because
# GitHub Pages does not send the cross-origin-isolation headers a threaded
# build needs. Needs the Godot 4.7 export templates installed once from the
# editor (Editor > Manage Export Templates).
set -euo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
mkdir -p build/web
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
echo "exported to build/web/ - serve that folder, or push it to gh-pages"
