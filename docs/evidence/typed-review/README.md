# Follow-up review fixes on f25defd4

Changes: typed binding follows Script.GetBaseScript() while retaining main-thread,
live-node, configured-world, loaded-instance and kind checks. Tests exercise a
two-level inherited world, inherited instance, base instance, out-of-tree and
unrelated/wrong-kind rejection. The existing unload/delete/reentry checks now also
exercise inherited nodes. No native source changes or heavy models in this fix.

Confirmed revision defect before fixing it: disable the instance's idle processing,
queue a valid mass edit, and let native physics commit. Native property_revision
becomes 1 while node property_revision stays 0. The old typed Read reports new body
mass with old revision, and fails the dedicated consistency assertion. The genuine
failed runtime log is retained separately in negative/revision-repro.log; this is
not a positive run. Typed Read now gets revision from the same native dictionary as
its bodies/joints. Request.Finished stays pending until the node polls its result.

Executed on Linux x86_64 with the fixed Godot 4.7.2 .NET / MuJoCo 3.16.0 environment:

| Command (after sourcing /workspace/shared/tools/env.sh) | Outcome |
| --- | --- |
| `OUT=/workspace/shared/validation/typed-review-final bash tests/typed_control/run.sh` | exit 0; 69 checks; C# build zero warnings/errors |
| `OUT=/workspace/shared/validation/heightfield-ray-01 bash tests/heightfield/run.sh` | exit 0; 65 checks |
| `OUT=/workspace/shared/validation/native-review-final REPEAT=1 bash tests/native_backend/run.sh` | exit 0; 149 checks / 3 processes |
| `git diff --check`, `bash -n tests/typed_control/run.sh` | exit 0 |

All positive logs rescanned for ERROR/leak: clean. Full logs and disposable projects
remain in the listed workspace directories. Native regression now uses the final
P2 cancellation-guard binary, SHA256
`d43e4fbb49b680f3ec7c5aca501e5c34ee9de6afb27587d8b86298f3fad5a1b9`.

The first inheritance run reached the old box-motion assertion too early: two
render frames did not guarantee a physics synchronization tick. The test now waits
up to five physics frames for box node motion; no physics implementation changed.
Its original failed log is retained at typed-inheritance-01/runtime.log.

Dedicated terrain assertions now cover excluded RID, clearing exclusion, front
face with back faces disabled/enabled, and an outward ray starting exactly on the
surface (t=0), rejected when back faces are disabled and accepted when enabled.
This closes a coverage gap; the previous evidence report did not claim these
assertions existed. README now distinguishes dedicated static terrain from general
HeightMapShape3D and introduces the typed API in its main C# section while retaining
dynamic Call/Get compatibility.

GUI acceptance remains separate (dot). No new native build required for this fix.
No forced candidate compiler/allocation failure injection, G1/stress, packaging,
remote CI or main merge. Invalid-input rejection is not evidence of compiler-failure
rollback. Cold import 139 remains unresolved; no cached retry is presented as fresh.
