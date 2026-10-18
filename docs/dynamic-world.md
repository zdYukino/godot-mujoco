> [中文使用指南](README.zh-CN.md) · [当前范围与验证](freebase-clock-validation.zh-CN.md)。本文保留原阶段的英文说明；版本和支持范围以当前入口为准。

# Transactional model instances in the native MuJoCo space

Linux milestone based on independently accepted `b32fd22f0405caf086b8fb866160694e88853c9e`.
The parent task preserved that commit on `baseline/linux-native-backend-20261018`
and advanced main; this milestone is developed on `codex/dynamic-g1-world` only.

## Runtime model and ownership

The extension's PhysicsServer3D exposes these additional methods via `call`:

| Method | Purpose |
| --- | --- |
| `scene_pause(space, paused)` | Pause/resume integration for this space; pending native changes are rebuilt first |
| `scene_import_g1(space, path, label, pose)` | Import the fixed-base G1 URDF; return a model-instance RID or invalid RID |
| `scene_add_box(space, label, pose, size, mass)` | Add a box to the same model; zero mass selects a static box |
| `scene_remove(space, object)` | Remove an instance transactionally; false leaves the existing world intact |
| `scene_info(space)` | Revision, error, instance list, actual compiled dimensions, time, contacts and warnings |
| `scene_state(space, object)` | Named joint qpos/qvel, controls, geometry poses and object identity |
| `scene_geometry(space, object)` | Compiled geometry/mesh data for creating display resources |
| `scene_set_control(space, object, joint, target)` | Set a finite, within-limit synthetic position target |

Use the main thread and pause before topology edits, outside physics callbacks.
This is synchronous, bounded desktop-model editing, not asynchronous streaming.
The provided scene pauses explicitly; it never steps a second MjWorld instance.

Instance RIDs are allocated by the server's RID owner, with generation-aware
identity. They are **model instance handles**, not ordinary Godot Body RIDs.
Names are unique within a space; each instance also gets an internal RID-based
prefix for MuJoCo bodies, joints, actuators, meshes and geometry. Internal MuJoCo
array indices may change after a commit and must never be cached by clients.
The UI selects these instances by dropdown; this milestone does not turn each
URDF link into a Godot PhysicsBody3D or add mesh ray-query support to the minimal
native backend. Existing native-body queries and collision behavior remain.

The server owns imported specs until deletion or space disposal. Each candidate
uses MuJoCo's deep-copy attachment, so a rejected candidate cannot steal source
assets. Fixed-base URDF world geometry is attached together (preserving fused
pelvis geometry and shared assets); a free box attaches its root body directly
to retain MuJoCo's top-level-freejoint invariant. A successful transaction frees
the previous model/data. Deletion frees the instance RID and source spec;
space disposal releases all remaining instances. The scene frees their meshes.

## State and rollback contract

Edits first build a separate candidate model/data. Compatible named joints keep
their full qpos/qvel (including free-body quaternion and six velocities) and
solver warm-start values; matching named drives keep controls; time is retained.
Native Godot body pose/velocity state is reapplied using its stable RID. New
bounded G1 joints start inside their limits with matching controls. Geometry
poses and contacts are derived again with `mj_forward`.

Only successful compilation/allocation and finite candidate position checks
replace the live model and advance revision. Parse, input, duplicate-name,
candidate-compile and stale-handle failures return invalid RID/false, expose
`last_error`, and preserve the previous model, states, object list and revision.
Tests use a valid-but-tiny positive dynamic mass to force a true candidate
compile failure, in addition to a malformed URDF parse failure.

This milestone edits topology by adding/removing immutable supported instances.
It does not support replacing a robot's topology in place or arbitrary plugins,
tendons, actuator activation dynamics, or serialization of all solver internals.
Contact constraints are rebuilt; existing contact impulses are not a preserved
state contract. Spaces with imported objects use `implicitfast` and the existing
substeps (at most 0.002 seconds) to stabilize damped articulated drives.

## G1 compatibility and explicit adaptations

Import the copied original
`demo/assets/robots/unitree_g1/g1_29dof_mode_18/g1_29dof_mode_18.urdf`.
MuJoCo 3.16.0's default path handling otherwise repeats `meshes/meshes/`.
The importer parses without rewriting the file, resolves **spec copies** of
mesh filenames against the asset's `meshes` directory, and validates the
fixed-base 29-joint/34-mesh/no-source-actuator contract. The API is intentionally
G1-specific, not a claim of general URDF or arbitrary MJCF import compatibility.
Local filesystem-backed projects are supported; packed/exported resource import
is outside this milestone.

The source supplies no actuators or walking policy. For this demonstrator only,
the runtime spec gets 29 unit-gear position drives (kp=100, kv=10), using source
joint ranges and actuator-force bounds. Robot bodies use gravity compensation;
the source fixed base is retained. Robot collision geometry uses layer 2/mask 1
to exclude self-contact, while obstacles use layer 1/mask 3. World gravity and
robot/obstacle contacts remain active. Visual-only source geometry stays
non-colliding. Original source mass/inertia/mesh bytes are not rewritten.

Coordinates use the existing right-handed mapping `(x,y,z) -> (x,-z,y)` for
placement, geometry poses and mesh vertices. Imported root placement takes a
Godot rigid transform. No scaled/sheared poses or nonfinite inputs are accepted.

## Acceptance

Run [the dynamic scene suite](../tests/dynamic_scene/README.md), then the original
native-backend suite (207 checks), MjWorld scenes and all three G1 regressions.
Repeat the original-assets SHA-256/Git-blob verification. Retain cold import,
per-process exit codes and the exact addon binary hash, not just PASS markers.

The new scene's actual rendered before/after G1/obstacle screenshots are a
required **dot independent acceptance** step. Cloud headless UI execution or
any cloud image cannot substitute for those screenshots. After this milestone,
stop: full editor plugins, CharacterBody3D, Area3D, native joint compatibility,
walking and non-Linux work remain separate tasks.
