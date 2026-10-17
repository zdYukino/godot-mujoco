# Linux G1 bounded-actuation checks

Requires a C++17 compiler, Python 3, MuJoCo **3.16.0** development files, a freshly built Linux GDExtension in `demo/addons/godot_mujoco/bin`, Godot 4.7.2 .NET and .NET SDK 8.

```sh
. /workspace/shared/tools/env.sh   # optional environment-specific SDK setup
MUJOCO_ROOT=/path/to/mujoco-3.16.0 GODOT=/path/to/godot \
  OUT=/tmp/g1-validation-new tests/g1_actuation/run.sh
```

Choose a new output directory per run. Nothing imports into the checked-out demo's `.godot` cache; the script stages an isolated copy and builds C# there. No upstream executable/script is run. Original assets are hash-verified and only read. A locally authored generator produces the derived URDF, inventory and synthetic MJCF in `OUT/generated`, compares them byte-for-byte with checked-in fixtures, and loads the model from `/tmp` by absolute path.

## Native coverage

- Expected source and fixture dimensions and exact MuJoCo runtime version.
- 29 unique named joint/actuator/qpos/dof mappings, hinge types, correct actuator transmission and unit gear.
- Exact source joint/control limits; original effort limits mapped to joint and actuator force caps.
- Fixed base, zero gravity, disabled contacts, 0.001 s timestep, implicitfast.
- 58 individual ±0.02-rad targets plus one combined alternating target, each starting from a reset inside-limit pose and running 4,000 steps: **236,000 steps** total.
- Finite state and force, joint bounds, actuator force bounds and absence of MuJoCo warnings during each step.
- Every final target and non-target error ≤0.002 rad; non-target transient excursion ≤0.005 rad.
- 58 independent positive/negative saturation checks using synthetic high initial velocity and forward evaluation (not integrated dynamic trajectories).

Initial positions are clamp(0, lower+0.03, upper-0.03), so asymmetric elbow/knee limits do not make nominal zero invalid. No original physics or limit values are changed for those poses.

## Binding coverage

The GDScript and C# tests exercise the current MjWorld method names and named scalar/batch control access using the same inventory and synthetic fixture. See each script and its JSON result for exact trial counts and bounds. These bindings do not expose raw actuator forces, so force-limit enforcement and per-step saturation assertions belong to the native test.

This is scoped actuation/binding validation, not walking, balance, contact physics, GUI acceptance or a robot-control policy.
