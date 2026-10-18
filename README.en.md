# godot-mujoco

[中文默认入口](README.md) · [Chinese documentation index](docs/README.zh-CN.md)

This branch targets **Linux x86_64, official Godot 4.7.2 .NET, and MuJoCo 3.16.0**. It does not modify the engine. Other platform configurations and historical reports do not establish current support.

The native PhysicsServer integrates ordinary box/sphere/plane/cylinder bodies and ray queries with imported models. The MuJoCo editor workspace provides model properties, viewport selection and transforms, undo/redo, portable resources, and explicit runtime application. `MjRuntimeWorld` and `MjModelInstance` compose models in one physics space. The legacy `MjWorld` demonstration owns an independent model.

Build with CMake 3.24+ and a C++17 compiler:

```sh
cmake -S . -B build -DMUJOCO_VERSION=3.16.0
cmake --build build -j4
GODOT_BIN=/path/to/official-godot scripts/import_headless.sh demo
/path/to/official-godot --editor --path demo
```

C# regression tests require .NET SDK 8. Select the MuJoCo 3D physics engine, restart, and enable the `mujoco_editor` plugin. Save a project model before creating a runtime scene or simulation playground.

Free-base G1 import is explicit; fixed-base import remains the default. The relaxed free-base option has no gravity compensation or synthetic position drives. Falling is expected; standing and walking are not implemented.

Per-world pause, exact N native steps, capture, and reset commands execute at the native physics boundary. State reset retains current topology and committed model edits. Environment rebuild explicitly discards runtime topology changes and constructs a saved scene in a separate World3D before replacement. UI, input, and the game clock remain active. Runtime snapshots do not automatically save design resources.

See the [implementation and validation report](docs/freebase-clock-validation.zh-CN.md) and retained English guides for [models](docs/portable-models.md), [editor properties](docs/editor-advanced-properties.md), and [runtime model edits](docs/runtime-safe-editing.md).

**Known limits:** cold-import exit 139 remains unresolved; cached retries are not fresh passes. The standalone game-window run passed, while the editor GUI run emitted host Vulkan-probe ERROR messages and therefore failed the strict gate despite exit 0. Main-thread physics is required. Synchronous compilation may stall the UI. No stable-baseline, complete embedded-F5, non-Linux, Area, CharacterBody, terrain, full Godot-joint, standing, or walking acceptance is claimed.
