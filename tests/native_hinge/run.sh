#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-hinge.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || { echo "Use a fresh OUT directory" >&2; exit 2; }
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_hinge/"{project.godot,acceptance.gd,gui.gd,input_smoke.gd,negative.gd} "$OUT/project/"
cp "$ROOT/tests/native_joints/acceptance.gd" "$OUT/project/pin_support.gd"
cp -a "$ROOT/demo/addons" "$OUT/project/"
run_stage() {
 local stage="$1" code;shift
 set +e
 timeout --kill-after=5 120 "$@" > "$OUT/$stage.log" 2>&1
 code=$?
 set -e
 printf '%s\t%s\n' "$stage" "$code" >> "$OUT/executions.tsv"
 [[ "$code" == 0 ]] || { echo "$stage failed ($code): $OUT/$stage.log" >&2;return "$code"; }
}
run_stage import bash "$ROOT/scripts/import_headless.sh" "$OUT/project"
run_stage positive "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://acceptance.gd
run_stage negative "$GODOT_BIN" --headless --path "$OUT/project" --script res://negative.gd
# Parsing and orderly teardown only; not a substitute for desktop visual QA.
run_stage gui-smoke "$GODOT_BIN" --headless --path "$OUT/project" --script res://gui.gd --quit-after 120
run_stage input-smoke "$GODOT_BIN" --headless --path "$OUT/project" --script res://input_smoke.gd
python3 - "$OUT" <<'PY'
import pathlib,sys,json,hashlib
p=pathlib.Path(sys.argv[1])
for name in ['import','gui-smoke','input-smoke','positive']:
 s=(p/(name+'.log')).read_text();assert 'ERROR:' not in s and 'leak' not in s.lower(),s
rows=[x.split(' ',1)[1] for x in s.splitlines() if x.startswith('HINGE_RESULT ')];assert len(rows)==1
r=json.loads(rows[0]);assert r['failed']==0
s=(p/'negative.log').read_text();errors=[x for x in s.splitlines() if x.startswith('ERROR:')]
expected=[line.removeprefix('EXPECT_HINGE_ERROR ') for line in s.splitlines() if line.startswith('EXPECT_HINGE_ERROR ')]
assert len(errors)==len(expected)==16,(errors,expected)
for message in expected:
 matches=[line for line in errors if message in line]
 assert matches,(message,errors)
 errors.remove(matches[0])
assert 'leak' not in s.lower() and 'SCRIPT ERROR:' not in s
negative=json.loads(next(line.split(' ',1)[1] for line in s.splitlines() if line.startswith('HINGE_NEGATIVE_RESULT ')))
assert negative['failed']==0
r['negative']=negative;r['expected_rejections']=len(expected)
input_result=json.loads(next(line.split(' ',1)[1] for line in (p/'input-smoke.log').read_text().splitlines() if line.startswith('DEMO_INPUT_RESULT ')))
assert input_result=={'passed':11,'failed':0},input_result
r['input_smoke']=input_result
r['extension_sha256']=hashlib.sha256((p/'project/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').read_bytes()).hexdigest()
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('HINGE PASS',r['passed'],'positive',r['negative']['passed'],'negative',p)
PY
