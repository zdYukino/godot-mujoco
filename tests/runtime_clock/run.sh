#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-clock.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp "$ROOT/tests/runtime_clock/"*.gd "$ROOT/tests/runtime_clock/project.godot" "$OUT/project/"
cp -a "$ROOT/addons" "$OUT/project/"
timeout --kill-after=5 120 "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://acceptance.gd > "$OUT/runtime.log" 2>&1
cp "$ROOT/tests/runtime_clock/ClockBinding.cs" "$ROOT/tests/runtime_clock/ClockBinding.csproj" "$ROOT/tests/runtime_clock/ClockBinding.tscn" "$OUT/project/"
printf '\n[dotnet]\nproject/assembly_name="ClockBinding"\n' >> "$OUT/project/project.godot"
timeout --kill-after=5 180 dotnet build "$OUT/project/ClockBinding.csproj" -c Debug > "$OUT/dotnet-build.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" res://ClockBinding.tscn > "$OUT/csharp.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);s=(p/'runtime.log').read_text()
r=json.loads(next(x.removeprefix('CLOCK_RESULT ') for x in s.splitlines() if x.startswith('CLOCK_RESULT ')))
assert r['failed']==0,r
assert 'CLOCK CSHARP PASS' in (p/'csharp.log').read_text()
for f in p.glob('*.log'):
 s=f.read_text();assert 'ERROR:' not in s and 'leaked' not in s,f
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n')
print('CLOCK PASS',r['passed'],p)
PY
