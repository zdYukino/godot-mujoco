# Dynamic G1 milestone: cloud evidence

Base: `b32fd22f0405caf086b8fb866160694e88853c9e` (independently accepted by dot,
as reported by the parent task). Development branch: `codex/dynamic-g1-world`.
Main and `baseline/linux-native-backend-20261018` are left unchanged.

Validated toolchain: Linux x86_64, Godot
`4.7.2.stable.mono.official.ed1daf0bf`, MuJoCo `3.16.0`, .NET SDK `8.0.426`,
.NET runtime `8.0.32`, CMake `4.4.4`, GCC `14.2.0`, godot-cpp
`godot-4.5-stable`. Existing tools survived environment restart; the environment
script still needs to be sourced. No repository AGENTS.md or local skills were
found. GitHub synchronization uses MCP, not SSH.

## Final validation

The complete command manifest is
`/workspace/shared/validation/dynamic-release/results.json`; each entry contains
the command array, cwd, actual process exit, elapsed time and log path.

| Validation | Result / process exit |
| --- | --- |
| CMake configure, extension build, linkage, standalone core | Pass / 0 |
| Original native backend runner | 207 checks / 0 |
| Fresh dynamic runner import | Pass / 0 |
| Dynamic physics/state/lifecycle suite | 86 checks / 0 |
| Actual visual-scene UI methods, headless | Pass / 0 |
| Fresh MjWorld import; HeadlessTest, ChaosPendulumTest, VisualDebugTest | Pass / 0 |
| MjWorld main scene, 120 frames | Pass / 0 |
| G1 native, GDScript, C# runner | Pass / 0 |
| All 36 original Unitree files | SHA-256 and Git blob checks unchanged |

The final dynamic report records the compiled extension SHA-256:
`0f143acf90e8f973669864d256dcb820e3b82d2b3414fb13f3987523a5a2ec2a`.
The UI report captures real instance/display counts of **1/1 before**, **3/3
after adding G1 and obstacle**, and **1/1 after deletion and repeated cycles**.

The initial 77-check suite passed; expanded 84-check suites passed twice with
fresh project caches. Final review added generic-RID removal transaction coverage
and a second-space replacement check, bringing the final suite to 86. Earlier
prototype attachment failures were retained in `dynamic-g1/attempt*` and are
not counted as passes. They led to separate attachment paths for fixed URDF
world geometry and top-level free boxes.

The new regression explicitly forces candidate compilation failure, not merely
bad input rejection. It also records an actual MuJoCo contact pair containing
both the robot and obstacle RIDs, verifies 29 drives per G1, and compares exact
joint qpos/qvel/control arrays across topology edits. Native RigidBody3D pose,
linear velocity and angular velocity are checked separately. Details and
limitations are in [dynamic-world.md](dynamic-world.md).

## Commands and logs

Build was isolated at `/workspace/shared/validation/dynamic-release/build` using
verified inherited dependency sources and the existing godot-cpp archive. All
extension source files were rebuilt; no baseline source checkout was overwritten.
The new runner stages an independent project under `dynamic-release/dynamic`.

```bash
source /workspace/shared/tools/env.sh
cmake -S . -B /tmp/gmj-dynamic-build \
  -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
  -DMUJOCO_VERSION=3.16.0 -DGMJ_BUILD_CORE_SMOKE=ON
cmake --build /tmp/gmj-dynamic-build -j 8
OUT=/tmp/gmj-dynamic tests/dynamic_scene/run.sh
OUT=/tmp/gmj-native tests/native_backend/run.sh
MUJOCO_ROOT=/tmp/gmj-dynamic-build/_deps/mujoco-src \
  GODOT="$GODOT_BIN" OUT=/tmp/gmj-g1 tests/g1_actuation/run.sh
```

Use fresh output directories. Cloud .NET builds required the already-established
scoped write permission for `/home/agent/.dotnet/corefx/Runtime/SharedMemory`;
there is no project/dependency version change to work around that sandbox rule.

Machine-local final evidence:

- `dynamic-release/run.py`, `results.json`, `configure.log`, `build.log`,
  `linkage.log`: complete harness and process evidence.
- `dynamic-release/dynamic/results.json`, `import.log`, `runtime.log`,
  `ui-smoke.log`: final 86 checks, UI before/after and exact binary hash.
- `dynamic-release/acceptance/results.json`: prior 207 backend checks.
- `dynamic-release/g1/`: generator/hash verification, native, GDScript,
  .NET build and C# logs.
- `dynamic-release/HeadlessTest.log`, `ChaosPendulumTest.log`,
  `VisualDebugTest.log`, `main.log`: original MjWorld regressions.

## Independent gate still required

There is no desktop display in this executor. Headless scene/UI tests do not
prove actual rendered appearance and are not screenshot acceptance. Dot must
pull the final development commit independently, build/test it, launch the
[visual scene](../tests/dynamic_scene/README.md), and capture the required
before/after real G1-and-obstacle images plus repeated add/delete behavior.
Do not merge this milestone into main before that gate. No walking, full editor
plugin, Area3D, CharacterBody3D, full native-joint or Windows work is claimed.
