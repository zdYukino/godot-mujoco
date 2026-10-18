# Application development delivery — 2026-10-18

Repository `zdYukino/godot-mujoco`, branch `codex/application-editing`.
Starting developer commit `c8d0286ce2c882c863c2b2a82f74b47629a10d29` was verified
against GitHub MCP before work. Initial local checkout was main's
`bb1294e4f1d074d2a7c6a3852b428d83020ae5b3`; the exact developer commit was fetched
via HTTPS and a new branch created through GitHub MCP. No SSH or main update.
No AGENTS.md or `.agents/skills` files were present in this workspace/repository.
All remote development commits/ref updates use GitHub MCP.

## Stage checkpoints

| Stage | Commit | Tree | Outcome |
| --- | --- | --- | --- |
| F5 controlled comparison | `49bba26c6bac7e7102fd68d3060fe7172a96d172` | `269003d3e457888b5219b6d8ce23bb6fd7b971ee` | Actual plain/G1 embedding screenshots; project-level silent audio. Persistent dot grey view remains unproven; strict GUI failure retained. |
| Joint/inertia/viewport editing | `38cf010072edde96591f7d5912973436c663a724` | `479003dbd978a63bed89cb6ebcb4d68e43e06ca3` | 142 editor assertions, 447 native assertions; GUI exercised but strict host ERROR gate fails. |
| Runtime-safe editing | Commit containing this report | Its Git tree | Native boundary transaction, debugger transport, scene assignment, tests and evidence below. |

Fixed tools: Godot `4.7.2.stable.mono.official.ed1daf0bf`, MuJoCo `3.16.0`, Linux
x86_64, .NET SDK `8.0.426`. Official Godot binary was not modified. This work did
not resume cold-import patch research or engine memory work. Cold import 139
remains a separate known limitation; no cached retry is described as fresh.

Final native extension SHA256:
`f4ca31da09832cabeda353f65090007a0c3230753996df670f8b68bdde43c57e`.
Native source was compiled by the existing CMake build directory; this is not a
claim of a new clean dependency build. Tests stage fresh project directories.

## Exact commands and evidence

Commands ran in the repository with `source /workspace/shared/tools/env.sh`.
`V=/workspace/shared/validation`. New OUT directories were used for every runner.

| Command | Exit and interpretation |
| --- | --- |
| `cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 4` | 0; final native transaction implementation built |
| `OUT=$V/application-final-native tests/native_backend/run.sh` | 0; 447 assertions, including rotation and reentry; no ERROR/leak |
| `OUT=$V/application-final-dynamic tests/dynamic_scene/run.sh` | 0; 86 assertions and UI smoke; no ERROR/leak |
| `OUT=$V/application-final-editor tests/editor_plugin/run.sh` | 0; 142 assertions; no ERROR/leak |
| `OUT=$V/application-final-assets tests/portable_runtime/run_assets.sh` | 0; packaging, relocation, original paths unavailable; no ERROR/leak |
| `OUT=$V/application-frozen-runtime tests/portable_runtime/run_runtime.sh` | Original runner exited 0 after all runtime, relocation, live edit, C#, editor and restart stages. **Final strict re-audit exits 1** for two expected-but-still-ERROR negative ownership/configuration diagnostics. No clean aggregate pass claimed. |
| `OUT=$V/application-delivery-live tests/portable_runtime/run_live.sh` | See retained live-results.json and final verification below; native transaction plus actual debugger-child workflow |
| `MUJOCO_ROOT=/workspace/shared/builds/godot-mujoco-3.16/_deps/mujoco-src OUT=$V/application-final-g1 tests/g1_actuation/run.sh` | Native and GDScript passed; initial runner exited 1 at environment-constrained .NET build |
| `dotnet build $V/application-final-g1/godot/G1ActuationTests.csproj -c Debug` | Follow-up exit 0 with exact .NET shared-memory directory permission; 0 warnings/errors |
| `godot --headless --path $V/application-final-g1/godot res://tests/g1_actuation/BindingTest.tscn` | Follow-up exit 0; C# 29 joints, 60 trials, 240000 steps; no ERROR/leak |

The initial NuGet-Migrations failure was traced to EROFS creating a session in
`/home/agent/.dotnet/corefx/Runtime/SharedMemory/.dotnet/shm`. Granting write access
only to `/home/agent/.dotnet/corefx/Runtime/SharedMemory` via the permission tool
allowed .NET builds. No engine patch, auth workaround or broader permission
bypass was used. Earlier failures remain in stage-one evidence. Full portable
C# compilation/runtime also succeeded with that exact directory permission.

All **36 original Unitree files** match both original SHA256 and Git blob SHA-1;
[the retained integrity report](evidence/runtime-safe/original-assets.json) lists
every file. G1 remains fixed-base; standing/walking was not developed.

## Strict failures and GUI evidence

[Actual runtime editor screenshot](evidence/runtime-safe/editor-live.png) shows
the selected debugger instance and applied revision. The real-renderer automated
editor used `--editor --rendering-method gl_compatibility --audio-driver Dummy
--resolution 1600x1000 -- --mj-editor-test --live-capture=...` with the unchanged
binary under Xorg dummy/Mesa llvmpipe. Apply/ack/control/scene assignment/undo/redo
and the actual editor Save action passed; process exit was 0. Its two Vulkan
surface-probe ERRORs remain in [the full log](evidence/runtime-safe/editor-gui.log),
so this is **not** a clean GUI acceptance pass.

The first expanded persistence probe also emitted official headless-thumbnail
ERRORs while saving a scene. This failed run is retained at
`$V/application-final-persist-live/`. The headless harness now tests PackedScene
serialization directly; the graphical harness still exercises actual editor Save.
These are clearly distinct checks, not a cached/import retry or engine change.

The historical full portable runner replaced two exact recovery ERROR messages
before evaluating its log gate. That exemption is removed. The positive stages
and expected rejection assertions are recorded, but **all** ERROR/leak logs now
produce a nonzero aggregate result. [Strict audit](evidence/runtime-safe/portable-strict-audit.log)
and [substage results](evidence/runtime-safe/portable-results.json) retain this
failure even though the older runner's process exit was 0.

During development, tests caught automatic-inertia reset metadata, resource-path
cache takeover, a GDScript inference error and debugger-session closure leaks.
They were fixed and retested. Earlier failed local runs remain at
`application-editor-stage2-advanced`, `application-stage3-live.log`,
`application-stage3-editor`, `application-stage3-editor2`, and
`application-final-live` (child lacked a DISPLAY). None count as acceptance passes.

No main promotion or stable-baseline claim is made. Dot must independently pull,
build, perform the GUI checklists in [editor properties](editor-advanced-properties.md)
and [runtime safe editing](runtime-safe-editing.md), and reproduce the
[F5 comparison](embedded-display-investigation.md). Persistent dot grey-screen
root cause and the host/official-renderer strict errors remain unresolved.

Final live verification: `application-delivery-live` exited **0**, with **84/84**
native/runtime assertions and zero failures in the real editor-to-child debugger
workflow, including scene assignment undo/redo and serialization. Fresh import,
authoring, runtime and editor logs contain no ERROR/leak. Results and full live
logs are retained under `evidence/runtime-safe/`. Same-node unload/reload obtains
a new RID generation in its debugger ID, so stale requests cannot target the
replacement load. Final shell syntax and `git diff --check` exited 0.
