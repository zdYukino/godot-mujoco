#!/usr/bin/env bash
# Clone, configure, check and build. All paths are relative to this script.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        echo './boostup.sh [--check | --rebuild | --configure] [--godot-dir DIR] [--dotnet-dir DIR] [--yes] [--jobs N] [--build-dir DIR] [--mujoco-root DIR]'
        exit 0
    fi
    for arg in "$@"; do
        if [[ "$arg" == --check ]]; then
            echo '缺少 Python 3.10+，仅检查模式不会安装。 / Python 3.10+ missing; check-only mode will not install it.' >&2
            exit 2
        fi
    done
    # Python is needed to run the main wizard; bootstrap it only on tested Ubuntu.
    . /etc/os-release
    if [[ "$ID" != ubuntu || ( "$VERSION_ID" != 22.04 && "$VERSION_ID" != 24.04 ) ]]; then
        echo '需要 Python 3.10+，请安装后重试。 / Install Python 3.10+ and retry.' >&2
        exit 2
    fi
    echo '需要安装 python3 和 ca-certificates。 / Need to install python3 and ca-certificates.'
    accepted=no
    for arg in "$@"; do [[ "$arg" != --yes ]] || accepted=yes; done
    if [[ "$accepted" != yes ]]; then
        read -r -p '允许 sudo apt-get 安装？ / Allow sudo apt-get installation? [y/N] ' accepted
    fi
    [[ "$accepted" == y || "$accepted" == Y || "$accepted" == yes ]] || exit 2
    sudo apt-get update
    sudo apt-get install -y python3 ca-certificates
fi
export PYTHONDONTWRITEBYTECODE=1
exec python3 "$ROOT/scripts/bootstrap.py" "$@"
