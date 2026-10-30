# Third-party components bundled with this addon

This addon builds on and redistributes the following components. Their licenses
apply to the bundled binaries.

## MuJoCo
- Upstream: https://github.com/google-deepmind/mujoco
- License: Apache License 2.0
- Redistributed as the prebuilt runtime bundled next to the extension
  (`libmujoco.*` / `mujoco.dll`), fetched at build time.
- MuJoCo 3.16 simulate interaction, history, diagnostic formulas and shortcut
  defaults are adapted in `src/viewer/` and `addons/godot_mujoco/viewer/`.
  Source/version notes and the Apache-2.0 license are in `src/viewer/UPSTREAM.md`
  and `src/viewer/LICENSE-MUJOCO`. The adapter uses Godot UI and the linked mjv_*
  APIs; it does not embed simulate's GLFW or simulation loop.
  An addon-local copy of the license is bundled as `viewer/LICENSE-MUJOCO`.

## godot-cpp
- Upstream: https://github.com/godotengine/godot-cpp
- License: MIT
- Statically linked into the GDExtension library.

See each project's repository for full license texts. This addon itself is
distributed under the MIT license (see the repository `LICENSE`).
