#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-static-map.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp "$ROOT/tests/static_map/"{project.godot,acceptance.gd,reopen.gd,verify_damage.gd} "$OUT/project/"
cp -a "$ROOT/demo/addons" "$OUT/project/"
run_stage() {
 local stage="$1" code; shift
 set +e
 timeout --kill-after=5 150 "$@" > "$OUT/$stage.log" 2>&1
 code=$?
 set -e
 printf '%s\t%s\n' "$stage" "$code" >> "$OUT/executions.tsv"
 [[ "$code" == 0 ]] || { echo "$stage failed ($code): $OUT/$stage.log" >&2; return "$code"; }
}
run_stage import bash "$ROOT/scripts/import_headless.sh" "$OUT/project"
python3 "$ROOT/tests/static_map/fixtures.py" "$OUT/project/fixtures"
run_stage positive "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://acceptance.gd
run_stage reopen "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://reopen.gd
# Remove only generated fixture inputs; move the immutable bundle to a new location.
python3 - "$OUT/project" <<'PY'
import pathlib,shutil,sys
p=pathlib.Path(sys.argv[1]);src=p/'fixtures';shutil.rmtree(src)
old=(p/'saved_path.txt').read_text().strip();folder=p/old.removeprefix('res://');dest=p/'relocated'/'map';dest.parent.mkdir();folder.rename(dest)
(p/'saved_path.txt').write_text('res://relocated/map')
PY
run_stage relocated "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://reopen.gd
run_stage damaged "$GODOT_BIN" --headless --path "$OUT/project" --script res://verify_damage.gd
python3 - "$OUT" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);results={}
for stage,prefix in [('positive','STATIC_MAP_RESULT '),('reopen','STATIC_MAP_REOPEN '),('relocated','STATIC_MAP_REOPEN ')]:
 s=(p/(stage+'.log')).read_text();rows=[line[len(prefix):] for line in s.splitlines() if line.startswith(prefix)];assert len(rows)==1,(stage,s)
 r=json.loads(rows[0]);assert r['failed']==0,(stage,r);results[stage]=r
 assert 'SCRIPT ERROR:' not in s and 'leak' not in s.lower(),(stage,s)
 # Invalid source XML is deliberately rejected by native importer without engine error.
 assert 'ERROR:' not in s,(stage,s)
damage=(p/'damaged.log').read_text();assert 'STATIC_MAP_DAMAGE 6 passed' in damage and 'ERROR:' not in damage
results['dependency_diagnostics']={'passed':6,'failed':0}
(p/'results.json').write_text(json.dumps(results,indent=2)+'\n');print('STATIC MAP PASS',p,results)
PY
