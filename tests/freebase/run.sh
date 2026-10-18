#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-freebase.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp "$ROOT/tests/freebase/acceptance.gd" "$ROOT/tests/portable_runtime/project.godot" "$OUT/project/"
cp -a "$ROOT/demo/addons" "$ROOT/demo/assets" "$OUT/project/"
timeout --kill-after=5 120 "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://acceptance.gd > "$OUT/runtime.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);s=(p/'runtime.log').read_text()
r=json.loads(next(x.removeprefix('FREEBASE_RESULT ') for x in s.splitlines() if x.startswith('FREEBASE_RESULT ')))
assert r['failed']==0,r
for f in p.glob('*.log'):
 s=f.read_text();assert 'ERROR:' not in s and 'leaked' not in s,f
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n')
print('FREEBASE PASS',r['passed'],p)
PY
