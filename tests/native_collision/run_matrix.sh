#!/usr/bin/env bash
set -euo pipefail
: "${MUJOCO_ROOT:?MuJoCo 3.16.0 distribution required}"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${OUT:=$(mktemp -d /tmp/gmj-collision-matrix.XXXXXX)}"
mkdir -p "$OUT"
g++ -O2 "$ROOT/tests/native_collision/matrix.cpp" -I"$MUJOCO_ROOT/include" -L"$MUJOCO_ROOT/lib" -Wl,-rpath,"$MUJOCO_ROOT/lib" -lmujoco -o "$OUT/matrix"
"$OUT/matrix" > "$OUT/matrix.csv"
echo "MATRIX PASS $OUT"
