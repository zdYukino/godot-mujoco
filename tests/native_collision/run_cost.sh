#!/usr/bin/env bash
set -euo pipefail
: "${MUJOCO_ROOT:?MuJoCo 3.16.0 required}"
: "${OUT:=$(mktemp -d /tmp/gmj-collision-cost.XXXXXX)}"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$OUT"
g++ -std=c++17 -O2 "$ROOT/tests/native_collision/benchmark.cpp" -I"$MUJOCO_ROOT/include" -L"$MUJOCO_ROOT/lib" -Wl,-rpath,"$MUJOCO_ROOT/lib" -lmujoco -o "$OUT/benchmark"
python3 "$ROOT/tests/static_map/fixtures.py" "$OUT/fixtures"
python3 - "$OUT" <<'PY'
import json,pathlib,subprocess,sys,hashlib
p=pathlib.Path(sys.argv[1]);f=p/'fixtures';parts=json.loads((f/'parts.json').read_text())['room']
probe="<body name='through' pos='0 4 1'><freejoint/><geom type='sphere' size='.2'/></body><body name='blocked' pos='2 4 1'><freejoint/><geom type='sphere' size='.2'/></body>"
results={'version':'3.16.0','steps':750,'timestep':.002,'trials':3,'source_sha256':hashlib.sha256((f/'room.obj').read_bytes()).hexdigest(),'modes':{}}
for mode in ['sdf','mesh','compound_boxes']:
 asset="<asset><mesh name='room' file='room.obj'/></asset>" if mode!='compound_boxes' else ''
 if mode=='compound_boxes':
  geom=''.join("<geom type='box' pos='%s' size='%s'/>"%(' '.join(map(str,[v['center'][0],-v['center'][2],v['center'][1]])),' '.join(str(v['size'][i]/2) for i in [0,2,1])) for v in parts)
 else:geom=f"<geom name='room' type='{mode}' mesh='room' quat='.707106781 .707106781 0 0'/>"
 path=f/(mode+'.xml');path.write_text("<mujoco><option gravity='0 0 0' timestep='.002' sdf_iterations='20' sdf_initpoints='40'/>"+asset+'<worldbody>'+geom+probe+'</worldbody></mujoco>')
 trials=[]
 for _ in range(3):
  r=json.loads(subprocess.check_output([str(p/'benchmark'),str(path)],text=True,timeout=60));assert r['target_force_max']>0 and r['target_normal_ok'];assert (r['through_y']>3.2 if mode=='mesh' else r['through_y']<2);trials.append(r)
 results['modes'][mode]=trials
(p/'results.json').write_text(json.dumps(results,indent=2)+'\n');print('BOUNDED COST PASS',p)
PY
