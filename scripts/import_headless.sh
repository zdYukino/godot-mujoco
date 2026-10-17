#!/usr/bin/env bash
# Linux headless import workaround for Godot's first-extension doc generation race.
# Never retries against a populated cache or converts a failing exit to success.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
if [[ "$#" -gt 1 ]]; then
    echo "Usage: GODOT_BIN=/path/to/godot $0 [project-directory]" >&2
    exit 2
fi
version="$("$GODOT_BIN" --version)"
if [[ "$version" != 4.7.2.stable.mono.* ]]; then
    echo "Expected Godot 4.7.2 .NET (4.7.2.stable.mono.*), got: $version" >&2
    exit 2
fi
if [[ "$(uname -s)" != Linux ]]; then
    echo "This helper is validated only on Linux." >&2
    exit 2
fi
# Frame delay mitigates the race; it is not an engine fix or a guarantee.
# exec preserves Godot's actual status (including crashes) for callers/CI.
exec "$GODOT_BIN" --headless --editor --path "${1:-$ROOT/demo}" --import --frame-delay 1000
