# godot-mujoco

Import, edit and run MuJoCo models in Godot, with static maps and supported Godot bodies in the same physics world.

[中文](README.md) · [Example catalog](examples/README.md) · [Installation and troubleshooting (Chinese)](docs/linux-install.zh-CN.md) · [Documentation index](docs/README.zh-CN.md)

## Quick start

The current baseline is Linux x86_64, Godot 4.7.2 .NET, MuJoCo 3.16.0 and .NET SDK 8.0.426. Source checkouts do not contain compiled native libraries; run the setup wizard before first use.

```bash
./boostup.sh                      # Check the environment, install or import tools, and build the addon
./boostup.sh --check              # Inspect existing tools
./boostup.sh --rebuild            # Rebuild with installed tools
./boostup.sh --configure          # Choose tool sources again or reinstall
./em_run.sh                       # Open the Godot project manager
./em_run.sh --exp                 # Choose an example
./em_run.sh --exp shape_gallery   # Open a specific example
./em_run.sh --new my-project      # Create and open a local project
```

The wizard can download or import Godot Mono and .NET. On Ubuntu 22.04/24.04 it can install missing system dependencies after confirmation; other Linux distributions require those dependencies to be prepared manually. See the [installation guide](docs/linux-install.zh-CN.md).

## Repository layout

```text
godot-mujoco/
├── src/          # Native extension source
├── addons/       # Runtime and editor addons
├── assets/       # Shared assets
├── examples/     # Examples and project template
├── projects/     # Locally created projects (generated, Git-ignored)
├── scripts/      # Setup, build and launch scripts
├── tests/        # Tests and acceptance checks
├── docs/         # Documentation and architecture diagrams
└── third_party/  # Local tools and environment (generated, Git-ignored)
```

<details>
<summary>Detailed repository layout</summary>

`[generated, ignored]` denotes local output absent from a fresh clone; `[optional]` appears only when needed.

```text
godot-mujoco/
├── README.md / README.en.md       # Chinese and English entry documentation
├── boostup.sh                     # Install, configure, check and build wizard
├── em_run.sh                      # Launch Godot, an example or a new project
├── CMakeLists.txt                 # Native build, dependency pins and addon staging
├── global.json                    # Pinned .NET SDK selection
├── .gitignore / .gitattributes    # Git ignore and file attribute rules
├── .github/workflows/             # CI builds, acceptance and upstream version checks
├── .vscode/                       # Local VS Code settings/index; not ignored as a whole
├── src/                           # C/C++ GDExtension source
│   ├── register_types.*           # GDExtension type registration
│   ├── mj_world.*                 # Independent MjWorld simulation interface
│   ├── mj_editor_document.*       # MJCF documents and editing transactions
│   └── physics/                   # MuJoCo backend, bodies, joints and spatial queries
├── cmake/                         # Build helpers, symbol export map and mobile patches
├── scripts/                       # Setup, launch, build and validation implementation
│   ├── bootstrap.py               # Download/import tools, configure and build
│   ├── local_tools.py             # Tool paths, version checks and local state
│   ├── em_run.py                  # --exp / --new implementation
│   ├── setup.sh / setup.py        # Lower-level check / build / smoke interface
│   ├── ci/toolchain.json          # Pinned versions, official URLs and checksums
│   ├── ci/install_godot.py        # Verified Godot download and extraction
│   └── build_*.sh / verify_*.sh    # Android / iOS builds and binary checks
├── addons/                        # Canonical plugin source and staged libraries
│   ├── godot_mujoco/             # GDExtension config, runtime scripts and C# API
│   │   └── bin/                  # [generated, ignored] Native/MuJoCo libraries; .gitkeep retained
│   └── mujoco_editor/            # MuJoCo editor plugin source
├── assets/                       # Shared original assets maintained with source
│   └── robots/unitree_g1/        # Original G1 URDF, meshes, provenance and license
├── examples/                      # Example source and required assets
│   ├── _shared/                  # Shared sky, floor shader and UI script; no project.godot
│   ├── shape_gallery/            # Falling shapes and collisions
│   ├── g1_passive/               # Uncontrolled G1 robot
│   ├── sdf_terrain/              # SDF stairs, depression and rough terrain
│   ├── pendulum/                 # Former demo/: independent MjWorld and diagnostics
│   ├── light_workflow/           # C# control and terrain developer example
│   ├── templates/new_project/   # --new template: project.godot, Main.tscn, README, .gitignore
│   └── <each of the four ready examples>/
│       ├── addons -> ../../addons  # [generated, ignored] Shared addon link from setup
│       ├── .godot/               # [generated, ignored] Cache created on opening
│       └── bin/ / obj/           # [optional, generated, ignored] .NET build output
├── third_party/                  # [generated, ignored] Local tools and environment
│   ├── godot/                    # Complete Godot Mono engine and GodotSharp/
│   ├── dotnet/                   # .NET SDK: dotnet, sdk/, shared/, etc.
│   ├── cmake/                    # [optional] Installed when system CMake is too old
│   ├── cache/                    # [optional] Downloaded tool archives
│   ├── environment.json          # Relative tool paths, versions and build status
│   ├── environment.sh            # Environment variables for terminal use
│   └── .boostup.lock             # Prevents concurrent setup processes
├── build-linux/                  # [generated, ignored] Default build; --build-dir overrides it
│   ├── CMakeCache.txt / CMakeFiles/ # CMake configuration and intermediate files
│   ├── _deps/                    # godot-cpp / MuJoCo dependencies and sub-builds, depending on SDK mode
│   └── libgodot_mujoco*.so        # Linux extension, staged into shared addon bin/
├── projects/                     # [generated, ignored] User projects created by --new
│   └── <project-name>/
│       ├── project.godot / Main.tscn # New project and flat-ground falling-ball scene
│       ├── addons/               # Complete addon/library copies, independently movable
│       ├── global.json / README.md / .gitignore
│       └── .godot/               # [optional] Import cache created on opening
├── tests/                        # Setup, examples, physics backend and editor acceptance
│   ├── setup/                    # Isolated bootstrap and launcher tests
│   ├── example_projects/         # Acceptance for the four directly openable examples
│   └── native_*/ / spatial_queries/ / …
├── docs/                         # Installation, features, known issues and validation evidence
│   └── pics/                     # Architecture diagrams and their sources
├── ARCHITECTURE.zh-CN.md         # Architecture documentation and history
└── LICENSE                       # Project license
```

</details>

## Run an example

After the one-time [addon build](docs/linux-install.zh-CN.md), run `./em_run.sh --exp` to choose an example. Alternatively, import its `project.godot` in the Godot project manager, wait for resource import and press F5.

| Example | Project file | Main scene |
|---|---|---|
| [Shape gallery](examples/shape_gallery/README.md) | `examples/shape_gallery/project.godot` | `Main.tscn` |
| [Passive G1](examples/g1_passive/README.md) | `examples/g1_passive/project.godot` | `G1.tscn` |
| [SDF terrain](examples/sdf_terrain/README.md) | `examples/sdf_terrain/project.godot` | `Main.tscn` |
| [Independent pendulum](examples/pendulum/README.md) | `examples/pendulum/project.godot` | `Main.tscn` |

Keep the repository layout intact so examples can use shared addons and assets. The first three use the shared MuJoCo physics backend; the pendulum uses independent MjWorld. G1 has no standing or walking controller and is expected to fall; multi-robot hot-add has [known limitations](examples/g1_passive/README.md).

## Import and run a model

1. Open a 3D scene. In the **MuJoCo** dock, select **MJCF 文档**, expand **文档 / 导入 / 发布** and enable **显示 MJCF 草稿（独立于正式场景）**.
2. Click **Import MJCF** and choose the model's `.xml`, keeping its includes, meshes and textures available. Click **聚焦模型** to frame it.
3. Select an object in the model tree or viewport, edit its fields and click **Apply** or **Discard**. Use **Run / Pause** to control the draft preview.
4. Click **Save project model** to save the model package, then **Create simulation playground** to save a simulation scene.
5. Open the generated scene, press F6 to run it and click **恢复仿真 / Resume**.

For G1, use **Import fixed G1** or **Import free G1 (relaxed)** to select a URDF. **Create runtime scene** creates world and model nodes for further scene authoring; use **Open project model** to reopen a saved package. See the [MJCF editor guide](docs/mjcf-editor.md) and [portable models guide](docs/portable-models.md).

## Import a map and configure collisions

1. Create and save a 3D scene with a **Node3D** root.
2. In the **MuJoCo** dock select **静态地图草稿**. Under **导入 / 独立包**, browse to a `.glb`, `.gltf`, `.obj` or `.stl` file.
3. Select the source units and up axis, then click **导入（保留脏数据）**.
4. Select each mesh in the map tree, choose a collision representation and click **验证并应用碰撞草稿**. Use **聚焦全图** and the viewport's **MuJoCo 显示** menu to inspect it.
5. Click **保存独立地图包**, then **Apply 到编辑场景**; save and run the host scene. Apply, save and rerun after changing collisions.

Reopen a saved map package using **打开地图包** and its `manifest.json`. See the [SDF terrain example’s map workflow (Chinese)](examples/sdf_terrain/README.md).

## Save and reopen

| Content | Save / open action |
|---|---|
| Editable MJCF document | **Save document / Open document**: `.gmj.json`; source assets remain in place |
| Portable model | **Save project model / Open project model**: `model.tres`; copy the entire package when moving it |
| Static map | **保存独立地图包 / 打开地图包**: `manifest.json`; keep the entire package |
| Scene layout | Godot **Save Scene**: `.tscn` |

## Architecture diagrams

### Repository layout: source, addons, examples and local projects

[![Repository layout](docs/pics/ARCHITECTURE-files.svg)](docs/pics/ARCHITECTURE-files.svg)

### Godot integration: editor preview, shared backend and independent MjWorld

[![Godot and MuJoCo integration](docs/pics/ARCHITECTURE-godot.svg)](docs/pics/ARCHITECTURE-godot.svg)

### Runtime communication: models, maps, bodies and the physics world

[![Shared physics world runtime](docs/pics/ARCHITECTURE-runtime.svg)](docs/pics/ARCHITECTURE-runtime.svg)

## Limits and further reading

Cold-import exit 139 and heavy G1/multi-G1 operation have known issues; see [known issues (Chinese)](docs/known-issues.zh-CN.md) and the [G1 limits](examples/g1_passive/README.md). SDF continuous sweeps still have unresolved exact-contact and grazing cases; callers must check query status and must not treat uncertified results as collision-free. The default 0.5 mm total spatial error budget applies to the compiled SDF; public sweeps do not establish dynamic-body CCD. See the [spatial query matrix](docs/development/spatial-query-matrix.md).

[Editor guide](docs/mjcf-editor.md) · [Heightfields](docs/static-heightfield.md) · [Typed control API](docs/typed-control.md) · [Runtime edits](docs/runtime-safe-editing.md) · [GUI workflow audit (Chinese)](docs/gui-workflow-audit.zh-CN.md)

Licensed under [MIT](LICENSE). See [third-party notices](addons/godot_mujoco/THIRD_PARTY.md); Unitree assets retain their original licenses and provenance.
