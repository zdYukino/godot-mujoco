#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "$GODOT_BIN" "$OUT"
[[ ! -e "$OUT/project" ]] || { echo "Existing fixture preserved"; exit 2; }
mkdir -p "$OUT/project/assets"
cp -a "$ROOT/addons" "$OUT/project/"
cp "$ROOT/tests/static_map/project.godot" "$OUT/project/"
cp "$ROOT/examples/sdf_terrain/"*.gd "$OUT/project/"
python3 "$ROOT/examples/sdf_terrain/generate.py" --out "$OUT/project/assets" > "$OUT/generate.log"
cp "$ROOT/examples/_shared/assets/SOURCES.md" "$OUT/project/assets/"
cp "$ROOT/examples/_shared/floor_grid.gdshader" "$OUT/project/"
cp "$ROOT/examples/_shared/assets/kloofendal_43d_clear_puresky_4k.hdr" "$OUT/project/assets/"
cp "$ROOT/examples/sdf_terrain/assets/kloofendal_43d_clear_puresky_4k.hdr.import" "$OUT/project/assets/"
bash "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
"$GODOT_BIN" --headless --path "$OUT/project" --script res://prepare.gd > "$OUT/prepare.log" 2>&1
python3 - "$OUT/project/project.godot" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]);s=p.read_text()
if "run/main_scene=" in s:
    s="\n".join('run/main_scene="res://Main.tscn"' if x.startswith("run/main_scene=") else x for x in s.splitlines())+"\n"
else:s=s.replace("[application]","[application]\nrun/main_scene=\"res://Main.tscn\"")
if "[editor_plugins]" not in s:
    s+='\n[editor_plugins]\nenabled=PackedStringArray("res://addons/mujoco_editor/plugin.cfg")\n'
elif 'res://addons/mujoco_editor/plugin.cfg' not in s:
    raise SystemExit("Terrain template has an unexpected editor plugin configuration")

p.write_text(s)
PY
python3 - "$OUT" <<'PYAUDIT'
from pathlib import Path
import sys
for name in ("import.log","prepare.log"):
    text=(Path(sys.argv[1])/name).read_text()
    if "SCRIPT ERROR:" in text or "\nERROR:" in text or "leaked" in text: raise SystemExit("Terrain preparation log failed: "+name)
PYAUDIT
echo "SDF terrain project: $OUT/project"
