# Dynamic scene camera and selection correction

Follow-up to `46f550b82bcedf312ce8852cec67f93721f29a2b` on the same
`codex/dynamic-g1-world` branch. Dot's independent rendering found a roughly
70-pixel robot and excessive illumination, plus stale elbow slider state after
selection/deletion. This change is confined to the visual scene and documentation.
No C++ physics, model placement, original asset, dependency or main-branch change.

## Changes

- Fit actual MeshInstance3D world bounds, excluding the floor, with a 45-degree
  camera and space reserved for the control panel. Newly added objects are
  framed together; F focuses the selected object and A frames all.
- Wheel zoom and right-drag orbit, bounded pitch and distance, responsive
  framing and a vertically scrollable control panel.
- Lower directional/ambient intensity, darker matte robot material and reduced
  specular reflection. Geometry and transforms still come from actual physics.
- Read the selected model's actual elbow control on selection/add/delete and
  after target changes. Selection uses `set_value_no_signal`, so browsing does
  not command the robot. Empty/non-robot selections disable/reset the slider
  and show an explicit label. Continuous slider values avoid display rounding
  introduced by the old 0.01 step.

## Verification

`OUT=/workspace/shared/validation/camera-release tests/dynamic_scene/run.sh`
passed (exit 0): all **86 dynamic checks**, fresh import and the expanded UI
smoke. The UI regression covers the reported 1.08-rad stale-value sequence,
switching between robots, deletion, new instances, obstacle selection and empty
selection. It also sends wheel/right-drag events to the camera input handler
and compares the robot's complete state before/after camera manipulation.

At 1180 x 800, projected geometry bounding-box heights were:

| View | Height |
| --- | --- |
| Robot and elevated obstacle together | 309.12 px |
| Focus selected G1 | 697.15 px |
| One zoom-in step | 846.85 px (intentional close-up) |

The camera test also confirms a finite orbit transform and unchanged physics
state. Existing UI lifecycle counts remain 1 → 3 → 1, matching display objects.

The extension SHA-256 remains exactly the independently tested parent binary:
`0f143acf90e8f973669864d256dcb820e3b82d2b3414fb13f3987523a5a2ec2a`.
The prior 207-backend/MjWorld/G1 results were not relabeled as new runs; this UI
change reran the affected dynamic/GUI suite against that unchanged binary.

Real OpenGL Compatibility rendering was also exercised using a workspace-local
Xvfb display and Mesa llvmpipe. Actual viewport images are retained under
`/workspace/shared/validation/camera-release/screenshots`; these are rendered
physics geometry, not illustrations or relocated bodies. The headless report
is `camera-release/results.json`, with `import.log`, `runtime.log` and
`ui-smoke.log` beside it. Render output is in `camera-release-render.log`.
The rendered process exited 0. The display-less host reported unsupported
VSync and an unavailable ALSA device before falling back to dummy audio;
there were no scene script errors. These host diagnostics are retained in the
render log, separate from the error-free automated headless suite.

Dot must still independently pull the new final commit, run the real desktop
scene, inspect zoom/orbit/focus and target synchronization, and take its own
before/after screenshots. Cloud rendering evidence does not waive that gate.
