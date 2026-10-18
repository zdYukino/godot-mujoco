#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:?Use a fresh absolute OUT directory}"
: "${DISPLAY:?A real X11 display with XTEST is required}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp -a "$ROOT/tests/editor_plugin/". "$OUT/project/"
cp -a "$ROOT/demo/addons" "$OUT/project/"
cp "$ROOT/tests/editor_plugin/mouse_probe.gd" "$OUT/project/acceptance.gd"
timeout --kill-after=5 120 "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
timeout --kill-after=5 240 "$GODOT_BIN" --editor --path "$OUT/project" --rendering-method gl_compatibility --audio-driver Dummy --resolution 1600x1000 -- --mj-editor-test --probe-dir="$OUT" > "$OUT/editor.log" 2>&1 &
editor_pid=$!
trap 'kill "$editor_pid" 2>/dev/null || true' EXIT
set +e
timeout --kill-after=5 180 python3 "$ROOT/tests/editor_plugin/mouse_acceptance.py" "$OUT" > "$OUT/mouse-driver.log" 2>&1
mouse_exit=$?
wait "$editor_pid"
editor_exit=$?
set -e
trap - EXIT
python3 - "$OUT" "$mouse_exit" "$editor_exit" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);rc=list(map(int,sys.argv[2:]));checks=json.loads((p/'mouse-results.json').read_text());errors=[]
for f in p.glob('*.log'):
 for i,l in enumerate(f.read_text().splitlines(),1):
  if 'ERROR:' in l or 'leaked' in l:errors.append({'file':f.name,'line':i,'text':l})
r={'mouse_exit':rc[0],'editor_exit':rc[1],'passed':sum(c['passed'] for c in checks),'failed':sum(not c['passed'] for c in checks),'diagnostics':errors};(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print(r)
assert rc==[0,0] and checks and all(c['passed'] for c in checks) and not errors
PY
