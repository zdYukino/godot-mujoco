#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-overlap-witness.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || { echo "Use a fresh OUT directory" >&2; exit 2; }
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_overlap_witness/"{project.godot,acceptance.gd} "$OUT/project/"
cp -a "$ROOT/demo/addons" "$OUT/project/"
run_stage() {
 local stage="$1" code; shift
 set +e
 timeout --kill-after=5 120 "$@" > "$OUT/$stage.log" 2>&1
 code=$?
 set -e
 printf '%s\t%s\n' "$stage" "$code" >> "$OUT/executions.tsv"
 [[ "$code" == 0 ]] || { echo "$stage failed ($code): $OUT/$stage.log" >&2;return "$code"; }
}
run_stage import bash "$ROOT/scripts/import_headless.sh" "$OUT/project"
run_stage positive "$GODOT_BIN" --headless --path "$OUT/project" --script res://acceptance.gd
python3 - "$OUT" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1])
for name in ['import','positive']:
 s=(p/(name+'.log')).read_text();assert 'ERROR:' not in s and 'leak' not in s.lower(),name
rows=[line.split(' ',1)[1] for line in (p/'positive.log').read_text().splitlines() if line.startswith('OVERLAP_WITNESS_RESULT ')]
assert len(rows)==1
r=json.loads(rows[0]);assert r['failed']==0,r
r['extension_sha256']=hashlib.sha256((p/'project/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').read_bytes()).hexdigest()
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n')
print('OVERLAP WITNESS PASS',r['passed'],p)
PY
