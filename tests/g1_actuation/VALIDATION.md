# Fresh reconstruction validation

Validated on 2026-10-17 UTC, Linux x86_64, MuJoCo 3.16.0, Godot 4.7.2.stable.mono.official.ed1daf0bf and .NET SDK 8.0.426. This reports a newly reconstructed snapshot, not byte identity with an unavailable historical commit.

Final full-run command:

```sh
source /workspace/shared/tools/env.sh
MUJOCO_ROOT=/workspace/shared/builds/godot-mujoco-3.16/_deps/mujoco-src \
GODOT=/workspace/shared/tools/bin/godot \
OUT=/workspace/shared/test-results/g1-restored-final \
  tests/g1_actuation/run.sh
```

All stages exited 0:

- 36 original source blobs verified against recorded hashes; their Git blob SHA-1 identities independently matched the pinned upstream GitHub tree at recovery time.
- Freshly regenerated fixtures compared byte-for-byte against saved derived artifacts.
- Source load from `/tmp`: nq=29, nv=29, njnt=29, nu=0, nbody=30, ngeom=69, nmesh=34.
- Native: 59 trials / 236,000 steps; maximum final error 7.15282506161e-6 rad, non-target final error 1.3378032573e-6 rad, non-target transient excursion 0.0010321753919 rad. All 58 force-saturation checks passed.
- GDScript: 60 trials / 240,000 steps; maximum final error 7.20425421500345e-6 rad.
- C#: 60 trials / 240,000 steps; maximum final error 7.204254215003453e-6 rad. Build: zero warnings and zero errors.
- Binding tests explicitly checked runtime version 3.16.0. Both include a second, reversed combined-control trial beyond the native suite's one combined trial.
- A fresh isolated project/cache was used, with `scripts/import_headless.sh`'s frame-delay workaround; no existing demo import cache was reused.

Separately, the unchanged original URDF was confirmed to fail MuJoCo loading with `Error opening file 'meshes/meshes/pelvis_ver0529.STL'`. This is why the derived URDF adds only `strippath="true"`.

Coverage remains synthetic bounded actuation and binding behavior. No walking, balancing, contacts, GUI, non-Linux platform, hardware or vendor-policy validation is claimed.
