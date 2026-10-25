#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-passive-g1-test.XXXXXX)}"
export OUT GODOT_BIN
bash "$ROOT/examples/g1_passive/prepare.sh"
cp "$ROOT/tests/g1_passive/acceptance.gd" "$ROOT/tests/g1_passive/initial_failure.gd" "$OUT/project/"
if [[ -d "$OUT/project/assets/robots" ]]; then mv "$OUT/project/assets/robots" "$OUT/unavailable-original-robots"; fi
timeout --kill-after=5 90 "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://initial_failure.gd > "$OUT/initial_failure.log" 2>&1
timeout --kill-after=5 150 "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://acceptance.gd > "$OUT/runtime.log" 2>&1
python3 - "$OUT" <<'PY'
import json,pathlib,sys,os,re
p=pathlib.Path(sys.argv[1]);s=(p/'runtime.log').read_text()
rows=[x.split(' ',1)[1] for x in s.splitlines() if x.startswith('G1_PASSIVE_RESULT ')];assert len(rows)==1,s
r=json.loads(rows[0]);assert r['failed']==0,r
bad=[x.split(' ',1)[1] for x in (p/'initial_failure.log').read_text().splitlines() if x.startswith('G1_INITIAL_FAILURE_RESULT ')];assert len(bad)==1
r['initial_failure']=json.loads(bad[0]);assert r['initial_failure']['failed']==0
for f in p.glob('*.log'):
 t=f.read_text();assert 'SCRIPT ERROR:' not in t and '\nERROR:' not in t and 'leaked' not in t,str(f)
stages=[json.loads(x.split(' ',1)[1]) for x in s.splitlines() if x.startswith('G1_ADD_STAGE ')]
loads=[json.loads(x.split(' ',1)[1]) for x in s.splitlines() if x.startswith('MJ_MODEL_LOAD_STAGE ')]
assert {'await_frame_1','await_frame_2','frames_ready','add_child_begin','add_child_end','capture_after_end','overlay_begin','overlay_end','add_returned'} <= {x['stage'] for x in stages}
assert {'validate_package_begin','validate_package_end','native_scene_load_begin','native_scene_load_end','visual_geometry_begin','visual_geometry_end','visual_nodes_end'} <= {x['stage'] for x in loads}
r['diagnostic_stages']={'add':stages,'load':loads}
if os.environ.get('GMJ_TRACE_SCENE_LOAD')=='1':
 native=re.findall(r'MJ_NATIVE_LOAD_STAGE id=(\d+) elapsed_ms=(\d+) stage=(\S+)',s);assert native,'native diagnostics missing'
 last=max(int(x[0]) for x in native);finished={x[2] for x in native if int(x[0])==last}
 assert {'document.compile_end','document.make_data_end','document.forward_end','load.take_spec_end','rebuild.compile_end','rebuild.transfer_end','rebuild.forward_end','rebuild.old_delete_end','document.destroy_end','load.exit'} <= finished,finished
 r['native_last_load']=[x for x in native if int(x[0])==last]
 if os.environ.get('GMJ_DIAGNOSTIC_SERIAL_COMPILE')=='1':
  assert 'rebuild.diagnostic_serial_compile' in finished
  assert re.search(rf'id={last} .*stage=rebuild.compile_begin a=0 ',s), 'serial compiler flag not applied'

r['hot_add']=[json.loads(x.split(' ',1)[1]) for x in s.splitlines() if x.startswith('G1_HOT_ADD ')][0]
r['memory']=[x for x in s.splitlines() if x.startswith('G1_MEMORY ')]
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('G1 PASSIVE PASS',{k:v for k,v in r.items() if k not in ['diagnostic_stages','native_last_load']},p)
PY
