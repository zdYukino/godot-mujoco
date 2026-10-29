# Runtime authoring

The local editor scene is the design source. Editing it during F5 pauses physics, validates the model and compiles the combined world in isolated workers, then submits an MJB at the physics boundary. Successful edits stay paused until manually resumed. Failure, cancellation or timeout preserves the draft and the last valid preview/world, and blocks stale resume.

Stable identities preserve compatible state across renames and reset subtrees whose coordinates change. Compilation contexts include world collision settings and budgets; obsolete results cannot overwrite newer edits.

Game design buttons call `world.request_editor_design(command)`; standalone requests return 0. The old resource replacement APIs and debugger protocol have been removed. Runtime control remains available through `instance.set_control` and atomic [control presets](runtime-presets.zh-CN.md).

Reset retains committed design and topology. Environment rebuild restores the saved scene after a candidate compiles in a separate World3D. Saving design never silently captures fallen simulation poses as authored initial state.
