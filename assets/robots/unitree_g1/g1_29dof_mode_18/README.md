# Unitree G1: pinned source and bounded synthetic test fixture

Source: [unitreerobotics/unitree_ros](https://github.com/unitreerobotics/unitree_ros/tree/5994d4faef0a9cadd3287f8de0199a67eeb2a259/robots/g1_description), commit `5994d4faef0a9cadd3287f8de0199a67eeb2a259`.

`g1_29dof_mode_18.urdf`, 34 referenced files in `meshes/`, and repository-root `LICENSE` are byte-exact upstream copies. The license is BSD-3-Clause. `upstream-manifest.json` records upstream paths, byte counts, SHA-256, and Git blob SHA-1; all 36 blobs were checked against the pinned GitHub tree. URDF CRLF line endings are intentionally preserved.

## What this model contains

The source has 38 links, 29 revolute and 8 fixed joints. Its floating-base joint is commented out, so it is fixed-base. It contains no actuators or control policy. See `joint-inventory.json` for exact source limits, effort and velocity values.

MuJoCo **3.16.0** defaults to `strippath=false`. The upstream combination `meshdir="meshes"` and mesh filenames `meshes/...` therefore looks for `meshes/meshes/...` and fails. `g1_29dof_mode_18.mujoco316.urdf` changes only the compiler tag by adding `strippath="true"`; the original is unchanged. Loading the derived file by absolute path from `/tmp` yields nq=29, nv=29, njnt=29, nu=0, nbody=30, ngeom=69, nmesh=34. URDF effort limits map to joint actuator-force limits; URDF velocity limits are not enforced by MuJoCo.

## Synthetic fixture, not a robot controller

`actuation-test.xml` is generated from MuJoCo's `mj_saveLastXML` output. Exact original joint ranges are restored because the canonical XML writer rounds them. It adds 29 named, unit-gear position actuators (kp=10, kv=5), each with the original joint control range and effort force cap. Gravity and contacts are disabled, timestep is 0.001 s, and integration is `implicitfast`.

This fixture only validates bounded joint actuation, mapping and bindings. It is **not** walking, balance, free-base dynamics, contact physics, GUI validation, or a claim that Unitree supplies these actuators/gains. The original model and meshes are never modified to make the tests pass.

Reproduce with `tests/g1_actuation/run.sh`; generated files are produced in a fresh output directory and compared with these saved fixtures before tests run. This is a newly reconstructed and verified snapshot, not proof of identity with a lost historical commit.
