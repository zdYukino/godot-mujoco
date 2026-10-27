#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-motion-negative.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp "$ROOT/tests/native_motion/"{project.godot,negative.gd} "$OUT/project/"
cp -a "$ROOT/addons" "$OUT/project/"
timeout 120 bash "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://negative.gd > "$OUT/negative.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);s=(p/'negative.log').read_text()
for log in p.glob('*.log'):
 text=log.read_text();assert 'ERROR:' not in text and 'leak' not in text.lower(),(log,text)
r=json.loads(next(x.split(' ',1)[1] for x in s.splitlines() if x.startswith('MOTION_NEGATIVE_RESULT ')))
assert r=={'passed':12,'failed':0},r
warnings=[x for x in s.splitlines() if x.startswith('WARNING:')]
expected=['body motion moving shapes (sphere/capsule only)','body motion invalid input or missing space','body motion recovery did not converge','continuous sweep contact has no certified float safe/unsafe poses','body motion continuous sweep could not be certified','body motion rounded path introduced an uncertified collision','body motion unsafe body pose has no certified contact']
assert len(warnings)==len(expected) and all(any(e in w for w in warnings) for e in expected),warnings
(p/'results.json').write_text(json.dumps({'result':r,'warnings':warnings},indent=2)+'\n')
print('MOTION NEGATIVE PASS',r)
PY
