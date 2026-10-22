#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${OUT:=$(mktemp -d /tmp/gmj-mjworld-smoke.XXXXXX)}"
export PYTHONDONTWRITEBYTECODE=1
exec python3 "$ROOT/tests/mjworld_smoke/run.py" "$OUT"
