# Linux portable model/runtime validation — 2026-10-18

Development branch: `codex/portable-model-runtime`. Accepted starting main:
`bb1294e4f1d074d2a7c6a3852b428d83020ae5b3`. Asset checkpoint:
`311d8ff594e654c25d6d65b27e769b8f43d41a63`; shared-runtime checkpoint:
`c563eff6644c19a76af06f56542b273ac395f78d`. Main was not changed.

Environment inherited successfully: Linux, Godot
`4.7.2.stable.mono.official.ed1daf0bf`, MuJoCo compile/runtime **3.16.0**,
.NET SDK **8.0.426**. No Windows work. No outstanding permissions blocker.

Build command (exit 0):

```sh
source /workspace/shared/tools/env.sh
cmake --build /workspace/shared/validation/dynamic-final/build -j 4
```

Build log: `/workspace/shared/validation/runtime-build5.log`.
Final native binary SHA-256:
`c6aedb8bf549e6a82819d0ee2bfdbbbf41db08008feb0f4c787147eae9b33dcf`.
Subsequent changes are Godot scripts, tests and documentation only.

All commands below ran from the repository with the inherited environment sourced.
`V` below denotes `/workspace/shared/validation`. Every listed command exited 0.

| Command | Verified result | Logs |
| --- | --- | --- |
| `OUT=$V/portable-assets-release tests/portable_runtime/run_assets.sh` | Pack, deduplication, include provenance, same-name conflicts, missing-asset rollback; six distinct cube texture faces; actual relocated model compilation/advance | `portable-assets-release/{import,package,relocated-import,relocate}.log` |
| `OUT=$V/portable-runtime-release tests/portable_runtime/run_runtime.sh` | 30 runtime assertions before and after relocation; .NET build without warnings/errors; C# actual movement; 9 editor flow assertions; separate-process editor-authored scene runs with kp=126 and angle 0.74999999874989 for target 0.75 | `portable-runtime-release/results.json`, `runtime.log`, `relocated-runtime.log`, `dotnet-build.log`, `csharp.log`, `editor-flow.log`, `editor-scene-restart.log` |
| `OUT=$V/portable-regress-native tests/native_backend/run.sh` | 207 assertions in six fresh processes | `portable-regress-native/`, `portable-regress-native.log` |
| `OUT=$V/portable-regress-dynamic tests/dynamic_scene/run.sh` | 86 assertions plus UI smoke | `portable-regress-dynamic/{results.json,runtime.log,ui-smoke.log}` |
| `OUT=$V/portable-editor-release tests/editor_plugin/run.sh` | 116 editor assertions including real Apply/Discard signals | `portable-editor-release/{results.json,runtime.log}` |
| `MUJOCO_ROOT=/workspace/shared/builds/godot-mujoco-3.16/_deps/mujoco-src OUT=$V/portable-regress-g1 tests/g1_actuation/run.sh` | Native, GDScript and C# G1 actuation; 36 upstream assets verified byte-for-byte | `portable-regress-g1/{generation,native,gdscript,dotnet-build,csharp}.log` |
| `godot --headless --path $V/portable-regress-g1/godot res://HeadlessTest.tscn` | PASS; expected invalid-qpos negative-test error | `portable-regress-g1/HeadlessTest.log` |
| Same command with `ChaosPendulumTest.tscn` | PASS | `portable-regress-g1/ChaosPendulumTest.log` |
| Same command with `VisualDebugTest.tscn` | PASS | `portable-regress-g1/VisualDebugTest.log` |

The migration runner physically renames the original project, removes the relocated
original `assets/` robot directory and source fixture XMLs, removes `.godot`, then
cold-imports. Packaged dependencies alone remain. Original path strings retained in
provenance are not runtime dependencies. Source archives survive a relocated edit.
The original 36 upstream files were reverified afterward using both SHA-256 and Git
blob SHA-1; manifest: `$V/portable-original-assets.json`.

Real rendering uses Xvfb + Mesa llvmpipe OpenGL compatibility, 1600×1000. The old
editor suite also passed 119 checks (116 plus three actual screenshots). The new
rendered editor flow passed 11 checks and exited 0; its log is
`$V/portable-visual/editor-render-fixed.log`. New image
files under `$V/portable-visual/` are `04-portable-g1-editor.png`,
`05-portable-godot-scene.png`, and `06-shared-runtime.png`. The runtime image is a
running saved scene, not an illustration: two G1 models, a normal Godot rigid box
and floor; target 0.80 rad, measured 0.800 rad. This host can emit Vulkan surface
probe errors and unsupported VSync warnings before using OpenGL; these are distinct
from script/native acceptance failures.

Development failures were retained in earlier logs, not counted as successful
acceptance: foreign C++ string-vector ABI access (replaced with MuJoCo C accessors
and XML parsing), full-inertia/diagonal-inertia edit conflict, initial test robot
intersecting the floor, and a deferred RID queue that omitted model instances.
The new acceptance exercises each repaired boundary, including six cube texture
files and instance destruction from a physics callback. Editor scans now wait for
a normal frame and serialize with scans already in progress. Earlier screenshot
repeats timed out waiting for a draw signal in a static editor; the capture helper
now explicitly forces a render and the corrected run completed with exit 0.
Those timeouts are not counted as acceptance passes.

See [portable models](portable-models.md) for the API, scene workflow and limitations.
Fixed-base G1 contact/control is **not walking acceptance**. No CharacterBody3D,
Area3D, full Godot joint compatibility, textured visual parity or PCK asset loading
is claimed. Dot still must independently pull/build, move the project, use actual
GUI controls, save/restart/run and inspect contacts before any main promotion.
