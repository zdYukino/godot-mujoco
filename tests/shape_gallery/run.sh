#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-shape-gallery.XXXXXX)}"
mkdir -p "$OUT/project"
cp -a "$ROOT/examples/shape_gallery/". "$OUT/project/"
cp -a "$ROOT/demo/addons" "$OUT/project/"
cp "$ROOT/tests/shape_gallery/acceptance.gd" "$OUT/project/"
timeout --kill-after=5 120 bash "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://acceptance.gd > "$OUT/shipped.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://prepare.gd > "$OUT/prepare.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://acceptance.gd > "$OUT/runtime.log" 2>&1
mv "$OUT/project/assets/gallery.xml" "$OUT/source-unavailable.xml"
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://acceptance.gd > "$OUT/missing-source.log" 2>&1
python3 - "$OUT" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);s=(p/'runtime.log').read_text();rows=[x.split(' ',1)[1] for x in s.splitlines() if x.startswith('SHAPE_GALLERY_RESULT ')];assert len(rows)==1,s
r=json.loads(rows[0]);assert r['failed']==0,r
for name in ['shipped.log','missing-source.log']:
 rows=[x.split(' ',1)[1] for x in (p/name).read_text().splitlines() if x.startswith('SHAPE_GALLERY_RESULT ')];assert len(rows)==1,name
 result=json.loads(rows[0]);assert result['failed']==0,result
 r[name]=result
for f in p.glob('*.log'):
 s=f.read_text();assert 'SCRIPT ERROR:' not in s and '\nERROR:' not in s and 'leaked' not in s,str(f)
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('SHAPE GALLERY PASS',r,p)
PY
