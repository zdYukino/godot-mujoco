#!/usr/bin/env bash
# Separate capability gate. Does not enable SDF in the Godot backend/editor.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${MUJOCO_ROOT:?Set MUJOCO_ROOT to the exact MuJoCo 3.16.0 distribution}"
: "${OUT:=$(mktemp -d /tmp/gmj-sdf-probe.XXXXXX)}"
mkdir -p "$OUT"
g++ -std=c++17 -O2 "$ROOT/tests/static_map/sdf_probe.cpp" -I"$MUJOCO_ROOT/include" -L"$MUJOCO_ROOT/lib" -Wl,-rpath,"$MUJOCO_ROOT/lib" -lmujoco -o "$OUT/probe"
python3 "$ROOT/tests/static_map/fixtures.py" "$OUT/fixtures"
python3 - "$OUT/fixtures" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);xml='''<mujoco><option timestep=".002" gravity="0 0 0" sdf_iterations="20" sdf_initpoints="40"/><asset><mesh name="room" file="room.obj"/></asset><worldbody><geom name="room" type="sdf" mesh="room" quat=".707106781 .707106781 0 0"/><body name="through" pos="0 4 1"><freejoint/><geom type="sphere" size=".2" mass="1"/></body><body name="blocked" pos="2 4 1"><freejoint/><geom type="sphere" size=".2" mass="1"/></body></worldbody></mujoco>'''
(p/'room_sdf.xml').write_text(xml);(p/'room_convex.xml').write_text(xml.replace('type="sdf"','type="mesh"'))
PY
timeout 90 "$OUT/probe" "$OUT/fixtures/room_sdf.xml" 750 > "$OUT/room_sdf.log" 2>&1
set +e
timeout 90 "$OUT/probe" "$OUT/fixtures/room_convex.xml" 750 > "$OUT/room_convex.log" 2>&1
code=$?
set -e
[[ "$code" == 3 ]] || { echo "Expected convex door closure (exit 3), got $code" >&2; exit 1; }
timeout 90 "$OUT/probe" "$MUJOCO_ROOT/model/plugin/sdf/cow.xml" 100 "$MUJOCO_ROOT/bin/mujoco_plugin/libsdf_plugin.so" > "$OUT/cow.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib,sys,json,re
p=pathlib.Path(sys.argv[1]);results={}
for key in ['room_sdf','room_convex','cow']:
 s=(p/(key+'.log')).read_text();line=next(x for x in s.splitlines() if x.startswith('SDF_PROBE '));d=dict(re.findall(r'(\w+)=([^ ]+)',line));assert d['version']=='3.16.0';results[key]=d
assert 'plugin=-1' in (p/'room_sdf.log').read_text()
assert 'cow1 plugin=-1' in (p/'cow.log').read_text()
(p/'results.json').write_text(json.dumps(results,indent=2)+'\n');print('SDF NATIVE CAPABILITY GATE PASS (not Godot integration)',p)
PY
