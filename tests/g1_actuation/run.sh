#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
[[ $(uname -s) == Linux ]] || { echo 'Linux-only validation' >&2; exit 1; }
: "${MUJOCO_ROOT:=$ROOT/build/_deps/mujoco-src}"
: "${GODOT:=godot}"
: "${OUT:=$(mktemp -d /tmp/g1-actuation.XXXXXX)}"
mkdir -p "$OUT"; OUT=$(realpath "$OUT"); MUJOCO_ROOT=$(realpath "$MUJOCO_ROOT")
[[ ! -e "$OUT/generated" && ! -e "$OUT/godot" ]] || { echo 'OUT must have no generated or godot directory; use a fresh directory' >&2; exit 1; }
ASSETS="$ROOT/assets/robots/unitree_g1/g1_29dof_mode_18"
g++ -O2 -std=c++17 -I"$MUJOCO_ROOT/include" "$ROOT/tests/g1_actuation/native_test.cpp" -L"$MUJOCO_ROOT/lib" -Wl,-rpath,"$MUJOCO_ROOT/lib" -lmujoco -o "$OUT/native_test"
python3 "$ROOT/tests/g1_actuation/prepare_fixture.py" --assets "$ASSETS" --out "$OUT/generated" --native "$OUT/native_test" | tee "$OUT/generation.log"
for f in actuation-test.xml joint-inventory.json joint-inventory.tsv g1_29dof_mode_18.mujoco316.urdf; do cmp "$ASSETS/$f" "$OUT/generated/$f"; done
(cd /tmp && "$OUT/native_test" "$OUT/generated/actuation-test.xml" "$OUT/generated/joint-inventory.tsv") | tee "$OUT/native.log"
python3 - "$ROOT" "$OUT" <<'PY'
import pathlib,shutil,sys
r,o=map(pathlib.Path,sys.argv[1:]);p=o/'godot'
shutil.copytree(r/'examples/pendulum',p,ignore=shutil.ignore_patterns('.godot','addons','assets','bin','obj'))
# Copy canonical sources directly, including native libraries. Do not depend on
# setup-generated example links, so this fixture also works from a fresh checkout.
shutil.copytree(r/'addons',p/'addons')
shutil.copytree(r/'assets',p/'assets')
shutil.copytree(r/'tests/g1_actuation',p/'tests/g1_actuation')
shutil.copy2(r/'tests/g1_actuation/G1ActuationTests.csproj',p/'G1ActuationTests.csproj')
with (p/'project.godot').open('a') as f:f.write('\n[dotnet]\nproject/assembly_name="G1ActuationTests"\n')
PY
GODOT_BIN="$GODOT" timeout 120 "$ROOT/scripts/import_headless.sh" "$OUT/godot" >"$OUT/import.log" 2>&1
timeout 120 "$GODOT" --headless --path "$OUT/godot" --script res://tests/g1_actuation/binding_test.gd >"$OUT/gdscript.log" 2>&1
cat "$OUT/gdscript.log"; grep -q 'G1 GDSCRIPT PASS' "$OUT/gdscript.log"
timeout 180 dotnet build "$OUT/godot/G1ActuationTests.csproj" -c Debug >"$OUT/dotnet-build.log" 2>&1
timeout 120 "$GODOT" --headless --path "$OUT/godot" res://tests/g1_actuation/BindingTest.tscn >"$OUT/csharp.log" 2>&1
cat "$OUT/csharp.log"; grep -q 'G1 CSHARP PASS' "$OUT/csharp.log"
printf 'PASS: native, GDScript and C# G1 checks. Logs: %s\n' "$OUT"
