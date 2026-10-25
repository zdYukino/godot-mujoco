#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-map-editor.XXXXXX)}"
mkdir -p "$OUT/project"
cp "$ROOT/tests/static_map/"{project.godot,map_editor_test.gd,source_transaction_test.gd} "$OUT/project/"
cp -a "$ROOT/demo/addons" "$OUT/project/"
printf '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/mujoco_editor/plugin.cfg")\n' >> "$OUT/project/project.godot"
timeout --kill-after=5 120 bash "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
python3 "$ROOT/tests/static_map/fixtures.py" "$OUT/project/fixtures"
# GUI=1 uses the actual display, otherwise this is editor integration self-test only.
args=(--headless); [[ "${GUI:-0}" == 1 ]] && args=()
timeout --kill-after=5 120 "$GODOT_BIN" "${args[@]}" --audio-driver Dummy --editor --path "$OUT/project" -- --static-map-test > "$OUT/editor.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);s=(p/'editor.log').read_text();rows=[x.split(' ',1)[1] for x in s.splitlines() if x.startswith('STATIC_MAP_EDITOR ')];assert len(rows)==1,s
r=json.loads(rows[0]);assert r['failed']==0,r
assert 'SCRIPT ERROR:' not in s and 'ERROR:' not in s and 'leak' not in s.lower(),s
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('MAP EDITOR PASS',r,p)
PY
