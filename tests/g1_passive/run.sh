#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${OUT:=$(mktemp -d /tmp/gmj-g1-parent.XXXXXX)/results}"
exec python3 "$ROOT/tests/example_projects/run.py" --out "$OUT" --godot "${GODOT_BIN:-godot}"
