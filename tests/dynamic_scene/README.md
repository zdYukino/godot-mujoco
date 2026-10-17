# Dynamic G1 world acceptance (Linux)

This project selects the native MuJoCo PhysicsServer3D backend. The G1 and boxes
are compiled into the **same space's mjModel/mjData**, alongside any ordinary
Godot static/rigid bodies. Meshes are generated from that compiled model and
updated from its actual geometry transforms; a render-only robot is not accepted.

Build with Godot 4.7.2 .NET, MuJoCo 3.16.0 and .NET SDK 8 as documented in
`docs/headless-baseline.md`. Then choose a new output directory:

```bash
source /workspace/shared/tools/env.sh  # cloud-specific; use local paths on dot
OUT=/tmp/gmj-dynamic-acceptance tests/dynamic_scene/run.sh
"$GODOT_BIN" --path /tmp/gmj-dynamic-acceptance/project \
  --rendering-method gl_compatibility
```

The runner copies a fresh project, the compiled addon and model assets; applies
the existing import helper (120-second timeout); runs quantitative acceptance
(180 seconds); then runs the actual UI's add/control/delete sequence headlessly
(120 seconds). Any nonzero process exit, missing report or engine/script error
fails. `results.json` contains each check, the exact extension hash, and the UI's
before/after object counts. `import.log`, `runtime.log`, `ui-smoke.log` are retained.

## Independent visual/screenshot acceptance

1. Launch without `--headless`. Before adding anything, capture the floor-only
   scene and visible counters. It starts paused with one object (the floor).
2. Click **Add G1 robot** (G), then **Add falling obstacle** (O). Capture the
   same view with G1 and the orange obstacle, with nonzero joint/drive counters.
3. Click **Run** (Space). Observe the obstacle contact G1 and/or settle on the
   floor. Pause. Select G1 in the dropdown, change the elbow slider, then run
   to observe articulation. These are bounded synthetic drives, not walking.
4. Pause, select the obstacle, **Delete selected** (Delete); delete G1 next.
   Confirm the visible meshes disappear and counters return to floor-only.
   Repeat adding/deleting G1 and obstacles at least twice; keep before/after
   screenshots tied to the exact tested commit.

Edits while running are rejected with an on-screen message. Deleting the
selected model removes its physics instance first, and releases its display
meshes only after the transaction succeeds. The floor is intentionally not in
the deletion dropdown. `--demo-sequence` starts with G1 plus an obstacle for a
quick scene demonstration. `--ui-smoke` exercises the UI methods and exits;
neither headless mode establishes rendered acceptance.

## Quantitative scope

Checks cover real model body/geometry/joint/actuator counts and stable instance
RIDs; original URDF loading; bounded elbow drive; paused simulation time;
two robot instances; free obstacle pose/velocity and robot joint/control
preservation across insert/delete; ordinary RigidBody3D pose, linear and angular
velocity preservation; failed parse and **failed candidate compilation** rollback;
duplicate labels and stale RIDs; forbidden running edits; floor collisions and
an actual G1/obstacle contact pair; finite state and MuJoCo warnings; repeated
robot cycles; separate-space isolation, space disposal and return to empty model.

The G1 remains fixed-base. Source URDF, all 34 meshes and LICENSE remain byte
unchanged. Runtime-only adaptations resolve mesh paths, add synthetic position
drives and gravity compensation, and exclude robot self-collision while keeping
robot/obstacle contacts. See [API and limitations](../../docs/dynamic-world.md).
