#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:?Use a fresh absolute OUT directory}"
: "${DISPLAY:?A real X11 display with XTEST is required}"
bash "$ROOT/tests/freebase/run.sh"
cp "$ROOT/tests/freebase/prepare_playground.gd" "$ROOT/tests/freebase/prepare_gui_contacts.gd" "$ROOT/tests/freebase/gui_probe.gd" "$OUT/project/"
for script in prepare_playground prepare_gui_contacts; do
 timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script "res://$script.gd" > "$OUT/$script.log" 2>&1
done
mkdir "$OUT/gui"
timeout --kill-after=5 240 "$GODOT_BIN" --path "$OUT/project" --rendering-method gl_compatibility --audio-driver Dummy --resolution 1600x1000 --script res://gui_probe.gd -- --probe-dir="$OUT/gui" > "$OUT/gui/runtime.log" 2>&1 &
game_pid=$!
trap 'kill "$game_pid" 2>/dev/null || true' EXIT
set +e
timeout --kill-after=5 180 python3 "$ROOT/tests/freebase/gui_acceptance.py" "$OUT/gui" > "$OUT/gui/mouse-driver.log" 2>&1
mouse_exit=$?
wait "$game_pid"
game_exit=$?
set -e
trap - EXIT
python3 - "$OUT" "$mouse_exit" "$game_exit" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);rc=list(map(int,sys.argv[2:]));checks=json.loads((p/'gui/mouse-results.json').read_text());diagnostics=[]
for f in list(p.glob('*.log'))+list((p/'gui').glob('*.log')):
 for i,l in enumerate(f.read_text().splitlines(),1):
  if 'ERROR:' in l or 'leaked' in l:diagnostics.append({'file':str(f.relative_to(p)),'line':i,'text':l})
r={'mouse_exit':rc[0],'game_exit':rc[1],'passed':sum(c['passed'] for c in checks),'failed':sum(not c['passed'] for c in checks),'diagnostics':diagnostics};(p/'gui/results.json').write_text(json.dumps(r,indent=2)+'\n');print(r)
assert rc==[0,0] and checks and all(c['passed'] for c in checks) and not diagnostics
PY
