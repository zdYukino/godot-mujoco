#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-light-workflow.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp "$ROOT/examples/light_workflow/"{prepare.gd,project.godot,Main.tscn,LightWorkflow.cs,LightWorkflow.csproj} "$OUT/project/"
cp -a "$ROOT/addons" "$OUT/project/"
run_stage() {
 local stage="$1" code; shift
 set +e
 timeout --kill-after=5 180 "$@" > "$OUT/$stage.log" 2>&1
 code=$?
 set -e
 printf '%s\t%s\n' "$stage" "$code" >> "$OUT/executions.tsv"
 [[ "$code" == 0 ]] || { echo "$stage failed ($code): $OUT/$stage.log" >&2; return "$code"; }
}
run_stage import bash "$ROOT/scripts/import_headless.sh" "$OUT/project"
run_stage prepare "$GODOT_BIN" --headless --path "$OUT/project" --script res://prepare.gd
run_stage build dotnet build "$OUT/project/LightWorkflow.csproj" -c Debug
run_stage runtime "$GODOT_BIN" --headless --path "$OUT/project" -- --self-test
python3 - "$OUT" <<'PY'
import pathlib,json,sys,xml.etree.ElementTree as ET
p=pathlib.Path(sys.argv[1])
for f in p.glob('*.log'):
 s=f.read_text();assert 'ERROR:' not in s and 'leak' not in s.lower(),f
rows=[x.split(' ',1)[1] for x in (p/'runtime.log').read_text().splitlines() if x.startswith('LIGHT_WORKFLOW_RESULT ')];assert len(rows)==1
r=json.loads(rows[0]);assert r['failed']==0
models=list((p/'project/models').glob('typed*/model.xml'));assert models
for model in models:
 root=ET.parse(model).getroot()
 assert root.find('compiler').get('angle')=='radian'
 joint=root.find(".//joint[@name='hinge']")
 assert [float(x) for x in joint.get('range').split()]==[-1.0,1.0],model
r['packaged_radian_limits_verified']=True
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('LIGHT WORKFLOW PASS',r)
PY
