# Native PhysicsServer3D acceptance

This isolated project selects `MuJoCo` as Godot's 3D physics engine and uses
ordinary `RigidBody3D`, `StaticBody3D`, `CollisionShape3D`, and `World3D` APIs.
It does not instantiate `MjWorld`, call MuJoCo stepping, or change the existing
pendulum/G1 demo settings.

## Reproduce

First build and stage the extension using the repository's pinned **Godot
4.7.2 .NET** and **MuJoCo 3.16.0** instructions. Then run:

```bash
GODOT_BIN=/absolute/path/to/Godot_v4.7.2-stable_mono_linux.x86_64 \
  OUT=/tmp/mujoco-native-acceptance tests/native_backend/run.sh
```

The runner copies this project and the built addon to `$OUT/project`, uses the
existing cold import helper (1000 ms frame-delay workaround), and executes
headlessly at 60 fixed FPS in three repetitions (`REPEAT=3`, overridable).
Each repetition uses separate processes for the original 44 checks and 25
additional primitive/ownership checks: 207 checks across six processes by default.
It leaves `import.log`, `runtime-N.log`, `results-N.json`, `primitives-N.log`,
`primitives-N.json`, and aggregate `results.json` under `$OUT`.
`OUT/project` must not already exist, so import always starts with a fresh cache.
Import has a separate 120-second timeout and never retries a failed cache.
The report records
the Godot version and SHA-256 of the exact staged extension binary. The 90-second execution timeout, missing report,
nonzero engine exit, engine/script errors, or failed checks fail the runner.
Required but unsupported functionality is a failure, never a silent skip.

## Coverage and thresholds

- Runtime `MjPhysicsServer3D` identity, not just the project setting.
- Ordinary one-meter rigid box dropped from Y=3 onto a static box floor whose
  top surface is Y=0. After four simulated seconds, rest center Y must be
  0.5 ± 0.04 m and speed below 0.08 m/s. These tolerances allow compliant
  contact at 1/60-second ticks while rejecting penetration/fall-through.
- Finite transform, unit rotation determinant and orthonormal basis.
- Ray RID, object ID/reference, position and normal; layer masks, one/all
  exclusions, and an outside miss.
- Rotated, translated, asymmetric box with an offset collision shape: hits on
  all three local axes validate coordinate/basis conversion, extents and normals.
- Linear velocity read/write via node and server, followed by displacement.
- Three detach/reentry cycles, checking absence while detached and settling
  after reentry.
- Distinct worlds and isolated rays, disposal of a world and its objects,
  empty replacement world, and removal of all body query references.
- Sphere falling onto an infinite plane, rest height/speed, sphere and plane
  ray fields, inside-ray behavior, transformed plane offset/normal, and cleanup.
- Contact layer filtering and collision exceptions; ray masks are independent
  of the target body's collision mask.
- Server-owned classes cannot be instantiated through ClassDB, including
  editor documentation's default-property probes.

This is minimal native-backend acceptance, not complete Godot physics
conformance. Areas, joints, CCD, character motion and complex/concave shapes
are outside its claims. Headless quantitative checks do not establish rendered
GUI behavior. Cloud results and the independent acceptance gate are recorded in
[`docs/native-backend-validation.md`](../../docs/native-backend-validation.md).

## Manual rendered demo

After the runner has staged `$OUT/project`, launch the separate visual scene on
an available desktop display (omit `--headless`):

```bash
/path/to/Godot_v4.7.2-stable_mono_linux.x86_64 \
  --path /tmp/mujoco-native-acceptance/project \
  --rendering-method gl_compatibility res://VisualDemo.tscn
```

An orange one-meter ordinary `RigidBody3D` falls onto the visible static floor.
The label shows the actual backend, Y position and speed. It remains open;
press R to drop the same body again. The scene explicitly rejects a non-MuJoCo
backend. Quantitative acceptance does not depend on this camera/rendering path.
No rendered screenshot has been validated in the current display-less executor.
