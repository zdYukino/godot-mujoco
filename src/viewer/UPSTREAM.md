# MuJoCo runtime viewer adaptation

Upstream: google-deepmind/mujoco, release 3.16.0, `simulate/simulate.cc`,
`simulate/simulate.h`, and `simulate/platform_ui_adapter.cc`.
License: Apache-2.0 (LICENSE-MUJOCO in this directory).

Adaptations: Godot input/UI and plots, queued authoritative physics commands,
versioned frozen CPU scenes, renderer adapters, bounded history, read-only design
inspection, and user:// outputs. No GLFW event loop or second simulation loop.
Camera, selection and perturbation use the linked public mjv_* implementation.
The history/sensor/profiler formulas and shortcut defaults follow that release.
Input coordinate conversion follows the pinned
[platform adapter](https://github.com/google-deepmind/mujoco/blob/3.16.0/simulate/platform_ui_adapter.cc)
and [simulate event handler](https://github.com/google-deepmind/mujoco/blob/3.16.0/simulate/simulate.cc).

Godot diagnostic primitive dimensions/placement adapt the same release's
[classic renderer](https://github.com/google-deepmind/mujoco/blob/3.16.0/src/render/classic/render_gl3.c)
and [visualization construction](https://github.com/google-deepmind/mujoco/blob/3.16.0/src/engine/engine_vis_visualize.c).
Godot supplies its own meshes/materials; pixel line widths follow Godot's renderer.

The Godot UI adapter in `simulate_ui.gd`, `simulate_radio.gd` and
`shortcut_hints.gd` adapts the fixed release's section/control definitions,
radio/folding/shortcut hints, spacing and color organization. Original sidebars
and F1–F4 overlays remain separate from the F11 Godot extras window.
Control noise adapts `Simulate::InjectNoise`; solver workers directly call
`mju_threadpool`. Widget drawing stays in Godot so native GL OFF is supported.
The original and both backend screenshots are reviewed separately; pixel-identical
`mjui_render` drawing is not claimed.
