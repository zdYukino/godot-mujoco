> [中文使用指南](portable-models.zh-CN.md) · [当前范围与验证](freebase-clock-validation.zh-CN.md)。本文保留原阶段的英文说明；版本和支持范围以当前入口为准。

# Project-owned MuJoCo models

Branch `codex/portable-model-runtime`, starting at the accepted
`bb1294e4f1d074d2a7c6a3852b428d83020ae5b3`. Linux only, Godot 4.7.2 .NET,
MuJoCo 3.16.0 and .NET SDK 8; no main promotion without independent acceptance.

## Project resource workflow

Enable the MuJoCo editor plugin, import MJCF or open an existing `.gmj.json`,
and choose **Save project model**. This publishes an immutable bundle beneath
`res://mujoco_models/model_<content-hash>/` containing:

- `model.tres`: `MjModelResource`, canonical MJCF plus authored/saved initial state;
- `model.xml`: human-readable canonical MJCF with include contents expanded;
- `assets/<sha256>.<extension>`: byte-identical mesh/texture dependencies;
- `sources/<sha256>.xml`: archived original XML/include bytes for provenance.

Original files are only read. Original path strings remain in provenance, never
as runtime dependency paths. Actual MJCF assets use `assets/...`, resolved from
the resource's current directory at load time. Copy the entire Godot project,
including its addon binary, to relocate it. Filesystem projects are supported;
PCK/ZIP export requires extracting filesystem assets and is not claimed here.

**Open project model** loads a saved `.tres` for preview/editing. Saving edits
creates a new content-addressed bundle; it does not overwrite an existing bundle
or update every scene using it. This gives an explicit application boundary.
Identical imports deduplicate; same-named assets with different bytes have different
hash filenames. Missing or corrupted dependencies fail validation before replacing
an active document. A complete staged bundle is compiled before atomic directory
rename. Failed operations remove staging files and leave published bundles intact.

Legacy `.gmj.json` files remain supported by **Open document** and still need their
original absolute assets until **Save project model** successfully migrates them.
Do not infer that changing the filename makes an old JSON document portable.
Source includes are archived and flattened into canonical MJCF; their old relative
layout is not used at runtime. Additional dependency classes unsupported by the
existing preview remain explicitly rejected.

## Implementation boundary

`MjEditorDocument.asset_manifest`, `portable_snapshot` and `restore_at` enumerate,
rewrite and validate canonical XML asset attributes, including cube texture faces.
All native string operations cross MuJoCo's C API. Do not dereference an mjStringVec
as a host GCC STL container: the pinned prebuilt library has a different C++
container representation. This was caught with a native backtrace during development.

`package_builder.gd` is usable by editor tools and automated build scripts;
`model_resource.gd` validates dependency hashes and creates independent native
preview documents. Each document owns its own model/data; resource snapshots are
never mutated by a preview.

## Asset acceptance

```sh
source /workspace/shared/tools/env.sh
OUT=/tmp/gmj-portable-new tests/portable_runtime/run_assets.sh
```

This checks includes, duplicate imports, same-label/different-content packages,
same-basename/different-byte meshes, missing-source rollback and missing-packaged
asset diagnostics. It copies the entire project without `.godot`, renames BOTH
original source directories and the original project out of the recorded paths,
then cold-imports and advances the relocated model using MuJoCo. Neither the
original absolute assets nor original project are available during this test.

## Reusable scenes and shared native physics

1. Select **MuJoCo** under Project Settings → Physics → 3D → Physics Engine,
   restart Godot, and enable the MuJoCo editor plugin.
2. **Import MJCF**, **Import G1 URDF**, or **Open project model**. Edit fields and
   **Apply to physics**. G1 import reads the original 29-DOF URDF without altering
   it, fixes its base, and synthesizes bounded position drives (initial kp=100,
   kv=10). This is an explicit G1 adapter, not a general URDF importer.
3. **Save project model**, then **Create runtime scene**, and save a `.tscn`.
   The scene references one explicit immutable resource revision. Saving another
   revision does not modify existing scene references. Pending/unsaved edits block
   scene creation; saving a legacy JSON file does not publish a runtime revision.
4. Open the generated scene in Godot's normal 3D editor. It contains an
   `MjRuntimeWorld` root and an `MjModelInstance` child. Add more model instances
   beneath that world and assign their resources. Position fixed-base G1 at about
   Y=1.1 above a floor (the imported base origin is at its pelvis).
5. Add normal Godot `StaticBody3D` terrain and `RigidBody3D` obstacles. They use the
   **same World3D space and native mjModel** as imported models, with real contacts.
   The acceptance scene uses box terrain and an ordinary falling box. The G1
   adapter uses collision bits 2/1 to avoid self-contact; the obstacle's mask is 3.
6. Save, close, reopen, and run the scene. Copy the whole project to move it;
   neither the original external XML nor original robot asset directory is needed.

`MjRuntimeWorld.world_model` owns the complete MuJoCo option profile (including
integrator, timestep, gravity, solver and tolerances). Each loaded resource must
match every `mjOption` field exactly. Conflicts are rejected before replacing the
live model, with the conflicting field named in `last_error`. Ordinary Godot
project/default-area gravity changes cannot override this authored profile.
One runtime-world owner is permitted per World3D; use a separate SubViewport and
World3D for independently configured worlds. Configuration happens paused before
model insertion. Authored timesteps are accumulated exactly against Godot's frame
step, with a minimum of 0.0001 seconds for the synchronous stepping budget.

Each instance owns a model RID, a unique native name prefix and independent joint,
control and activation state. Whole-spec composition retains multiple free roots,
world geometry and attached model entities. A compiled element-count check rejects
composition that loses joints, geoms, actuators, equality constraints, tendons or
sensors. Existing compatible state survives insertion/removal. Native model
removal requested from physics callbacks is deferred until callback flushing ends.
No PhysicsServer3D full-joint compatibility is implied by MJCF constraint retention.

The node transform is the **initial placement**, not a continuously driven physics
pose. Do not scale model nodes: edit source geometry/mass explicitly. To apply a saved design revision while loaded, call `request_model_edit(resource)`
and observe its completion/revision, or use the editor runtime target selector.
This queues a synchronous transaction at the next native physics-step boundary;
compatible live state is retained and failures roll back. Direct assignment while
loaded remains rejected. Explicit unload/assign/load remains available when a
state reset is intended. See [runtime safe editing](runtime-safe-editing.md). Preview nodes never step
or mutate the shared resource. Actual runtime visual transforms come from MuJoCo.
Mesh and primitive geometry is shown with flat colors; texture/material rendering
parity and filesystem-free PCK export are not claimed.

GDScript control (native names are relative to this instance):

```gdscript
var robot = $MuJoCoWorld/Model
robot.set_control("left_elbow_joint_position", 0.8)
var angle = robot.state().joints.left_elbow_joint.qpos[0]
$MuJoCoWorld.set_paused(true)
```

C# calls the same stable GDScript node API; native extension classes do not require
custom generated C# wrappers:

```csharp
var robot = GetNode<Node>("MuJoCoWorld/Model");
bool accepted = robot.Call("set_control", "left_elbow_joint_position", 0.8).AsBool();
var state = robot.Call("state").AsGodotDictionary();
```

The runtime rejects global userdata, mocap bodies and keyframes explicitly;
CharacterBody3D, Area3D and complete Godot joint compatibility remain out of scope.
The original G1 is a fixed-base control/contact fixture, **not walking acceptance**.

## Full runtime acceptance

```sh
OUT=/tmp/gmj-runtime-new tests/portable_runtime/run_runtime.sh
```

This authors an edited G1 (mass, kp/kv, angle and control), saves an ordinary Godot
scene with two independent instances plus normal bodies, exits, then starts a new
runtime process. It checks actual joint movement and model/native-body contacts,
option conflicts, rollback, instance destruction during callbacks and multiple free
roots. It then copies the project without caches, renames the original project,
removes the relocated original robot assets, cold-imports and repeats all checks.
A separate .NET process checks C# control and actual motion. Finally the editor
opens the relocated package, emits the real Apply/Save/Create-scene signals and
checks saved references plus retained original source archive bytes.

For real-renderer evidence, after the runner completes:

```sh
godot --editor --path "$OUT/relocated" --rendering-method gl_compatibility \
  -- --mj-editor-test --capture-dir=/tmp/gmj-images
godot --path "$OUT/relocated" --rendering-method gl_compatibility \
  --script res://capture_runtime.gd -- --capture=/tmp/gmj-images/runtime.png
```

The generated `RuntimeScene.tscn` is also the project's main scene for independent
manual inspection. Dot must independently build/pull, move the project, use the
actual editor controls, save/restart/run and inspect the contacts before promotion
to main. Cloud automation and screenshots do not replace that gate.
