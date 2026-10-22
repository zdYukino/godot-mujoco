#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-typed.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || exit 2
mkdir -p "$OUT/project"
cp "$ROOT/tests/typed_terrain/"{derived_terrain.gd,gui.gd,prepare.gd,project.godot,TypedTerrain.cs,TypedControl.csproj,TypedControl.tscn} "$OUT/project/"
cp -a "$ROOT/demo/addons" "$OUT/project/"
run_stage() {
    local stage="$1" limit="$2" code
    shift 2
    set +e
    timeout --kill-after=5 "$limit" "$@" > "$OUT/$stage.log" 2>&1
    code=$?
    set -e
    printf '%s\t%s\n' "$stage" "$code" >> "$OUT/executions.tsv"
    if [[ "$code" != 0 ]]; then
        echo "$stage failed: exit $code; see $OUT/$stage.log" >&2
        return "$code"
    fi
}
run_stage import 120 bash "$ROOT/scripts/import_headless.sh" "$OUT/project"
run_stage prepare 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://prepare.gd
run_stage build 180 dotnet build "$OUT/project/TypedControl.csproj" -c Debug
run_stage runtime 120 "$GODOT_BIN" --headless --path "$OUT/project" res://TypedControl.tscn
python3 - "$OUT" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1])
for f in p.glob('*.log'):
 s=f.read_text();assert 'ERROR:' not in s and 'leak' not in s.lower(),f
s=(p/'runtime.log').read_text();rows=[x.removeprefix('TYPED_TERRAIN_RESULT ') for x in s.splitlines() if x.startswith('TYPED_TERRAIN_RESULT ')];assert len(rows)==1
r=json.loads(rows[0]);assert r['failed']==0
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('TYPED TERRAIN PASS',r)
PY
