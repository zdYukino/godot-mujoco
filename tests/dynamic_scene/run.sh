#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-dynamic.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || { echo 'Use a fresh OUT directory' >&2; exit 2; }
mkdir -p "$OUT/project"
cp -a "$ROOT/tests/dynamic_scene/". "$OUT/project/"
cp -a "$ROOT/demo/addons" "$ROOT/demo/assets" "$OUT/project/"
GODOT_BIN="$GODOT_BIN" timeout 120 "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
timeout 180 "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 res://Acceptance.tscn -- --report="$OUT/results.json" > "$OUT/runtime.log" 2>&1
timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 -- --ui-smoke > "$OUT/ui-smoke.log" 2>&1
python3 - "$OUT" <<'PY'
import json,pathlib,sys,hashlib
p=pathlib.Path(sys.argv[1]);r=json.loads((p/'results.json').read_text());assert r['failed']==0 and r['passed']==86,r
for log in ['import.log','runtime.log','ui-smoke.log']:
 assert 'ERROR:' not in (p/log).read_text(),log
ui=[line for line in (p/'ui-smoke.log').read_text().splitlines() if line.startswith('DYNAMIC_UI_RESULT ')];assert len(ui)==1 and json.loads(ui[0].split(' ',1)[1])['passed']
r['extension_sha256']=hashlib.sha256((p/'project/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').read_bytes()).hexdigest()
r['ui']=json.loads(ui[0].split(' ',1)[1]);(p/'results.json').write_text(json.dumps(r,indent=2)+'\n')
print('DYNAMIC PASS',r['passed'],'checks;',p)
PY
