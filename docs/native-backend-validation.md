# Linux native backend cloud validation — 2026-10-17

Status: cloud headless validation passed; dot's independent pull, runtime and
rendered acceptance remain outstanding. Do not merge this branch into main.
CharacterBody3D, Area3D, complete joints and non-Linux platforms are outside this work.

## Verified inputs

- Baseline/main: `88eb9ef7421b2aeca584bfcecac3ac9afa969a4b`, tree
  `f405ce8a89037e5a8cf006e17dd9833fbf1639c9` (also checked through GitHub MCP).
- Draft: `8c0757753bba7820a345077d9c94b17ed775fd42`, tree
  `4ccb2760289f6d320c456085b20537de4432ed78`. Downloaded with GitHub MCP;
  the reconstructed local Git tree matched exactly before editing.
- Linux x86_64; Godot `4.7.2.stable.mono.official.ed1daf0bf`;
  MuJoCo runtime `3.16.0`; .NET SDK `8.0.426`, runtime `8.0.32`;
  CMake `4.4.4`; GCC/G++ `14.2.0`; godot-cpp `godot-4.5-stable`.
- The baseline commit's `3.1.6` subject is a typo. No dependency was downgraded.
- Inherited tools, dependency sources and caches were present. The shell did
  not automatically load `/workspace/shared/tools/env.sh`; every run sourced it.
- All 36 original Unitree files matched both SHA-256 and Git blob hashes before
  and after testing. No model asset was edited.

## Diagnoses and fixes

1. **First physics-frame SIGSEGV (139): C++ symbol interposition.** With the
   draft's static libgcc/libstdc++ link flags, GDB stopped in
   `read_utf8_code_point -> codecvt::do_length -> ostream::_M_insert<double>`
   from `vector_xml`, called by `rebuild` during the body's inertia/state
   synchronization. Identical compiled objects linked dynamically completed
   execution (43/44 checks), and a static link exporting only the GDExtension
   entry point also completed. Linux builds now use a linker version script
   to keep the static C++ runtime and godot-cpp symbols private. This retains
   static runtime packaging and `$ORIGIN` linkage to MuJoCo.
2. **Cold import SIGSEGV: unowned direct state.** GDB separately stopped at
   `MjDirectBodyState::_get_step`, dereferencing its null `server`, during
   editor property/documentation probing. Direct states and the server are
   now registered abstract: C++ factories still construct them, but ClassDB
   and editor documentation cannot instantiate unowned objects. This is a
   concrete additional failure, not evidence that the historical baseline
   timing race has been universally fixed.
3. **Ray collider identity.** Native result structs cross the extension ABI
   without automatic object conversion. `collider` now contains the engine
   object's `_owner`, not the godot-cpp wrapper address. The original object
   identity check now passes, alongside RID and instance ID checks.

ASan attempts were not usable evidence: .NET's `RTLD_DEEPBIND` loading and
exception interception aborted those diagnostic runs (134). Plain GDB and
same-object link comparisons established the diagnoses above.

## Results

The untouched baseline was first built from a Git archive in a separate source
and build directory (full build 354.45 seconds, exit 0). Core smoke, fresh helper
import, HeadlessTest, ChaosPendulumTest, VisualDebugTest and the 120-frame main
scene all exited 0. Native G1 and GDScript passed; the first C# build exited 1
because its NuGet mutex needed a write to the sandbox-protected directory
`/home/agent/.dotnet/corefx/Runtime/SharedMemory`. A scoped write grant for that
directory allowed the SDK to run. A new isolated full G1 run then exited 0.
The failed attempt is retained, not counted as a pass.

Final fixed-backend validation (all commands exited 0):

| Check | Result |
| --- | --- |
| CMake configure/build and standalone core smoke | Pass |
| Fresh native acceptance import | Pass |
| Original acceptance | 44/44, three separate processes |
| Additional sphere/plane/filtering/ownership checks | 25/25, three separate processes |
| Aggregate | 207/207, no engine/script errors |
| Resting one-meter box center | Y = 0.499892354 m; effectively zero velocity |
| Fresh MjWorld import; three test scenes; main 120 frames | Pass |
| G1 native | 59 trials, 236,000 steps, 58 saturation checks |
| G1 GDScript and C# | 60 trials and 240,000 steps each |
| G1 maximum final error | native 7.152825e-6 rad; bindings 7.204254e-6 rad |
| Original Unitree assets | All 36 hashes unchanged |

Two complete fixed-backend acceptance runs passed with the same extension SHA-256:
`4cfae4767f713795294e798f89625c9a199b57e7529ed7f7ebd3a0e14f1d940f`.
`nm -D --defined-only` shows only `godot_mujoco_library_init`;
`readelf`/`ldd` confirm `libmujoco.so.3.16.0` and `$ORIGIN`.
The GodotPhysics3D negative control exits 1 with 42 behavior checks passing and
exactly the two backend identity checks failing.

G1 remains fixed-base, zero-gravity, contact-disabled bounded joint actuation.
These results establish neither walking nor balance nor rendered GUI behavior.

## Reproduce independently

Use a new checkout and fresh build/output directories. The normal CMake path
fetches the pinned dependencies; this cloud run reused the verified local
MuJoCo and godot-cpp sources. Its final build reused only the baseline's compiled
godot-cpp dependency, rebuilding every extension translation unit separately.

```bash
source /workspace/shared/tools/env.sh  # environment-specific; or set tool paths
cmake -S . -B /tmp/gmj-native-build \
  -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
  -DMUJOCO_VERSION=3.16.0 -DGMJ_BUILD_CORE_SMOKE=ON
cmake --build /tmp/gmj-native-build -j 8
/tmp/gmj-native-build/gmj_core_smoke
OUT=/tmp/gmj-native-acceptance tests/native_backend/run.sh
MUJOCO_ROOT=/tmp/gmj-native-build/_deps/mujoco-src \
  GODOT="$GODOT_BIN" OUT=/tmp/gmj-g1 tests/g1_actuation/run.sh
# Also run the fresh-import and four MjWorld commands in headless-baseline.md.
```

Do not reuse an output directory or treat a crash followed by a cached rerun as
a successful cold import. The native runner now rejects existing project output
and bounds import at 120 seconds. Keep the existing timing workaround until an
engine-level resolution of the historical race is established.

## Machine-local evidence

- `/workspace/shared/validation/handoff-20261017/results.json`: baseline command
  arrays, working directories, process codes, timing and individual log paths.
- `handoff-20261017/g1-complete.log` and `g1-complete/`: full successful baseline
  G1 rerun after the scoped permission grant; earlier failures remain alongside.
- `/workspace/shared/validation/native-debug/static-crash.json`: raw -11 / shell
  139 runtime reproduction; `gdb-static.log`: original runtime crash stack.
- `/workspace/shared/validation/native-fixed/gdb-import-symbols.log`: separate
  null-server import stack; `negative-control.json`: built-in physics control.
- `/workspace/shared/validation/native-final/run.py` and `results.json`: exact
  final commands, working directories, exit codes and logs.
- `native-final/acceptance/results.json`: all 207 checks and binary hash;
  `native-final/g1/`: native, GDScript, build and C# logs.

No other branch was merged or overwritten. The initial `/workspace/godot-mujoco`
checkout remains clean on its original baseline; changes live in the separate
`/workspace/native-backend` directory and the development branch.
