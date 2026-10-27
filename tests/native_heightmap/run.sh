#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-heightmap.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_heightmap/"{project.godot,acceptance.gd,negative.gd,Main.tscn,gui.gd} "$OUT/project/"
cp -a "$ROOT/addons" "$OUT/project/"
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
python3 - "$OUT" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1])
for name in ['import','positive']:
 s=(p/(name+'.log')).read_text();assert 'ERROR:' not in s and 'leak' not in s.lower(),name
s=(p/'positive.log').read_text();rows=[x.split(' ',1)[1] for x in s.splitlines() if x.startswith('HEIGHTMAP_RESULT ')];assert len(rows)==1
r=json.loads(rows[0]);assert r['failed']==0
s=(p/'negative.log').read_text();assert 'HEIGHTMAP_NEGATIVE_RESULT 12 rejected inputs; old data retained' in s and 'SCRIPT ERROR:' not in s and 'leak' not in s.lower()
errors=[x for x in s.splitlines() if x.startswith('ERROR:')];assert len(errors)==12,errors
allowed=['HeightMap requires','HeightMap dimensions','HeightMap samples','MuJoCo minimal backend requires unscaled rigid transforms']
assert all(any(t in x for t in allowed) for x in errors),errors
r['expected_rejections']=12
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('HEIGHTMAP PASS',r)
PY
