# Rigid transform synchronization: remove accumulated scale

The previous `read_body` took scale from the previous Godot basis and reapplied
it to the next basis reconstructed from MuJoCo's quaternion. Although authored
scale is unsupported, each float basis contributes a small norm error. Feeding
that error back into every frame accumulated artificial scale. On the tenth
world reentry of the G1 pressure fixture, the ordinary obstacle reached scale
`(0.999998, 1.000011, 1.000003)` and was rejected by the existing rigid-transform
validator. This was a project defect independent of the engine cold-import race.

Readback now reconstructs a fresh rigid basis from a normalized quaternion and
does not inherit the previous basis scale. The write path explicitly normalizes
its quaternion after validating the incoming transform. Axis conversion remains
`(x,y,z) -> (x,-z,y)` and uses orthogonal conjugation for bases. Angular velocity
continues to convert between MuJoCo local free-joint coordinates and Godot world
coordinates using the resulting rigid basis.

The input validator and its tolerances are unchanged. Authored non-unit scale outside the existing numeric tolerance,
shear, reflection and non-finite transforms remain rejected; unsupported input
is not silently normalized into an accepted transform. Shape dimensions remain
the supported way to size geometry.

## Regression design and before/after evidence

`tests/native_backend/rotation_sync.gd` rotates an isotropic sphere for 2,400
frames, checks its analytical world-space orientation and angular velocity,
measures basis norms/orthogonality/determinant, and reenters the same world 20
times. It is part of each native runner repetition. The tolerance is `2e-6`,
stricter than the old drift that eventually tripped the production validator.

| Same regression | Previous binary | Fixed binary |
| --- | ---: | ---: |
| Process exit | 1 | 0 |
| Assertions | 20/80 failed | 80/80 passed |
| Maximum scale error | 8.16583633422852e-6 | 2.98023223876953e-7 |
| Maximum determinant error | 1.10864639282227e-5 | 5.96046447753906e-7 |

The G1 topology pressure test additionally checks the ordinary rigid body's
basis before every world reentry. All positive runtime logs must contain no
backend/script `ERROR` or leaked-instance message, independently of assertion
counts and process exit. Stability drivers now also return nonzero on recorded
failures; failure records are not merely advisory JSON output.

The fixed extension SHA256 is
`c92cd117e0151cbbb93eba8e4cb779fa398e43af9efda0ea27b614588a28d98a`.
Godot remains `4.7.2.stable.mono.official.ed1daf0bf` and MuJoCo remains `3.16.0`.
No engine patch, version replacement or main merge is included.

A separate deliberately failing invalid-input probe verifies that uniform and
nonuniform body scaling, shear, reflection, scaled shape insertion and scaled
shape updates still leave accepted state unchanged. It exits 1 and emits exactly
six rejection diagnostics; it is not counted as a clean positive regression.
No backend error is whitelisted in the pressure or rotation acceptance logs.

The shared pressure-log checker was replayed against the old exit-0/zero-failed-
assertion log containing a backend error: it exited 1. It exited 0 for the fixed
pressure log. Thus the old false-green case is covered independently of the new
numeric assertions.

## Validation scope

Tests run at nice 10 with at most two concurrent processes on CPU pairs 0–1 and
2–3. Every suite stages a fresh project; the configured SDK XDG environment is
used for .NET builds. This is not a claim that fresh private SDK initialization
or the unchanged official headless-import race has been fixed.

The earlier blocked baseline evidence remains in
[stability-2a17810.md](stability-2a17810.md). This change addresses the independent
project-side rigid-transform defect. Overall baseline promotion remains blocked
by cold import; main is unchanged and dot owns independent final acceptance.

| Fixed-binary regression | Result |
| --- | --- |
| Native, three repetitions including rotation sync | 447 assertions, exit 0 |
| Dynamic scene and UI smoke | 86 assertions plus UI smoke, exit 0 |
| Full portable runtime, three fresh projects | All stages exit 0, including C#, recovery and editor restart |
| Repeated G1 topology/recovery pressure | 3 × 371 assertions; 90 topology/recovery cycles, 30 world reentries; exits 0 and no backend errors |
| Asset packaging and relocation | Three runners exit 0 |
| Real-renderer GUI lifecycle | Five runners × 116 assertions; exits 0 |
| Original G1 native/GDScript/C# regression | All pass, exit 0 |
| Unitree original-byte integrity | 36/36 SHA256 entries unchanged |

GUI logs retain the known Xvfb V-Sync and Vulkan surface probe/fallback host
diagnostics; no script/backend error or resource leak was accepted. The portable
recovery suite retains its two exact, intentional GDScript ownership/configuration
rejections; it permits no additional error. The separate negative scale probe
is explicitly excluded from clean positive runs.

Evidence records exact commands/exits, source and binary hashes, old/new rotation
metrics, the old-error log replay, negative-input diagnostics and all suite logs.
Product source and binary remained unchanged throughout these regressions.
