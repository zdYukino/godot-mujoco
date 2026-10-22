#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-sweep.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || { echo "Use a fresh OUT directory" >&2; exit 2; }
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_sweep/"{project.godot,acceptance.gd,negative.gd} "$OUT/project/"
cp -a "$ROOT/demo/addons" "$OUT/project/"
timeout 120 bash "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
for i in 1 2 3; do
 timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://acceptance.gd > "$OUT/positive-$i.log" 2>&1
done
timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://negative.gd > "$OUT/negative.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib,sys,json
p=pathlib.Path(sys.argv[1])
for log in p.glob('*.log'):
 s=log.read_text();assert 'ERROR:' not in s and 'leak' not in s.lower(),(log,s)
for log in p.glob('positive-*.log'):
 r=json.loads(next(x.split(' ',1)[1] for x in log.read_text().splitlines() if x.startswith('SWEEP_RESULT ')))
 assert r['failed']==0,r
s=(p/'negative.log').read_text()
assert 'SWEEP_NEGATIVE_RESULT PASS' in s
warnings=[line for line in s.splitlines() if line.startswith('WARNING:')]
assert len(warnings)==3 and any('continuous sweep pair' in x for x in warnings) and any('Area3D' in x for x in warnings) and any('float safe/unsafe' in x for x in warnings),warnings
print('SWEEP PASS',r,'5 explicit rejection cases',p)
PY
