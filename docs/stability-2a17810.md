# Fixed-toolchain Linux stability gate

Target: `2a178101b9b72f9064f647291002da9d2f52913f`, tree
`cd9506478e9fb7fe651ccd7ac3de05d41225fd32`.

**Do not promote this commit as a stable baseline or merge it to main.** Official
cold import reproduced SIGSEGV in two independent fresh projects. Passing helper,
GUI or runtime samples cannot erase this failure or dot's independent failure.
No engine patch, replacement, timing workaround, or product change is included in
this test-only follow-up.

## Environment and reproducibility

- Godot `4.7.2.stable.mono.official.ed1daf0bf`, engine SHA256
  `fc1bd592b5e771c65d52968f99835b4f2b7fe7b7cbc141e202cb63e01c95ec4d`.
- MuJoCo runtime `3.16.0` (queried through `mj_versionString`), SDK `8.0.426`.
- Extension SHA256
  `c6aedb8bf549e6a82819d0ee2bfdbbbf41db08008feb0f4c787147eae9b33dcf`.
- Linux x86_64; allowed CPUs 0–4. Tests use nice 10, at most two processes,
  CPU sets 0–1 and 2–3. Xvfb supplies the real OpenGL editor display.
- Frozen source contains 189 tracked files. All match the tested tree; all
  36 original Unitree manifest entries retain their SHA256 bytes.
- Every cold import starts without `.godot`, with a fresh project and private
  XDG data/config/cache directories. SDK/NuGet installations are shared.
- Runtime pressure intentionally follows a successful fixture import; it is
  not counted as another cold-import success.

Entry points (after sourcing the fixed toolchain environment):

```bash
python3 tests/stability/cold_matrix.py --source FROZEN_SOURCE --out EVIDENCE/cold
python3 tests/stability/lifecycle_matrix.py --source FROZEN_SOURCE --out EVIDENCE/lifecycle
```

`EVIDENCE/frozen-manifest.json` records source and binary hashes. Individual
`command.json`, `result.json`, `commands.json` and `trial.json` record exact paths,
commands, exit codes and durations. The real editor requires Xvfb at `:97`.

## Cold-import outcome

| Mode | Planned | Executed | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: | ---: |
| Official native CLI | 3 | 2 | 0 | 2 (139) | 1 |
| Existing helper, sequential | 20 | 20 | 20 | 0 | 0 |
| Existing helper, bounded pairs | 10 | 10 | 10 | 0 | 0 |

The official command is `godot --headless --editor --path PROJECT --import`.
The two failures took 5.428 and 4.380 seconds. The third was stopped according to
the predeclared rule after reproducing the known blocker. The existing helper
still uses its previously committed frame delay; these successful samples do
not establish an engine-level completion barrier.

Earlier same-binary watchpoint evidence in `docs/portable-edge-fixes.md` traces
editor documentation cleanup followed by a queued callback dereferencing the
cleared document pointer. This matrix establishes reproducibility; it does not
claim a new symbolic root-cause diagnosis for every individual crash.

## GUI and migration outcomes

Five fresh real-renderer editor projects each passed 116 checks and exited 0
(580 assertions). Each had its own successful helper import. V-Sync capability
warnings and the Vulkan surface probe/fallback diagnostics are recorded in
`gui-diagnostics.json`; they are host-renderer diagnostics, not suppressed
script or extension failures. No script errors or leaked-instance messages were
found. This exercises plugin enable/disable, document recovery and editor shutdown;
it is not an assertion of headless-import reliability.

Three asset runners exited 0. Three full runtime runners each passed the original
30 checks, the relocated 30 checks and 47 recovery/integrity checks (321 total),
then exited 1 at `dotnet build`: fresh private XDG data caused NuGet's
`NuGet-Migrations` named-mutex initialization to fail (`MSB4242`). Thus **0/3 full
fresh-environment runners passed**; C# and subsequent editor phases were blocked
in those original runs. These failures remain in the evidence.

Separate post-import follow-ups use the existing configured SDK XDG environment
and are explicitly labeled. They do not rerun cold import or alter its results.

Three separately labeled pressure processes exited 0 with 361 passing assertions
each (1,083 total), but **all three failed the error-free pressure gate**:
90 missing-asset recovery / insertion-removal cycles and 30 same-node world
reentries. Existing model joints and controls survived topology changes, deleted
RIDs became invalid, and no MuJoCo warning or leaked-instance messages appeared.
However, each log contains `MuJoCo minimal backend requires unscaled rigid
transforms; set shape dimensions instead` during `root.add_child(world)` on world
reentry. An independent diagnostic rerun measured obstacle scale
`(0.999998, 1.000011, 1.000003)` and determinant `1.00001263618469`
at cycle 29 immediately before the rejection (exit 0). This confirms drift into
the scale-rejection boundary; the proposed readback fix has not been applied.
The assertion count alone missed this native error; the final log audit
caught it. Do not report these pressure runs as clean passes.

Separately, all three configured-SDK builds and C# runs exited 0; each portable
editor follow-up passed 9 checks and its saved-scene restart exited 0. These
follow-ups do not erase the original fresh-XDG failures.
This does not represent walking validation.

## Remaining decision

Keep main unchanged. Treat the pressure diagnostic independently of the cold
import engine race. Next project-side work should inspect rigid-body transform
readback (`read_body` preserves and reapplies the previous basis scale), remove
unintended numerical scale accumulation without accepting authored scaling, and
rerun this pressure test plus native shape/transform and body lifecycle regressions.
The diagnostic follow-up records the obstacle scale and determinant before each
world reentry; it does not modify the target binary. Prepare an independently
initialized writable SDK data directory before repeating the full fresh-environment
.NET runner; preserve this run's initialization failures.

The documented filesystem/import signals do not cover the
queued documentation work. A supported engine fix or an explicitly approved
engine-version/patch exception needs separate evaluation and a new cold matrix.
A same-version engine patch would still change the official binary and requires
explicit user approval; waiting for an official fix is the other path. No such
exception is approved here. dot retains independent final acceptance;
GUI success cannot substitute for headless-import stability.

The parent reports a separate dot sample of 8 cold imports: native 4/4 failed,
helper 3/4 failed; sequential 4/4 and bounded-parallel 3/4 failed. Those are
parent-reported cross-checks, not cloud-executed results. Identical log hashes
across different exits reinforce why a final log line is not a success signal.
