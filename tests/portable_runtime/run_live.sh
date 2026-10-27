#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-live.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || { echo 'Use a fresh OUT directory' >&2; exit 2; }
mkdir -p "$OUT/project"
cp "$ROOT/tests/portable_runtime/"*.gd "$ROOT/tests/portable_runtime/project.godot" "$OUT/project/"
cp -a "$ROOT/addons" "$ROOT/assets" "$OUT/project/"
timeout --kill-after=5 120 "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://prepare_runtime.gd > "$OUT/author.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://live_edit_test.gd > "$OUT/live-edit.log" 2>&1
cp "$ROOT/tests/portable_runtime/live_editor_acceptance.gd" "$OUT/project/acceptance.gd"
printf '\n[editor]\nrun/main_run_args="--headless"\n[editor_plugins]\nenabled=PackedStringArray("res://addons/mujoco_editor/plugin.cfg")\n' >> "$OUT/project/project.godot"
timeout --kill-after=5 150 "$GODOT_BIN" --headless --editor --path "$OUT/project" -- --mj-editor-test > "$OUT/live-editor.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);results={}
for name,marker in [('live-edit','LIVE_EDIT_RESULT '),('live-editor','LIVE_EDITOR_RESULT ')]:
 s=(p/(name+'.log')).read_text();r=json.loads(next(x[len(marker):] for x in s.splitlines() if x.startswith(marker)));assert r['failed']==0,r;results[name]=r
for f in p.glob('*.log'):
 s=f.read_text();assert 'ERROR:' not in s and 'leaked' not in s,f
(p/'results.json').write_text(json.dumps(results,indent=2)+'\n')
print('LIVE EDIT PASS;',p)
PY
