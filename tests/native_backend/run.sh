#!/usr/bin/env bash
# Independent staged project, leaving the default pendulum and G1 untouched.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEST="$ROOT/tests/native_backend"
GODOT_BIN=${GODOT_BIN:-godot}
OUT=${OUT:-$(mktemp -d /tmp/mujoco-native-backend.XXXXXX)}
[[ ! -e "$OUT/project" ]] || { echo "Use a fresh OUT directory" >&2; exit 2; }
mkdir -p "$OUT/project"
cp "$TEST/project.godot" "$TEST/Main.tscn" "$TEST/acceptance.gd" "$TEST/primitives.gd" "$TEST/rotation_sync.gd" "$TEST/VisualDemo.tscn" "$TEST/visual_demo.gd" "$OUT/project/"
cp -a "$ROOT/addons" "$OUT/project/"
printf 'Native backend results: %s\n' "$OUT"
GODOT_BIN="$GODOT_BIN" timeout 120 "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
# Three fresh engine processes exercise shutdown and startup independently.
REPEAT=${REPEAT:-3}
[[ "$REPEAT" =~ ^[1-9][0-9]*$ ]] || { echo "REPEAT must be positive" >&2; exit 2; }
for ((run=1; run<=REPEAT; run++)); do
  timeout 90 "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 -- --report="$OUT/results-$run.json" 2>&1 | tee "$OUT/runtime-$run.log"
  timeout 90 "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://primitives.gd -- --report="$OUT/primitives-$run.json" 2>&1 | tee "$OUT/primitives-$run.log"
  timeout 120 "$GODOT_BIN" --headless --path "$OUT/project" --fixed-fps 60 --script res://rotation_sync.gd > "$OUT/rotation-$run.log" 2>&1
done
python3 - "$OUT" "$REPEAT" <<'PYCODE'
import hashlib, json, pathlib, sys
out, count = pathlib.Path(sys.argv[1]), int(sys.argv[2])
runs = []
primitives = []
rotations = []
for index in range(1, count + 1):
    report = json.loads((out / f'results-{index}.json').read_text())
    assert report['failed'] == 0, report
    assert report['passed'] >= 44, report
    assert report['backend'] == 'MjPhysicsServer3D', report
    assert 'ERROR:' not in (out / f'runtime-{index}.log').read_text()
    runs.append(report)
    extra = json.loads((out / f'primitives-{index}.json').read_text())
    assert extra['failed'] == 0 and extra['passed'] == 25, extra
    assert extra['backend'] == 'MjPhysicsServer3D', extra
    assert 'ERROR:' not in (out / f'primitives-{index}.log').read_text()
    primitives.append(extra)
    text = (out / f'rotation-{index}.log').read_text()
    rotation = json.loads(next(line.split(' ',1)[1] for line in text.splitlines() if line.startswith('ROTATION_SYNC_RESULT ')))
    assert rotation['failed'] == 0 and rotation['checks'] == 80, rotation
    assert 'ERROR:' not in text and 'leaked' not in text
    rotations.append(rotation)
for log in out.glob('*.log'):
    text = log.read_text()
    assert 'ERROR:' not in text and 'leaked' not in text, log
library = out / 'project/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so'
summary = {'runs': runs, 'primitives': primitives, 'rotations': rotations, 'passed': sum(r['passed'] for r in runs + primitives) + sum(r['checks'] for r in rotations), 'failed': 0,
           'backend': runs[0]['backend'], 'extension_sha256': hashlib.sha256(library.read_bytes()).hexdigest()}
(out / 'results.json').write_text(json.dumps(summary, indent=2) + '\n')
print(f"ACCEPTANCE PASS: {summary['passed']} checks across {3 * count} fresh processes; backend={summary['backend']}")
PYCODE
