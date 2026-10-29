#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${OUT:=$(mktemp -d /tmp/gmj-editor.XXXXXX)}"
exec python3 "$ROOT/tests/node_authoring/run.py" --out "$OUT" --godot "${GODOT_BIN:-godot}"
