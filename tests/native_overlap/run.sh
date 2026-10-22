#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-overlap.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || { echo "Use a fresh OUT directory" >&2; exit 2; }
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_overlap/"{project.godot,acceptance.gd} "$OUT/project/"
cp -a "$ROOT/demo/addons" "$OUT/project/"
timeout 120 bash "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
for i in 1 2 3; do
 timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://acceptance.gd > "$OUT/positive-$i.log" 2>&1
done
python3 - "$OUT" <<'PY'
import pathlib,sys,json
p=pathlib.Path(sys.argv[1])
for log in p.glob('*.log'):
 s=log.read_text();assert 'ERROR:' not in s and 'leak' not in s.lower(),(log,s)
for log in p.glob('positive-*.log'):
 r=json.loads(next(x.split(' ',1)[1] for x in log.read_text().splitlines() if x.startswith('OVERLAP_RESULT ')))
 assert r['failed']==0,r
print('OVERLAP PASS',r,p)
PY
