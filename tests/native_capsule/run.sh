#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-capsule.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || { echo "Use a fresh OUT directory" >&2; exit 2; }
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_capsule/"{project.godot,acceptance.gd,negative.gd} "$OUT/project/"
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
for i in 1 2 3; do
 run_stage "positive-$i" "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://acceptance.gd
done
run_stage negative "$GODOT_BIN" --headless --path "$OUT/project" --script res://negative.gd
python3 - "$OUT" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1])
def result(name,prefix):
 text=(p/(name+'.log')).read_text()
 rows=[line.split(' ',1)[1] for line in text.splitlines() if line.startswith(prefix+' ')]
 assert len(rows)==1,(name,rows)
 return json.loads(rows[0])
for name in ['import','positive-1','positive-2','positive-3']:
 text=(p/(name+'.log')).read_text()
 assert 'ERROR:' not in text and 'leak' not in text.lower(),(name,text)
 if name!='import':
  assert 'unsupported' not in text.lower(),(name,text)
runs=[result('positive-'+str(i),'CAPSULE_RESULT') for i in range(1,4)]
for r in runs:
 assert r['failed']==0 and r['passed']==150,r
 assert r['passed']==sum(r['counts'].values()),r
assert all(r['counts']==runs[0]['counts'] for r in runs),runs
negative=(p/'negative.log').read_text()
r=result('negative','CAPSULE_NEGATIVE_RESULT')
assert r['failed']==0 and r['expected_errors']==11 and r['sweep_rejections']==2,r
assert 'SCRIPT ERROR:' not in negative and 'leak' not in negative.lower(),negative
errors=[line for line in negative.splitlines() if line.startswith('ERROR:')]
assert len(errors)==11,errors
allowed=[
 'Capsule data requires radius and height',
 'Capsule dimensions must be numeric',
 'Capsule dimensions must be finite and positive',
 'Capsule height must be at least twice radius',
 'MuJoCo minimal backend requires unscaled rigid transforms; set shape dimensions instead',
]
assert all(any(fragment in error for fragment in allowed) for error in errors),errors
warnings=[line for line in negative.splitlines() if line.startswith('WARNING:')]
allowed_warnings=['continuous sweep contact has no certified float safe/unsafe poses','continuous sweep numerical bracket could not be certified']
assert 1<=len(warnings)<=2 and all(any(fragment in warning for fragment in allowed_warnings) for warning in warnings),warnings
report={'runs':runs,'negative':r,'extension_sha256':hashlib.sha256((p/'project/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').read_bytes()).hexdigest()}
(p/'results.json').write_text(json.dumps(report,indent=2)+'\n')
print('CAPSULE PASS',runs[0]['passed'],'x3,',r['checks'],'negative checks;',p)
PY
