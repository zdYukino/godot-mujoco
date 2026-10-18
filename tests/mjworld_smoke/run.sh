#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-mjworld-smoke.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT"
python3 - "$ROOT" "$OUT" <<'PY'
import pathlib,shutil,sys
r,o=map(pathlib.Path,sys.argv[1:])
shutil.copytree(r/'demo',o/'project',ignore=shutil.ignore_patterns('.godot','bin','obj'))
shutil.copytree(r/'demo/addons/godot_mujoco/bin',o/'project/addons/godot_mujoco/bin')
shutil.copy2(r/'tests/mjworld_smoke/invalid_qpos.gd',o/'project/invalid_qpos.gd')
PY
timeout --kill-after=5 120 "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
set +e
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" res://HeadlessTest.tscn > "$OUT/positive.log" 2>&1
positive_exit=$?
timeout --kill-after=5 30 "$GODOT_BIN" --headless --path "$OUT/project" --script res://invalid_qpos.gd > "$OUT/negative.log" 2>&1
negative_exit=$?
set -e
PYTHONPATH="$ROOT/tests/mjworld_smoke" python3 - "$OUT" "$positive_exit" "$negative_exit" <<'PY'
import pathlib,json,sys
from audit import positive,negative
p=pathlib.Path(sys.argv[1]);a,b=map(int,sys.argv[2:]);imp=(p/'import.log').read_text()
assert 'ERROR:' not in imp and 'leak' not in imp.lower()
positive((p/'positive.log').read_text(),a);r=negative((p/'negative.log').read_text(),b)
(p/'results.json').write_text(json.dumps({'positive_exit':a,'negative_exit':b,'positive_passed':True,'negative':r},indent=2)+'\n')
print('MJWORLD SMOKE PASS; positive zero ERROR; isolated qpos rejection exactly matched')
PY
python3 -m unittest discover -s "$ROOT/tests/mjworld_smoke" -p test_audit.py > "$OUT/audit-tests.log" 2>&1
