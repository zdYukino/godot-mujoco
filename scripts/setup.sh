#!/usr/bin/env bash
# Portable Linux entry point; no shell profile or machine-specific paths needed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
    echo 'Python 3.10+ is required. Install python3, then rerun this command.' >&2
    exit 2
fi
export PYTHONDONTWRITEBYTECODE=1
exec python3 "$ROOT/scripts/setup.py" "$@"
