#!/usr/bin/env bash
set -euo pipefail
: "${GODOT_CPP_ROOT:?Set the existing pinned godot-cpp source directory}"
: "${GODOT_CPP_BUILD:?Set the generated godot-cpp build directory}"
: "${GODOT_CPP_LIBRARY:?Set the matching static library path}"
: "${OUT:?Set the isolated output directory}"
mkdir -p "$OUT"
for mode in class no_class; do
 flags=()
 if [[ $mode == no_class ]]; then flags+=(-DNO_PROBE_CLASS); fi
 g++ -shared -fPIC -std=c++17 -g -O0 -DDEBUG_ENABLED -DDEBUG_METHODS_ENABLED "${flags[@]}" \
  -I"$GODOT_CPP_ROOT/include" -I"$GODOT_CPP_ROOT/gdextension" -I"$GODOT_CPP_BUILD/gen/include" \
  "$(dirname "$0")/minimal_extension.cpp" "$GODOT_CPP_LIBRARY" -o "$OUT/libcold_probe_$mode.so"
done
