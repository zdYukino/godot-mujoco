# Rotated sweep ABI precision regression

Run `bash tests/native_sweep_precision/run.sh` after the Linux source build.
24 rotations × 3 margins × single/multiple targets × sphere/capsule queries:
864 assertions per process, repeated three times. The first sphere case is the
parent verifier's exact ordinary rotated box reproducer. Analytic face TOI and
actual Godot float poses are checked independently. No warnings are accepted.
See `docs/evidence/sweep-float-certification` for before/after evidence and limits.
