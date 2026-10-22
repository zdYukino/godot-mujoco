# godot-mujoco

[中文默认入口](README.md) · [Chinese documentation index](docs/README.zh-CN.md)

This branch targets **Linux x86_64, official Godot 4.7.2 .NET, and MuJoCo 3.16.0**. It does not modify the engine. Other platform configurations and historical reports do not establish current support.

The native PhysicsServer integrates ordinary box/sphere/plane bodies and ray queries with imported models. The MuJoCo editor workspace provides model properties, viewport selection and transforms, undo/redo, portable resources, and explicit runtime application. `MjRuntimeWorld` and `MjModelInstance` compose models in one physics space. The legacy `MjWorld` demonstration owns an independent model.

Build with CMake 3.24+ and a C++17 compiler:

```sh
cmake -S . -B build -DMUJOCO_VERSION=3.16.0
cmake --build build -j4
/path/to/official-godot --editor --path demo --rendering-method gl_compatibility
```

C# uses the addon’s typed `GodotMuJoCo.WorldHandle` / `InstanceHandle` API for inherited runtime nodes, state, control and request completion; see the [typed API guide](docs/typed-control.md). Existing `Call` / `Get` dynamic access remains compatible. C# regression tests require .NET SDK 8. Build before copying both addon directories, including the native libraries. Enable **MuJoCo Model Editor** for the independent editor preview. For `MjRuntimeWorld`, separately select the MuJoCo 3D physics engine and restart. The default `demo/Main.tscn` is the independent legacy `MjWorld` example; it does not require either setting. Save a project model before creating a runtime scene or simulation playground. See the [current installation guide](docs/linux-install.zh-CN.md).

Free-base G1 import is explicit; fixed-base import remains the default. The relaxed free-base option has no gravity compensation or synthetic position drives. Falling is expected; standing and walking are not implemented.

Per-world pause, exact N native steps, capture, and reset commands execute at the native physics boundary. State reset retains current topology and committed model edits. Environment rebuild explicitly discards runtime topology changes and constructs a saved scene in a separate World3D before replacement. UI, input, and the game clock remain active. Runtime snapshots do not automatically save design resources.

See the [implementation and validation report](docs/freebase-clock-validation.zh-CN.md) and retained English guides for [models](docs/portable-models.md), [editor properties](docs/editor-advanced-properties.md), and [runtime model edits](docs/runtime-safe-editing.md).

**Known limits:** cold-import exit 139 remains unresolved and is a non-blocking known issue for the approved daily workflows; cached retries are not fresh passes. Prefer GUI initialization before headless API editing of an existing project. The [2026-10-22 development baseline with known limits](docs/linux-development-baseline-20261022.zh-CN.md) passed independent lightweight dot GUI/F5 acceptance with normal software-driver configuration; earlier Vulkan-probe failures remain historical failures. Heavy G1/multi-G1 pressure did not pass and is left to user testing. Ubuntu 22.04 is a target, not a substitute for the recorded Debian-host acceptance. Main-thread physics is required; synchronous compilation may stall the UI. Windows and other platforms are not adapted for this baseline. No stable release, complete Godot-body/joint compatibility, Area, CharacterBody, standing, or walking support is claimed. Dedicated static `MjStaticHeightField` terrain is supported; general `HeightMapShape3D` and dynamic terrain are not. See [known issues](docs/known-issues.zh-CN.md).

[Typed C# control API](docs/typed-control.md): request completion, handle lifetime, and lightweight validation. Native `CylinderShape3D` is not implemented; MJCF cylinder editing/simulation is a separate model capability.

[Static fixed-grid heightfield](docs/static-heightfield.md): `MjStaticHeightField` / `MjHeightFieldData`, boundary transactions and matching visual/collision geometry; not general `HeightMapShape3D` support.

Dedicated terrain now includes an [editor panel](docs/heightfield-editor.zh-CN.md) and [typed C# TerrainHandle](docs/typed-terrain.zh-CN.md), with design drafts, undo, runtime targets and completion feedback. These feature-branch additions require independent acceptance and approval before another main merge.
