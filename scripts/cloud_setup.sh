#!/usr/bin/env bash
# Compatibility entry point. Tools must already be installed; see setup.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo '[cloud_setup] Deprecated: use bash scripts/setup.sh build, then bash scripts/setup.sh smoke.' >&2
bash "$ROOT/scripts/setup.sh" build "$@"
exec bash "$ROOT/scripts/setup.sh" smoke
