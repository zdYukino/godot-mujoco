#!/usr/bin/env bash
set -euo pipefail
cd /tmp/mj316-two-connect-hinge
MJ_ROOT=/workspace/shared/builds/godot-mujoco-3.16/_deps/mujoco-src
run_stage() {
 local stage="$1" code;shift
 set +e
 "$@" > "$stage.log" 2>&1
 code=$?
 set -e
 printf '%s\t%s\n' "$stage" "$code" >> executions.tsv
 return "$code"
}
: > executions.tsv
run_stage build c++ -std=c++17 -O2 -I"$MJ_ROOT/include" probe.cpp -L"$MJ_ROOT/lib" -Wl,-rpath,"$MJ_ROOT/lib" -lmujoco -o probe
run_stage run ./probe
