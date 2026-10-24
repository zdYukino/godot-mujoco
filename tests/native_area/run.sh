#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-area.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_area/"{project.godot,acceptance.gd,negative.gd,gui.gd,body_shape_order.gd} "$OUT/project/"
cp -a "$ROOT/demo/addons" "$OUT/project/"
timeout 120 bash "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://acceptance.gd > "$OUT/positive.log" 2>&1
timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://body_shape_order.gd > "$OUT/body-shape-order.log" 2>&1
timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://negative.gd > "$OUT/negative.log" 2>&1
timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://gui.gd --quit-after 240 > "$OUT/gui-smoke.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib,sys,json
p=pathlib.Path(sys.argv[1])
for name in ['import','gui-smoke','body-shape-order','positive']:
 s=(p/(name+'.log')).read_text();assert 'ERROR:' not in s and 'leak' not in s.lower(),s
rows=[x.split(' ',1)[1] for x in s.splitlines() if x.startswith('AREA_RESULT ')];assert len(rows)==1
r=json.loads(rows[0]);assert r['failed']==0
order=json.loads(next(x.split(' ',1)[1] for x in (p/'body-shape-order.log').read_text().splitlines() if x.startswith('AREA_BODY_SHAPE_ORDER_RESULT ')))
assert order['failed']==0 and order['passed']==22,order
r['body_shape_order']=order
s=(p/'negative.log').read_text();errors=[x for x in s.splitlines() if x.startswith('ERROR:')]
assert len(errors)==3 and 'Area monitoring supports native box, sphere, cylinder and capsule only' in errors[0] and '!rigid(t)' in errors[1],s
assert 'Area override mode must be 0..4' in errors[2] and 'AREA_NEGATIVE_RESULT true' in s and 'SCRIPT ERROR:' not in s and 'leak' not in s.lower(),s
r['expected_errors']=3;r['expected_unsupported_warnings']=0
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('AREA PASS',r)
PY
