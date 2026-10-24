#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-hinge-drive.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_hinge_drive/"{project.godot,acceptance.gd,negative.gd,gui.gd,input_smoke.gd,guard.gd,poststep.gd,alias.gd,range_loading.gd} "$OUT/project/"
cp "$ROOT/tests/native_joints/acceptance.gd" "$OUT/project/pin_support.gd"
cp "$ROOT/tests/native_hinge/acceptance.gd" "$OUT/project/hinge_support.gd"
cp "$ROOT/tests/native_hinge/gui.gd" "$OUT/project/passive_gui.gd"
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
run_stage negative "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://negative.gd
run_stage guard "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://guard.gd
run_stage poststep "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://poststep.gd
run_stage alias "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://alias.gd
run_stage range-loading "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://range_loading.gd
run_stage range-negative "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://range_loading.gd -- --negative
run_stage gui-smoke "$GODOT_BIN" --headless --path "$OUT/project" --script res://gui.gd --quit-after 120
run_stage input-smoke "$GODOT_BIN" --headless --path "$OUT/project" --script res://input_smoke.gd
python3 - "$OUT" <<'PY'
import pathlib,sys,json,hashlib
from collections import Counter
p=pathlib.Path(sys.argv[1])
for name in ['import','gui-smoke','input-smoke','range-loading','positive']:
 s=(p/(name+'.log')).read_text();assert 'ERROR:' not in s and 'leak' not in s.lower(),s
r=json.loads(next(x.split(' ',1)[1] for x in s.splitlines() if x.startswith('HINGE_DRIVE_RESULT ')));assert r['failed']==0
s=(p/'negative.log').read_text();assert 'SCRIPT ERROR:' not in s and 'leak' not in s.lower()
errors=[x for x in s.splitlines() if x.startswith('ERROR:')]
expected=[x for x in s.splitlines() if x.startswith('EXPECT_DRIVE_REJECTION ')]
assert len(errors)==len(expected)==10,(errors,expected)
assert Counter(errors)==Counter({
 'ERROR: Native Hinge invalid parameter':1,
 'ERROR: Native Hinge velocity outside supported range':2,
 'ERROR: Native Hinge impulse outside supported range':2,
 'ERROR: Native Hinge invalid limit range':3,
 'ERROR: Native driven Hinge requires isolated rigid endpoints and aligned frame axes':1,
 'ERROR: Native driven Hinge requires configured isolated rigid endpoints and aligned frame axes':1,
}),errors
n=json.loads(next(x.split(' ',1)[1] for x in s.splitlines() if x.startswith('HINGE_DRIVE_NEGATIVE_RESULT ')));assert n['failed']==0
r['negative']=n;r['expected_errors']=len(expected)
s=(p/'input-smoke.log').read_text();i=json.loads(next(x.split(' ',1)[1] for x in s.splitlines() if x.startswith('DEMO_INPUT_RESULT ')));assert i['failed']==0;r['input']=i
s=(p/'guard.log').read_text();assert 'SCRIPT ERROR:' not in s and 'leak' not in s.lower()
errors=[x for x in s.splitlines() if x.startswith('ERROR:')]
assert errors==['ERROR: Native Hinge drive numerical state rejected'],errors
g=json.loads(next(x.split(' ',1)[1] for x in s.splitlines() if x.startswith('HINGE_GUARD_RESULT ')))
assert g['failed']==0 and g['passed']==12,g;r['guard']=g;r['guard_expected_errors']=1
for stage,prefix,count in [('poststep','HINGE_POSTSTEP_RESULT ',18),('alias','HINGE_ALIAS_RESULT ',11)]:
 s=(p/(stage+'.log')).read_text();assert 'SCRIPT ERROR:' not in s and 'leak' not in s.lower()
 errors=[x for x in s.splitlines() if x.startswith('ERROR:')]
 assert errors==['ERROR: Native Hinge drive post-step state rejected']*2,(stage,errors)
 result=json.loads(next(x[len(prefix):] for x in s.splitlines() if x.startswith(prefix)))
 assert result['failed']==0 and result['passed']==count,(stage,result)
 r[stage]=result;r[stage+'_expected_errors']=2
s=(p/'range-loading.log').read_text();result=json.loads(next(x.split(' ',1)[1] for x in s.splitlines() if x.startswith('HINGE_RANGE_LOADING_RESULT ')));assert result['failed']==0;r['range_loading']=result
s=(p/'range-negative.log').read_text();assert 'SCRIPT ERROR:' not in s and 'leak' not in s.lower()
errors=[x for x in s.splitlines() if x.startswith('ERROR:')]
assert Counter(errors)==Counter({'ERROR: Native Hinge invalid limit range':2,'ERROR: Native Hinge invalid parameter':1,'ERROR: Native Hinge incomplete or inverted limit pair; accepted limits retained':3,'ERROR: Native Pin candidate rejected; previous model retained':1}),errors
result=json.loads(next(x.split(' ',1)[1] for x in s.splitlines() if x.startswith('HINGE_RANGE_NEGATIVE_RESULT ')));assert result['failed']==0;r['range_negative']=result;r['range_expected_errors']=7
r['extension_sha256']=hashlib.sha256((p/'project/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').read_bytes()).hexdigest()
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('HINGE DRIVE PASS',r['passed'],n['passed'],p)
PY
