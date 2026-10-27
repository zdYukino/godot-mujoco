#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
    echo '缺少 Python，请先运行 ./boostup.sh。 / Missing Python; run ./boostup.sh first.' >&2
    exit 2
fi
export PYTHONDONTWRITEBYTECODE=1
exec python3 "$ROOT/scripts/em_run.py" "$@"
