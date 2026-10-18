# Linux MJCF EditorPlugin validation

Base: `ccaa10a1ff7e27428e00797dfcc612d2a2a632ae` (independently accepted
previous milestone). New development branch: `codex/mjcf-editor`. Main and
other users' branches were not changed. GitHub synchronization uses MCP, no SSH.

Environment inherited successfully: Godot `4.7.2.stable.mono.official.ed1daf0bf`,
MuJoCo `3.16.0`, SDK `8.0.426`, .NET runtime `8.0.32`, Linux x86_64.
No AGENTS.md or `.agents/skills` instructions were present in the workspace.

## Final commands and evidence

All commands ran from the repository after sourcing
`/workspace/shared/tools/env.sh`. Evidence root:
`/workspace/shared/validation/mjcf-delivery`.

| Command / process | Result | Exit |
| --- | --- | --- |
| `cmake --build /workspace/shared/validation/dynamic-final/build -j 4` | Native extension built and staged | 0 |
| `OUT=$E/editor tests/editor_plugin/run.sh` | Cold import + actual editor, 80 checks | 0 |
| `OUT=$E/dynamic tests/dynamic_scene/run.sh` | 86 dynamic checks + UI smoke | 0 |
| `OUT=$E/backend tests/native_backend/run.sh` | 207 checks, six processes | 0 |
| `MUJOCO_ROOT=/workspace/shared/builds/godot-mujoco-3.16/_deps/mujoco-src OUT=$E/g1 tests/g1_actuation/run.sh` | C++ / GDScript / C# all pass | 0 |
| `godot --headless --path <isolated-demo> res://HeadlessTest.tscn` | SMOKE TEST PASS | 0 |
| Same, `ChaosPendulumTest.tscn` | CHAOS TEST PASS | 0 |
| Same, `VisualDebugTest.tscn` | VISUAL DEBUG DATA TEST PASS | 0 |

`E` above means the evidence root. Build log:
`/workspace/shared/validation/editor-build-final.log`. The isolated demo used for
MjWorld was `/workspace/shared/validation/editor-regression/mjworld`, restaged
with the final binary. Its fresh import is recorded in
`/workspace/shared/validation/editor-regression/mjworld-import.log`.

Final extension SHA-256:
`ba7b43d67115f49d5a794fc8bead0307bc7e76362bb5cb5f58a00521bb53013b`.
The editor, dynamic and backend JSON reports record the same binary hash.
G1 generation verified all 36 original Unitree SHA-256 and Git blob hashes.
Native G1 exercised 59 cases / 236,000 steps and 58 force saturation checks;
this remains fixed-base bounded actuation, not walking validation.

Headless editor tests have no script/engine errors or ObjectDB leak diagnostics.
The original MjWorld smoke deliberately sends a wrongly sized qpos array and
prints its expected rejection; its PASS marker and process exit are checked
separately. That negative-test diagnostic is not hidden.

## Actual editor rendering

The final project is also run with a workspace-local Xvfb display and Mesa
llvmpipe, 1600×1000, OpenGL Compatibility and Dummy audio:

```sh
DISPLAY=:98 LIBGL_ALWAYS_SOFTWARE=1 godot --editor \
  --path "$E/editor/project" --rendering-method gl_compatibility \
  --audio-driver Dummy --resolution 1600x1000 -- \
  --mj-editor-test --report="$E/editor/render-results.json" \
  --capture-dir="$E/editor/screenshots"
```

The rendered process exited **0**; all **83** checks passed, including three
screenshot assertions. There were no scene/script errors or ObjectDB leak diagnostics. The files show the actual
Godot editor, model hierarchy, physical geometry and editable property controls.
They are not illustrations or reconstructed interfaces. Host diagnostics include
unsupported VSync and unavailable Vulkan surface extensions, despite successful
OpenGL rendering; keep the complete `editor/render.log` with the result report.
Cloud screenshots do not substitute for dot's independent desktop acceptance.

## Scope and remaining gate

The new preview has its own native model ownership and shares state migration
and coordinate helpers with the runtime backend. No G1-specific importer or
existing runtime API was removed. Failed imports/edits preserve the active model;
undo targets a reference-counted session, and plugin shutdown releases its native
preview. Changes are saved as editor documents with external asset paths. Those
paths must remain available; this is not a portable asset bundler.

See [the parameter and unsupported-content contract](mjcf-editor.md), including
read-only inertias/limits, non-PD gain exclusions, frame/fromto pose limitations,
and unsupported flex/heightfield/skin/plugin/SDF previews. Follow
[the manual acceptance steps](../tests/editor_plugin/README.md) on dot, save its
independent screenshots and only then decide whether to promote this branch.
