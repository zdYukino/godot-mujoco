#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-runtime.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || { echo 'Use a fresh OUT directory' >&2; exit 2; }
mkdir -p "$OUT/project"
cp -a "$ROOT/tests/portable_runtime/". "$OUT/project/"
cp -a "$ROOT/addons" "$ROOT/assets" "$OUT/project/"
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
cat > "$OUT/relocated/ImportOnly.tscn" <<'SCENE'
[gd_scene format=3]
[node name="ImportOnly" type="Node3D"]
SCENE
timeout --kill-after=5 120 "$GODOT_BIN" --headless --editor --path "$OUT/relocated" res://ImportOnly.tscn --import --frame-delay 1000 > "$OUT/relocated-import.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/relocated" --script res://runtime_test.gd > "$OUT/relocated-runtime.log" 2>&1
timeout --kill-after=5 90 "$GODOT_BIN" --headless --path "$OUT/relocated" --script res://recovery_integrity_test.gd > "$OUT/recovery-integrity.log" 2>&1
python3 "$ROOT/tests/portable_runtime/world_rejections.py" --godot "$GODOT_BIN" --project "$OUT/relocated" --out "$OUT/negative" > "$OUT/negative-suite.log" 2>&1
timeout --kill-after=5 180 dotnet build "$OUT/relocated/PortableRuntime.csproj" -c Debug > "$OUT/dotnet-build.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/relocated" res://RuntimeBinding.tscn > "$OUT/csharp.log" 2>&1
python3 - "$OUT" <<'PYRESULT'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);results={}
for name,marker in [('runtime','RUNTIME_RESULT '),('relocated-runtime','RUNTIME_RESULT '),('recovery-integrity','RECOVERY_INTEGRITY_RESULT ')]:
 text=(p/(name+'.log')).read_text();rows=[json.loads(x[len(marker):]) for x in text.splitlines() if x.startswith(marker)]
 assert len(rows)==1 and rows[0]['failed']==0,(name,rows)
 results[name]=rows[0]
assert 'PORTABLE CSHARP PASS' in (p/'csharp.log').read_text()
for file in p.glob('*.log'):
 text=file.read_text();assert 'ERROR:' not in text and 'leaked' not in text,file
(p/'results.json').write_text(json.dumps(results,indent=2)+'\n')
print('PORTABLE AUTHOR RUNTIME PASS',p)
PYRESULT
