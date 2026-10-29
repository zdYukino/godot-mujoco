# Author resources and relocation

MJCF import accepts XML only. It expands includes and copies hashed dependencies and source archives into the project. `MjAuthorResource` stores the full author tree, stable identities, initial joint/control values and Godot mesh-depth metadata; body/joint/geom nodes are persistent scene nodes.

Save scenes with Ctrl+S. Scripts can use `author_builder.gd` (`import_file`, `save_document`) and `scene_builder.gd`. Current author resources may be saved as `.tres`; the import dialog does not accept resource files. Legacy packages, converters and upgrade actions have been removed.

`MjRuntimeWorld.world_design` owns global options and each `MjModelInstance.design` owns its author data. Six collision settings inherit from the world; other option conflicts remain errors. Instances and ordinary Godot physics objects share one space with independent state and real contacts.

Copy the whole project, addon runtime libraries and `mujoco_models/` when relocating. Original source paths are provenance only. Dependency checks detect missing/changed/untracked assets, directory redirects and unexpanded includes. `MjEnvironmentHost` waits for a candidate in a separate World3D to compile before replacing the active environment.

Run `tests/portable_runtime/run_assets.sh` and `run_runtime.sh` for relocation, control, contact and lifecycle coverage. Filesystem projects are supported; PCK/ZIP dependency extraction is unverified. See the [authoring guide](node-authoring.zh-CN.md) and [collision settings](geom-collision.zh-CN.md).
