#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-sweep-precision.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_sweep_precision/"{project.godot,acceptance.gd} "$OUT/project/"
cp -a "$ROOT/demo/addons" "$OUT/project/"
timeout 120 bash "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
for i in 1 2 3; do
 timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://acceptance.gd > "$OUT/positive-$i.log" 2>&1
done
python3 - "$OUT" <<'PY'
import json,pathlib,sys,hashlib
p=pathlib.Path(sys.argv[1]);runs=[]
for log in p.glob('*.log'):
 s=log.read_text();assert 'ERROR:' not in s and 'leak' not in s.lower() and 'WARNING:' not in s,(log,s)
 if log.name.startswith('positive-'):
  r=json.loads(next(x.split(' ',1)[1] for x in s.splitlines() if x.startswith('SWEEP_PRECISION_RESULT ')))
  assert r=={'passed':864,'failed':0},r
  runs.append(r)
assert len(runs)==3
r={'runs':runs,'extension_sha256':hashlib.sha256((p/'project/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').read_bytes()).hexdigest()}
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n')
print('SWEEP PRECISION PASS 864 x3',p)
PY
