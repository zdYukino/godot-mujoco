#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-contact.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || { echo "Use a fresh OUT directory" >&2; exit 2; }
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_contacts/"{project.godot,acceptance.gd,gui.gd,negative.gd} "$OUT/project/"
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
python3 - "$OUT" <<'PY'
import pathlib,sys,json,hashlib
p=pathlib.Path(sys.argv[1])
for name in ['import','gui-smoke','positive']:
 s=(p/(name+'.log')).read_text();assert 'ERROR:' not in s and 'leak' not in s.lower(),s
rows=[x.split(' ',1)[1] for x in s.splitlines() if x.startswith('CONTACT_RESULT ')];assert len(rows)==1
r=json.loads(rows[0]);assert r['failed']==0
s=(p/'negative.log').read_text();errors=[x for x in s.splitlines() if x.startswith('ERROR:')]
assert len(errors)==1 and 'n<0' in errors[0] and 'CONTACT_NEGATIVE_RESULT true' in s and 'leak' not in s.lower() and 'SCRIPT ERROR:' not in s,s
r['expected_rejections']=1
r['extension_sha256']=hashlib.sha256((p/'project/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').read_bytes()).hexdigest()
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('CONTACT PASS',r)
PY
