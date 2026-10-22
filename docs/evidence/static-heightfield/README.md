# P2 static-heightfield evidence

Depends on P1 `47cb7299b33ad36284ea2bec122f20dd5fe3837f` on
`codex/typed-control-heightfield`, itself based on strict-smoke `5cf7c45`.
No main merge; PR #1 remains separate. Linux x86_64 only.

Built native extension from these changed sources against fixed MuJoCo 3.16.0:
`source /workspace/shared/tools/env.sh` then
`cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2` (exit 0).
Final binary SHA256: `d43e4fbb49b680f3ec7c5aca501e5c34ee9de6afb27587d8b86298f3fad5a1b9`.
This is an incremental extension build; it is not a new ABI/distribution claim.
The first invocation without the tool PATH exited 127; invocation after sourcing
the existing environment succeeded. Subsequent builds compiled the changed source.

| Executed command (after sourcing env) | Result |
| --- | --- |
| `OUT=/workspace/shared/validation/heightfield-final bash tests/heightfield/run.sh` | exit 0; 60 assertions |
| `OUT=/workspace/shared/validation/p2-native REPEAT=1 bash tests/native_backend/run.sh` | exit 0; 149 assertions |
| `OUT=/workspace/shared/validation/p2-editor bash tests/editor_plugin/run.sh` | exit 0; 160 assertions |
| `OUT=/workspace/shared/validation/p2-clock bash tests/runtime_clock/run.sh` | exit 0; 118 assertions plus C# clock binding |
| `OUT=/workspace/shared/validation/typed-control-p2 bash tests/typed_control/run.sh` | exit 0; 61 assertions |
| fixed Godot `--headless --path .../heightfield-04/project res://HeightfieldDemo.tscn --quit-after 120` | exit 0; startup only, not GUI acceptance |
| `git diff --check`, `bash -n tests/heightfield/run.sh` | exit 0 |

Every listed integration log was rescanned for ERROR and leak strings: none.
Full projects/logs remain at the listed workspace paths. Native regression ran
before the final cancellation cleanup guard, so its report records the earlier
binary hash; final heightfield, editor and clock checks ran after that change.
No G1, multi-G1, migration stress, remote CI, packaging or Windows tests executed.

Heightfield coverage: actual box/slide-model contact; collision identity, mask,
inside-origin and rotated/translated ray results; non-coplanar visible triangle
agreement; pending/duplicate/revision semantics; invalid data/pose/resolution
rejection; snapshot isolation from subsequent design changes; paused state
continuity for two models and ordinary body; running-state restoration; repeated
remove/add; saved design/scene reopen; queued-deletion cleanup and successful
but unobserved request cancellation.

Earlier runs: heightfield-01 passed 47; -02 failed one exact float-comparison
assertion for translated visual position, then fixed to approximate comparison;
-03 passed 55; -04 passed 58. Their original logs are preserved, not relabelled.

Actual editor GUI acceptance awaits dot following `docs/static-heightfield.md`.
Invalid-input rollback is tested; forced compiler/allocation failure injection is
not. Cold import 139 remains independently unresolved; successful imports here
use the existing frame-delay helper and are not proof of a stable cold baseline.
