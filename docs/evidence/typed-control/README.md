# P1 typed control evidence

Base: `5cf7c45a4e7cf71083fd45612f02e9d27b124398` (depends on the separate
Linux strict-smoke branch / draft PR #1; not merged into main).
Feature branch: `codex/typed-control-heightfield`.

Linux x86_64, official Godot 4.7.2 .NET, MuJoCo 3.16.0. Existing native addon
binary used; P1 changes no C++ source and does not claim a new native build.
Command: `source /workspace/shared/tools/env.sh` then
`OUT=/workspace/shared/validation/typed-control-final bash tests/typed_control/run.sh`.
Exit 0; import, fixture generation, C# build and runtime each exit 0; 57 checks,
zero failures, no ERROR/leak. Logs here are the final run. Full disposable project
and import/prepare logs are in that OUT directory on the development workspace.

Earlier failed attempts are retained in `typed-control-01` through `-04`:
01 C# Environment name ambiguity (fixed); 02 box node not yet synchronized
(test waits two frames); 03/04 reopening into a persistent World3D retained its
clock (test now frees/recreates an isolated World3D). These are not passes.
05 passed 56 checks; 06 passed 57 after adding worker-thread rejection.
Final run also exercises the final exit-code recording runner.

Tests cover two hinge controls, typed state, pause/resume, exact steps, duplicate
request rejection, queued-but-failed command, snapshot reset, revision success and
stale failure, compatible state continuity, deletion during pending request,
unload/reload and same-node exit/reentry invalidation, independent surviving
instance, ordinary box motion, and saved design reopened in a new World3D.
GUI acceptance, G1/stress, cold-import stability and Windows are not claimed.
