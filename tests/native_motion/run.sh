#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-motion.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || { echo "Use a fresh OUT directory" >&2;exit 2; }
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_motion/"{project.godot,rid.gd,character.gd,kinematic_reset.gd} "$OUT/project/"
cp -a "$ROOT/addons" "$OUT/project/"
run_stage() {
 local stage="$1" code;shift
 set +e
 timeout --kill-after=5 150 "$@" > "$OUT/$stage.log" 2>&1
 code=$?
 set -e
 printf '%s\t%s\n' "$stage" "$code" >> "$OUT/executions.tsv"
 if [[ "$code" != 0 ]];then echo "$stage failed ($code): $OUT/$stage.log" >&2;return "$code";fi
}
run_stage import bash "$ROOT/scripts/import_headless.sh" "$OUT/project"
# Run both independent tests even when one fails; retain CharacterBody evidence.
failed=0
for i in 1;do
 run_stage "rid-$i" "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://rid.gd || failed=1
 run_stage "character-$i" "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://character.gd || failed=1
done
run_stage kinematic-reset "$GODOT_BIN" --headless --path "$OUT/project" --script res://kinematic_reset.gd || failed=1
python3 - "$OUT" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1]);runs=[];problems=[]
for log in p.glob('*.log'):
 text=log.read_text()
 if 'ERROR:' in text or 'leak' in text.lower() or 'unsupported' in text.lower():problems.append(str(log))
for group,prefix in [('rid','MOTION_RID_RESULT'),('character','MOTION_CHARACTER_RESULT')]:
 for i in range(1,2):
  log=p/f'{group}-{i}.log'
  rows=[line.split(' ',1)[1] for line in log.read_text().splitlines() if line.startswith(prefix+' ')]
  if len(rows)!=1:problems.append(f'{log}: expected one result');continue
  result=json.loads(rows[0]);runs.append({'test':group,'repeat':i,**result})
  if result['failed']!=0:problems.append(f'{log}: {result["failed"]} failed assertions')
reset_log=p/'kinematic-reset.log'
reset=json.loads(next(line.split(' ',1)[1] for line in reset_log.read_text().splitlines() if line.startswith('KINEMATIC_RESET_RESULT ')))
if reset['failed'] or reset['passed']!=11:problems.append('kinematic reset regression failed')
report={'kinematic_reset':reset,'runs':runs,'problems':problems,'extension_sha256':hashlib.sha256((p/'project/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').read_bytes()).hexdigest()}
(p/'results.json').write_text(json.dumps(report,indent=2)+'\n')
print('MOTION', 'FAIL' if problems else 'PASS',[(r['test'],r['passed'],r['failed']) for r in runs],p)
if problems:raise SystemExit(1)
PY
[[ "$failed" == 0 ]]
