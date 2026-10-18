#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-runtime.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || { echo 'Use a fresh OUT directory' >&2; exit 2; }
mkdir -p "$OUT/project"
cp -a "$ROOT/tests/portable_runtime/". "$OUT/project/"
cp -a "$ROOT/demo/addons" "$ROOT/demo/assets" "$OUT/project/"
printf '\n[dotnet]\nproject/assembly_name="PortableRuntime"\n' >> "$OUT/project/project.godot"
timeout --kill-after=5 120 "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://prepare_runtime.gd > "$OUT/author.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://runtime_test.gd > "$OUT/runtime.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib,shutil,sys
p=pathlib.Path(sys.argv[1]);shutil.copytree(p/'project',p/'relocated',ignore=shutil.ignore_patterns('.godot','obj','.staging_*'))
# Both the old project path and the relocated original model source path disappear.
(p/'project').rename(p/'project.offline');shutil.rmtree(p/'relocated/assets')
for name in ['multi.xml','conflict.xml']:(p/'relocated'/name).unlink()
PY
timeout --kill-after=5 120 "$ROOT/scripts/import_headless.sh" "$OUT/relocated" > "$OUT/relocated-import.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/relocated" --script res://runtime_test.gd > "$OUT/relocated-runtime.log" 2>&1
timeout --kill-after=5 90 "$GODOT_BIN" --headless --path "$OUT/relocated" --script res://recovery_integrity_test.gd > "$OUT/recovery-integrity.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/relocated" --script res://live_edit_test.gd > "$OUT/live-edit.log" 2>&1
timeout --kill-after=5 180 dotnet build "$OUT/relocated/PortableRuntime.csproj" -c Debug > "$OUT/dotnet-build.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/relocated" res://RuntimeBinding.tscn > "$OUT/csharp.log" 2>&1
cp "$ROOT/tests/portable_runtime/editor_acceptance.gd" "$OUT/relocated/acceptance.gd"
printf '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/mujoco_editor/plugin.cfg")\n' >> "$OUT/relocated/project.godot"
timeout --kill-after=5 120 "$GODOT_BIN" --headless --editor --path "$OUT/relocated" -- --mj-editor-test > "$OUT/editor-flow.log" 2>&1
timeout --kill-after=5 90 "$GODOT_BIN" --headless --path "$OUT/relocated" --script res://restart_editor_scene.gd > "$OUT/editor-scene-restart.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);results={}
for name in ['runtime','relocated-runtime']:
 s=(p/(name+'.log')).read_text();r=json.loads(next(x.split(' ',1)[1] for x in s.splitlines() if x.startswith('RUNTIME_RESULT ')));assert r['failed']==0,r;results[name]=r
live=json.loads(next(x.split(' ',1)[1] for x in (p/'live-edit.log').read_text().splitlines() if x.startswith('LIVE_EDIT_RESULT ')));assert live['failed']==0,live;results['live-edit']=live
editor=json.loads(next(x.split(' ',1)[1] for x in (p/'editor-flow.log').read_text().splitlines() if x.startswith('PORTABLE_EDITOR_RESULT ')));assert editor['failed']==0,editor;results['editor']=editor
assert 'EDITOR_SCENE_RESTART_PASS' in (p/'editor-scene-restart.log').read_text()
assert 'PORTABLE CSHARP PASS' in (p/'csharp.log').read_text()
edge=(p/'recovery-integrity.log').read_text()
e=json.loads(next(x.split(' ',1)[1] for x in edge.splitlines() if x.startswith('RECOVERY_INTEGRITY_RESULT ')));assert e['failed']==0,e;results['recovery-integrity']=e
expected=['ERROR: Assign a world_model resource to define all global MuJoCo options','ERROR: Only one MjRuntimeWorld may own a World3D; use a separate SubViewport for another world']
assert [x for x in edge.splitlines() if x.startswith('ERROR:')]==expected
violations=[]
for f in p.glob('*.log'):
 s=f.read_text()
 if 'ERROR:' in s or 'leaked' in s: violations.append(f.name)
results['strict_log_failures']=violations
(p/'results.json').write_text(json.dumps(results,indent=2)+'\n')
assert not violations, violations
print('PORTABLE RUNTIME PASS; original project and source assets unavailable;',p)
PY
