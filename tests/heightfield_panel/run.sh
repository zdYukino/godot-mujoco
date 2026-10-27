#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-editor.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || { echo 'Use a fresh OUT directory' >&2; exit 2; }
mkdir -p "$OUT/project"
cp -a "$ROOT/tests/heightfield_panel/". "$OUT/project/"
cp "$ROOT/tests/heightfield/"{prepare.gd,gui.gd} "$OUT/project/"
cp -a "$ROOT/addons" "$OUT/project/"
run_stage() {
 local stage="$1" code; shift
 set +e
 timeout --kill-after=5 120 "$@" > "$OUT/$stage.log" 2>&1
 code=$?
 set -e
 printf '%s\t%s\n' "$stage" "$code" >> "$OUT/executions.tsv"
 [[ "$code" == 0 ]] || { echo "$stage failed ($code): $OUT/$stage.log" >&2; return "$code"; }
}
run_stage import bash "$ROOT/scripts/import_headless.sh" "$OUT/project"
run_stage runtime "$GODOT_BIN" --headless --editor --path "$OUT/project" -- --mj-editor-test --report="$OUT/results.json"
run_stage prepare "$GODOT_BIN" --headless --path "$OUT/project" --script res://prepare.gd
run_stage material-runtime "$GODOT_BIN" --headless --path "$OUT/project" --script res://runtime_material.gd
python3 - "$OUT" <<'PY'
import json,sys,pathlib,hashlib
p=pathlib.Path(sys.argv[1]);r=json.loads((p/'results.json').read_text());assert r['failed']==0,r
for log in ['import.log','runtime.log','prepare.log','material-runtime.log']:
 s=(p/log).read_text();assert 'SCRIPT ERROR:' not in s and '\nERROR:' not in s and 'ObjectDB instances leaked' not in s,log
rows=[line.split(' ',1)[1] for line in (p/'material-runtime.log').read_text().splitlines() if line.startswith('PANEL_MATERIAL_RUNTIME_RESULT ')]
assert len(rows)==1 and json.loads(rows[0])['failed']==0
r['material_runtime']=json.loads(rows[0])
r['extension_sha256']=hashlib.sha256((p/'project/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').read_bytes()).hexdigest()
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('TERRAIN PANEL PASS',r['passed'],'checks;',p)
PY
