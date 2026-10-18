#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-portable.XXXXXX)}"
[[ ! -e "$OUT/project" ]] || { echo 'Use a fresh OUT directory' >&2; exit 2; }
mkdir -p "$OUT/project"
cp -a "$ROOT/tests/portable_runtime/". "$OUT/project/"
cp -a "$ROOT/demo/addons" "$OUT/project/"
cp -a "$ROOT/tests/editor_plugin/fixtures/external" "$OUT/source"
cp -a "$ROOT/tests/editor_plugin/fixtures/external" "$OUT/source_other"
sed -i 's/v 1 0 0/v 2 0 0/' "$OUT/source_other/meshes/tetra.obj"
timeout --kill-after=5 120 "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
timeout --kill-after=5 60 "$GODOT_BIN" --headless --path "$OUT/project" --script res://package_test.gd -- --source="$OUT/source/model.xml" > "$OUT/package.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib,shutil,sys
p=pathlib.Path(sys.argv[1]);shutil.copytree(p/'project',p/'relocated',ignore=shutil.ignore_patterns('.godot','.staging_*'))
(p/'source').rename(p/'source.offline');(p/'source_other').rename(p/'source_other.offline');(p/'project').rename(p/'project.offline')
PY
timeout --kill-after=5 120 "$ROOT/scripts/import_headless.sh" "$OUT/relocated" > "$OUT/relocated-import.log" 2>&1
timeout --kill-after=5 60 "$GODOT_BIN" --headless --path "$OUT/relocated" --script res://relocate_test.gd > "$OUT/relocate.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib,json,sys
p=pathlib.Path(sys.argv[1]);s=(p/'package.log').read_text();r=json.loads(next(x.split(' ',1)[1] for x in s.splitlines() if x.startswith('PACKAGE_RESULT ')));assert r['failed']==0
assert 'RELOCATED_MODEL_PASS' in (p/'relocate.log').read_text()
for f in p.glob('*.log'):assert 'ERROR:' not in f.read_text(),f
print('PORTABLE ASSETS PASS; original project and source paths unavailable;',p)
PY
