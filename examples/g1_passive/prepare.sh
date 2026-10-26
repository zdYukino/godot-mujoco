#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-passive-g1.XXXXXX)}"
mkdir -p "$OUT/project"
cp -a "$ROOT/examples/shape_gallery/". "$OUT/project/"
cp -a "$ROOT/demo/addons" "$OUT/project/"
cp -a "$ROOT/examples/g1_passive/models/". "$OUT/project/models/"
cp "$ROOT/examples/g1_passive/G1.tscn" "$ROOT/examples/g1_passive/g1_collision_previews.res" "$OUT/project/"
if [[ "${REBUILD:-0}" == 1 ]]; then
 python3 - "$ROOT/demo/assets/robots/unitree_g1/g1_29dof_mode_18" <<'PYHASH'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1]);m=json.loads((p/'upstream-manifest.json').read_text())
for f in m['files']:
 assert hashlib.sha256((p/f['path']).read_bytes()).hexdigest()==f['sha256'],f['path']
print('Verified pinned Unitree source manifest',m['commit'])
PYHASH
 mkdir -p "$OUT/project/assets/robots"
 cp -a "$ROOT/demo/assets/robots/unitree_g1" "$OUT/project/assets/robots/"
fi
cp "$ROOT/examples/g1_passive/"*.gd "$OUT/project/"
cp "$ROOT/examples/g1_passive/UPSTREAM_LICENSE" "$ROOT/examples/g1_passive/upstream-manifest.json" "$ROOT/examples/g1_passive/README.md" "$OUT/project/"
timeout --kill-after=5 150 bash "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
if [[ "${REBUILD:-0}" == 1 ]]; then
 timeout --kill-after=5 180 "$GODOT_BIN" --headless --path "$OUT/project" --script res://prepare_g1.gd > "$OUT/prepare.log" 2>&1
fi
python3 - "$OUT/project/project.godot" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);p.write_text(p.read_text().replace('res://Main.tscn','res://G1.tscn').replace('MuJoCo 动态形状示例','MuJoCo 无控 G1 示例'))
PY
echo "G1 project: $OUT/project (run GODOT_BIN --path this-directory)"
