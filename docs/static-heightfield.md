# Static fixed-resolution heightfield

Linux x86_64, Godot 4.7.2 .NET and MuJoCo 3.16.0 only. Add an
`MjStaticHeightField` node beneath a configured `MjRuntimeWorld`, assign an
`MjHeightFieldData` resource, and save the scene/resource. The resource contains
width, depth and row-major `PackedFloat32Array` heights. Width/depth are 2..256,
exactly width*depth finite samples, within +/-10000 metres. Samples increase in
local X across columns and local Z across rows, centred horizontally, with one
metre spacing. Node poses support translation/rotation; scale and shear fail.

This is a dedicated static terrain node. Ordinary Godot `HeightMapShape3D` now has a separate [bounded native path](native-heightmap.zh-CN.md). Dynamic
terrain bodies, holes/NaNs, sculpting and streaming are unsupported. Existing
native shapes include box/sphere/plane and [CylinderShape3D](../tests/native_cylinder/README.zh-CN.md). Native cylinders and MJCF cylinder model editing have separate entry points.

`request_apply(expected_revision=-1)` queues an add or replacement. Resolution
cannot change on a live terrain; remove then add a new grid. `request_remove()`
queues removal. True means queued, not successful. Observe `edit_finished(result)`
with request ID, success, error, body RID and revision. Duplicate pending requests
are rejected. `pending_request`, `last_error`, `revision` and `dirty()` support UI
feedback. Change the design, explicitly Apply, or restore a previously saved design
and Apply it to discard changes. There is no terrain sculpt/undo tool in this scope.

The native physics-step boundary validates a copied request, temporarily pauses,
builds a candidate combined model, transfers compatible state, commits or restores
metadata on failure, and restores the prior pause state. No worker/background
compiler or UI-thread mutation of active model/data is used. A running world may
advance in that same tick after commit. Normal world step commands are not dropped.
Deletion cancels queued requests and releases owned native geometry; an unobserved
successful add is also cleaned up. A removed/re-added terrain has a new RID and
revision starts again at 1. Ownership and expected revision reject stale requests.

Visible mesh updates only after success at runtime. Changing the node transform
without Apply leaves the committed visual aligned with its collision. Later edits
made while a request is pending remain dirty; they do not mutate that request.
Editor preview follows the design. Saved resources/scenes store design, not live
RID, revision, velocities or checkpoints.

The mesh includes side walls and a base one metre below the minimum height. It uses
the same cell diagonal as MuJoCo. Rays use compiled heightfield geometry, return
this node as collider, its body RID and shape index 0, and respect layer masks,
exclusions, inside-origin and back-face policy. The implementation follows the
[MuJoCo heightfield coordinate/data convention](https://mujoco.readthedocs.io/en/stable/XMLreference.html#asset-hfield)
and checks the fixed [3.16 ray implementation](https://github.com/google-deepmind/mujoco/blob/3.16.0/src/engine/engine_ray.c)
against the generated visible triangles. Contact identity is retained through the
native geometry-owner map.

## Validation and dot GUI steps

Build the extension from this commit using the existing Linux build instructions;
P2 requires the new native code. With the fixed Godot binary and staged libraries:

```sh
OUT=/tmp/heightfield-new GODOT_BIN=/path/to/fixed-dotnet-godot \
  bash tests/heightfield/run.sh
```

The disposable project contains two tiny slide models, a box, and generated
`HeightfieldDemo.tscn`. No G1 assets/stress workload. Every executed stage's exit
code is in `executions.tsv`. Logs are checked for ERROR/leak, and results.json
requires the unique structured success report. Failed/timeout stages stop the
runner; cold import 139 remains an independent known limitation, never a pass.

For actual GUI acceptance, open OUT/project with the fixed .NET editor and run
`HeightfieldDemo.tscn`. Confirm the box and two small spheres settle on the visible
terrain. U changes the authored corner (dirty=true); A applies it; repeated A
while pending is rejected; D removes; A adds again; P toggles pause. The overlay
shows pending ID/revision/error. Exercise U/A/D/P with repeated clicks/key presses,
then stop, reopen the saved scene, and verify its authored initial design returns.
In the editor, change a design height and observe preview; save/reopen the resource.
A runtime U edit is deliberately not saved by the example. For invalid dimensions,
NaN, scale and stale revision, the automated script checks rejection and retained
state. GUI checks are independent of headless startup and need dot confirmation.

Known verification limit: input/stale/pose/resolution failure paths are exercised;
allocator exhaustion and an artificially forced MuJoCo compiler failure are not
injected. The candidate compiler rollback branch is implemented but is not claimed
as a forced-failure runtime test. Terrain UI polish, a typed C# terrain-specific
facade remain separate workflows; generic HeightMapShape3D now has the native entry point linked above.

## Physics material

`physics_material_override` is a saved Godot PhysicsMaterial exposed in the Inspector.
Friction (0..1) and rough are applied through the same explicit terrain Apply transaction;
nonzero bounce is rejected. A queued snapshot captures the numeric values, and later
resource edits remain dirty. No material defaults to friction=1, bounce=0. Native body
pairs retain the existing signed rough-material combination; imported MJCF contacts
retain MuJoCo priority/solmix rules. See [material setup and acceptance](native-heightmap.zh-CN.md).
