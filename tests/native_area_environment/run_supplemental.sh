#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-area-env-extra.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_area_environment/"{project.godot,acceptance.gd,supplemental.gd} "$OUT/project/"
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
run_stage supplemental "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://supplemental.gd
python3 - "$OUT" <<'PY'
import pathlib,sys,json,hashlib
p=pathlib.Path(sys.argv[1])
for name in ['import','supplemental']:
 s=(p/(name+'.log')).read_text();assert 'ERROR:' not in s and 'leak' not in s.lower(),s
r=json.loads(next(line.split(' ',1)[1] for line in s.splitlines() if line.startswith('AREA_ENVIRONMENT_SUPPLEMENTAL_RESULT ')))
assert r['failed']==0
r['extension_sha256']=hashlib.sha256((p/'project/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').read_bytes()).hexdigest()
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('AREA ENVIRONMENT SUPPLEMENTAL PASS',r)
PY
