#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-native-collision.XXXXXX)}"
mkdir -p "$OUT/project"
cp "$ROOT/tests/static_map/project.godot" "$OUT/project/"
cp "$ROOT/tests/native_collision/"*.gd "$OUT/project/"
cp -a "$ROOT/demo/addons" "$OUT/project/"
python3 "$ROOT/tests/static_map/fixtures.py" "$OUT/project/fixtures"
timeout 150 bash "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
! rg 'SCRIPT ERROR|Parse Error' "$OUT/import.log"
timeout 150 "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://acceptance.gd > "$OUT/acceptance.log" 2>&1
timeout 150 "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://extended.gd > "$OUT/extended.log" 2>&1
timeout 150 "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://attributes.gd > "$OUT/attributes.log" 2>&1
timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://relations_transaction.gd > "$OUT/relations_transaction.log" 2>&1
printf '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/mujoco_editor/plugin.cfg")\n' >> "$OUT/project/project.godot"
timeout 120 "$GODOT_BIN" --headless --editor --path "$OUT/project" -- --ui-layout-test > "$OUT/layout.log" 2>&1
timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://map_gizmo_runtime.gd > "$OUT/map_gizmo_runtime.log" 2>&1
python3 - "$OUT/project" <<'PY'
import pathlib,shutil,sys
p=pathlib.Path(sys.argv[1]);shutil.rmtree(p/'fixtures');old=(p/'saved_path.txt').read_text();(p/old.removeprefix('res://')).rename(p/'relocated');(p/'saved_path.txt').write_text('res://relocated')
PY
timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://reopen.gd > "$OUT/reopen.log" 2>&1
! rg 'SCRIPT ERROR|ERROR:|leaked' "$OUT/acceptance.log" "$OUT/reopen.log" "$OUT/extended.log" "$OUT/attributes.log" "$OUT/relations_transaction.log" "$OUT/layout.log" "$OUT/map_gizmo_runtime.log"
python3 - "$OUT" <<'PYRESULT'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);rows=[x.split(' ',1)[1] for x in (p/'acceptance.log').read_text().splitlines() if x.startswith('NATIVE_COLLISION_RESULT ')]
assert len(rows)==1
r=json.loads(rows[0]);assert r['failed']==0 and r['passed']>0
extra=[x.split(' ',1)[1] for x in (p/'extended.log').read_text().splitlines() if x.startswith('NATIVE_EXTENDED_RESULT ')];assert len(extra)==1
r['extended']=json.loads(extra[0]);assert r['extended']['failed']==0
attributes=[x.split(' ',1)[1] for x in (p/'attributes.log').read_text().splitlines() if x.startswith('NATIVE_ATTRIBUTES_RESULT ')];assert len(attributes)==1
r['attributes']=json.loads(attributes[0]);assert r['attributes']['failed']==0
transactions=[x.split(' ',1)[1] for x in (p/'relations_transaction.log').read_text().splitlines() if x.startswith('NATIVE_RELATION_TRANSACTION_RESULT ')];assert len(transactions)==1
r['relation_transactions']=json.loads(transactions[0]);assert r['relation_transactions']['failed']==0
layout=[x.split(' ',1)[1] for x in (p/'layout.log').read_text().splitlines() if x.startswith('NATIVE_LAYOUT_RESULT ')];assert len(layout)==1
r['layout']=json.loads(layout[0]);assert r['layout']['failed']==0
gizmo=[x.split(' ',1)[1] for x in (p/'map_gizmo_runtime.log').read_text().splitlines() if x.startswith('MAP_GIZMO_RUNTIME_RESULT ')];assert len(gizmo)==1
r['map_gizmo_runtime']=json.loads(gizmo[0]);assert r['map_gizmo_runtime']['failed']==0
assert 'NATIVE_HEIGHT_PAIR_REOPEN true' in (p/'reopen.log').read_text()
assert 'NATIVE_ATTRIBUTE_REOPEN true' in (p/'reopen.log').read_text()
assert 'NATIVE_REOPEN true target material/force true' in (p/'reopen.log').read_text()
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n')
PYRESULT
echo "NATIVE COLLISION PASS $OUT"
