#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-runtime-preset.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp "$ROOT/tests/runtime_presets/"{prepare.gd,acceptance.gd,project.godot,gui.gd} "$OUT/project/"
cp -a "$ROOT/addons" "$OUT/project/"
run_stage() {
 local stage="$1" code; shift
 set +e
 timeout --kill-after=5 120 "$@" > "$OUT/$stage.log" 2>&1
 code=$?
 set -e
 printf '%s\t%s\n' "$stage" "$code" >> "$OUT/executions.tsv"
 if [[ "$code" != 0 ]]; then echo "$stage failed: exit $code; $OUT/$stage.log" >&2; return "$code"; fi
}
run_stage import bash "$ROOT/scripts/import_headless.sh" "$OUT/project"
run_stage prepare "$GODOT_BIN" --headless --path "$OUT/project" --script res://prepare.gd
run_stage runtime "$GODOT_BIN" --headless --path "$OUT/project" --script res://acceptance.gd
python3 - "$OUT" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1])
for f in p.glob('*.log'):
 s=f.read_text();assert 'ERROR:' not in s and 'leak' not in s.lower(),f
rows=[x.removeprefix('RUNTIME_PRESET_RESULT ') for x in (p/'runtime.log').read_text().splitlines() if x.startswith('RUNTIME_PRESET_RESULT ')];assert len(rows)==1
r=json.loads(rows[0]);assert r['failed']==0
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('RUNTIME_PRESET PASS',r)
PY
