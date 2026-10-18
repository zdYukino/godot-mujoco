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
timeout --kill-after=5 180 dotnet build "$OUT/relocated/PortableRuntime.csproj" -c Debug > "$OUT/dotnet-build.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/relocated" res://RuntimeBinding.tscn > "$OUT/csharp.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);results={}
for name in ['runtime','relocated-runtime']:
 s=(p/(name+'.log')).read_text();r=json.loads(next(x.split(' ',1)[1] for x in s.splitlines() if x.startswith('RUNTIME_RESULT ')));assert r['failed']==0,r;results[name]=r
assert 'PORTABLE CSHARP PASS' in (p/'csharp.log').read_text()
for f in p.glob('*.log'):
 s=f.read_text();assert 'ERROR:' not in s and 'ObjectDB instances leaked' not in s,f
(p/'results.json').write_text(json.dumps(results,indent=2)+'\n')
print('PORTABLE RUNTIME PASS; original project and source assets unavailable;',p)
PY
