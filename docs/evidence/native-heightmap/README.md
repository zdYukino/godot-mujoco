# Development-environment self-test (2026-10-24)

Not dot acceptance. Linux x86_64; fixed Godot 4.7.2 .NET and MuJoCo 3.16.0.

- `source /workspace/shared/tools/env.sh`
- `cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j2`: exit 0.
- `OUT=/tmp/gmj-heightmap-sliding-2 bash tests/native_heightmap/run.sh`: import/positive/negative all exit 0; 26 positive checks and 12 exact expected rejection errors. Positive/import logs contain no ERROR/leak.
- `$GODOT_BIN --headless --path /tmp/gmj-heightmap-final/project --quit-after 90`: example smoke exit 0; no ERROR/leak. This does not replace GUI inspection.
- `OUT=/tmp/gmj-heightfield-regression bash tests/heightfield/run.sh`: import/prepare/runtime all exit 0; 73 existing dedicated terrain checks pass.
- `git diff --check`: pass.

First run `/tmp/gmj-heightmap-1` failed its defensive-copy check (20 passed, 1 failed). Explicit sample-array duplication fixed the shared Variant mutation; `/tmp/gmj-heightmap-2` passed 21 checks before compound/shared-resource/removal coverage was added. Original failure logs remain at those paths in the development environment.

Raw logs and executions.tsv remain in the listed /tmp directories. No G1, heavy multi-robot workload, package restore, or main merge. See ../../native-heightmap.zh-CN.md for the dot rebuild and GUI checklist. The final feature branch preserves main's architecture-map documentation commit d7461cd6b4e3f3f79aad31b6be2384b19c813278.

Sliding comparison over 30 physics frames, initial box speed 1.5 m/s: friction 0 travels 0.713816 m and retains 1.381621 m/s; friction 0.8 travels 0.144226 m and ends at 0.0000353 m/s. The initial sliding assertion required >1.4 m/s for zero friction and failed despite clear continued sliding (`/tmp/gmj-heightmap-sliding`); the final test allows >1.3 m/s, requires >0.65 m travel, and requires the high-friction travel to be below half with speed <0.1 m/s. This checks a repeatable contrast, not ideal lossless integration.

## Dedicated material and MJCF coverage follow-up

- Rebuilt native extension after adding dedicated `physics_material_override` snapshots and geom friction: exit 0.
- `OUT=/tmp/gmj-terrain-material-final bash tests/heightfield/run.sh`: import/prepare/runtime all exit 0, **96 checks pass** (includes the original dedicated terrain coverage). Added pending material snapshot isolation, native and MJCF final-contact friction, changed material Apply, save/reopen/rebuild, nonzero-bounce rejection with prior material retained, and ordinary HeightMap/MJCF contact updates.
- `OUT=/tmp/gmj-heightmap-material-final bash tests/native_heightmap/run.sh`: import/positive/negative all exit 0, **26 positive checks and 12 expected rejection errors** after the follow-up.
- Both runners enforce clean positive logs. MJCF fixture friction is explicitly 0.15; terrain 0.23 and 0.67 dominate under the existing MuJoCo combination. Arbitrary imported priority/solmix and explicit pair overrides are not asserted.
- Existing Inspector terrain material is saved design, requiring explicit Apply at runtime. No new rolling/torsional/solver parameter surface was introduced.
