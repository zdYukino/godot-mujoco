Independent feasibility experiment, not native Godot HingeJoint3D implementation.
Source: probe.cpp. Reproduce: bash /tmp/mj316-two-connect-hinge/run.sh.
Official installed MuJoCo public API 3.16.0 only; no internal headers.
Two connect equalities join z-axis sites at +/- spacing/2. Both connect constraints
use solref=.02 1 and default solimp. Gravity/contact disabled. A 1 kg sphere of
radius .2 has inertia .016 kg m^2. dt=.001, implicitfast, solver iterations100,
tolerance1e-12, duration1s. Torque .01 Nm on A, -.01 on B when B is free.
Spacing .1 and 1. Each topology run for axial z and transverse x torque.
Results/logs: run.log, results.json; build.log and executions.tsv record exit0.

Findings: axial omega matches torque/inertia: .625 rad/s body->world, 1.25 rad/s
relative for two bodies. Transverse rotation settles with near-zero omega,
but finite soft-constraint tilt. Changing spacing .1 to 1 reduces tilt by ~100x
and linear anchor error by ~10x. Therefore the arbitrary site spacing materially
changes passive hinge compliance. nefc=6 for two point constraints: redundant
constraint rows, not a minimal rank-5 hard revolute joint.

Not validated: Godot frame axis mapping/lifecycle/rebuild, unequal masses,
non-spherical inertias, collision loads, long-duration stability, large torques,
solver/timestep variations, motor, limit, bias/damping parameter mapping.
Do not advertise this as a complete HingeJoint3D or parameter-equivalent solver.
