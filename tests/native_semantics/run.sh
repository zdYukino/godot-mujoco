#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-semantics.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_semantics/"{project.godot,acceptance.gd,negative.gd} "$OUT/project/"
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
python3 - "$OUT" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1])
for name in ['import','positive']:
 s=(p/(name+'.log')).read_text();assert 'ERROR:' not in s and 'leak' not in s.lower(),name
rows=[line.split(' ',1)[1] for line in (p/'positive.log').read_text().splitlines() if line.startswith('NATIVE_SEMANTICS_RESULT ')]
assert len(rows)==1
r=json.loads(rows[0]);assert r['failed']==0
s=(p/'negative.log').read_text()
assert 'SCRIPT ERROR:' not in s and 'leak' not in s.lower()
expected=[line.removeprefix('EXPECT_NATIVE_ERROR ') for line in s.splitlines() if line.startswith('EXPECT_NATIVE_ERROR ')]
errors=[line for line in s.splitlines() if line.startswith('ERROR:')]
assert len(errors)==len(expected)==21,(errors,expected)
for message in expected:
 matches=[line for line in errors if message.replace(" ", "") in line.replace(" ", "")]
 assert matches,(message,errors)
 errors.remove(matches[0])
negative=json.loads(next(line.split(' ',1)[1] for line in s.splitlines() if line.startswith('NATIVE_SEMANTICS_NEGATIVE_RESULT ')))
assert negative['failed']==0
r['negative']=negative
r['expected_errors']=len(expected)
r['extension_sha256']=hashlib.sha256((p/'project/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').read_bytes()).hexdigest()
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('NATIVE SEMANTICS PASS',r['passed'],p)
PY
