#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-editor.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || { echo 'Use a fresh OUT directory' >&2; exit 2; }
mkdir -p "$OUT/project"
cp -a "$ROOT/tests/editor_plugin/". "$OUT/project/"
cp -a "$ROOT/addons" "$OUT/project/"
timeout --kill-after=5 120 "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --editor --path "$OUT/project" -- --mj-editor-test --report="$OUT/results.json" > "$OUT/runtime.log" 2>&1
python3 - "$OUT" <<'PY'
import json,sys,pathlib,hashlib
p=pathlib.Path(sys.argv[1]);r=json.loads((p/'results.json').read_text());assert r['failed']==0,r
for log in ['import.log','runtime.log']:
 s=(p/log).read_text();assert 'SCRIPT ERROR:' not in s and '\nERROR:' not in s and 'ObjectDB instances leaked' not in s,log
r['extension_sha256']=hashlib.sha256((p/'project/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').read_bytes()).hexdigest()
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('EDITOR PASS',r['passed'],'checks;',p)
PY
