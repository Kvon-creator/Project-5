#!/usr/bin/env bash
# Render every asset through the shared rig, in dependency order.
#
# The anchor asset goes FIRST, because the GDD checks every other asset
# against it. If you change anything in rig_common.py - the camera angle, the
# lights, the cel bands, the ink weight - run this whole script, not one
# asset: a mixed set is worse than an unfinished one.
#
#   ./pipeline/render_all.sh
#   python3 pipeline/check_anchor.py      # verify afterwards
#
# The room is slowest by far (several minutes); characters and props are
# quick. tiles.py is retired - rooms are painted backgrounds now.
set -euo pipefail
cd "$(dirname "$0")/.."

BLENDER="${BLENDER:-blender}"

for asset in player enemy props room; do
  echo "=== $asset ==="
  "$BLENDER" -b --python "pipeline/${asset}.py" 2>&1 \
    | grep -Ei 'error|traceback|\[(render|player|enemy|props|room)\]' \
    | grep -v EGL || true
done

echo
echo "=== checking against the anchor ==="
python3 pipeline/check_anchor.py || true
echo
echo "=== static GDScript check ==="
python3 pipeline/check_gdscript.py
