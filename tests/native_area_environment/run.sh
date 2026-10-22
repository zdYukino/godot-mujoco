#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-area-env.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_area_environment/"{project.godot,acceptance.gd,negative.gd,gui.gd} "$OUT/project/"
cp -a "$ROOT/demo/addons" "$OUT/project/"
timeout 120 bash "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://acceptance.gd > "$OUT/positive.log" 2>&1
timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://negative.gd > "$OUT/negative.log" 2>&1
timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://gui.gd --quit-after 180 > "$OUT/gui-smoke.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib,sys,json
p=pathlib.Path(sys.argv[1])
for name in ['import','gui-smoke','positive']:
 s=(p/(name+'.log')).read_text();assert 'ERROR:' not in s and 'leak' not in s.lower(),s
r=json.loads(next(x.split(' ',1)[1] for x in s.splitlines() if x.startswith('AREA_ENVIRONMENT_RESULT ')))
assert r['failed']==0
s=(p/'negative.log').read_text();errors=[x for x in s.splitlines() if x.startswith('ERROR:')]
expected=['Area environment value must be finite','Area damping and point unit distance must be nonnegative','Area gravity vector must be finite','Area override mode must be 0..4']
assert len(errors)==4 and all(e in line for e,line in zip(expected,errors)) and 'AREA_ENVIRONMENT_NEGATIVE_RESULT true' in s and 'SCRIPT ERROR:' not in s and 'leak' not in s.lower(),s
r['expected_errors']=4
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('AREA ENVIRONMENT PASS',r)
PY
