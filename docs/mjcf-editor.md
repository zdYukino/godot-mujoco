> [中文使用指南](mjcf-editor.zh-CN.md) · [当前范围与验证](freebase-clock-validation.zh-CN.md)。本文保留原阶段的英文说明；版本和支持范围以当前入口为准。

# MuJoCo editor milestone

Development baseline: `ccaa10a1ff7e27428e00797dfcc612d2a2a632ae`.
Linux, Godot 4.7.2 .NET, MuJoCo 3.16.0, .NET SDK 8. Development branch
`codex/mjcf-editor`; main is not changed by this work.

Enable **MuJoCo Model Editor** in Project Settings → Plugins. Select the
**MuJoCo** main workspace tab. This is an actual EditorPlugin, not an F6 scene.
The addon requires the adjacent `godot_mujoco` GDExtension. No change to the
project's selected PhysicsServer is necessary.

## Architecture and editing contract

The editor owns an isolated native `MjEditorDocument` (mjSpec/model/data).
Existing runtime instance attachment replaces global MJCF options and assumes
one free root; therefore arbitrary MJCF must not be attached through the
G1-only importer. The preview preserves the imported model's global options.
The native backend and preview share named compatible state migration and the
same right-handed Godot/MuJoCo coordinate conversion. No editor-global physics
server is replaced or stepped manually.

Structural edits copy the spec, compile and forward a candidate, and replace
live ownership only on success. Compatible joint qpos/qvel/warmstart and named
controls survive. Invalid input/compile failure leaves the old model and state
in place. Explicit free-body pose editing intentionally resets that body's
pose to the new reference and clears its velocity. Preview simulation is local
and independent of the running game. Stop preview before structural Apply;
the UI pauses automatically and reports the state. Only explicit Apply compiles,
never individual keystrokes. Controls apply without compilation; scalar hinge/
slide qpos edits require pause. Preview steps are bounded on slow editor frames.

## Properties

- Body: local position (m), quaternion (wxyz), mass (kg) editable. Changing mass
  makes inertia explicit and scales the existing principal moments proportionally.
  Principal inertia (kg m²) is read-only. Mass belongs to bodies, not joints.
- Geometry: box half-extents, sphere radius, cylinder radius/half-height (m),
  local position/quaternion, density (kg/m³), friction triple, contact masks and
  margin editable. Explicit body inertia overrides geometry inference; density
  writes on those bodies are rejected with a diagnostic instead of silently
  pretending to change mass. Body mass remains editable.
- Joint: name/type, qpos, limits and units displayed; hinge/slide qpos editable.
  Ball/free joint arrays and limit definitions are read-only this milestone.
- Actuator: control, limits, transmission gear and gain/bias/dynamics types shown.
  Fixed-gain affine position-compatible drives expose kp and kv; velocity-compatible
  drives expose kv only. Other drives show N/A and reject PD edits. Classification
  describes the compiled force law, not the original XML shortcut spelling.
  Gains and controls are in actuator transmission units, not assumed joint units
  when gear/transmission changes. The full gain/bias definitions are preserved.

Box, sphere and cylinder create dynamic top-level bodies with a free joint and
actual MuJoCo geometry. Cylinder visuals use the same radius and full height.
Body/geometry deletion is transactional; dependency errors prevent deletion.

## Import, persistence and limitations

Import a filesystem MJCF XML with its original include/mesh directory intact.
MuJoCo expands includes; asset filenames are resolved on the in-memory copy.
The editor never writes imported XML, meshes or Unitree assets. Save an editor
`.gmj.json` document; it contains canonical MJCF plus full-precision simulation
state, source provenance and external absolute asset references. Reopening needs
those asset files to remain available at those paths. This is a local workstation
workflow, not a portable asset bundler. Missing assets fail with MuJoCo's path
error and keep the current model. For another machine, copy the entire source
asset directory and reimport there. Arbitrary original XML formatting/comments
are not preserved in the editor document.

Plugins, flex, skins, heightfields and SDF geometry are explicitly rejected.
Tendons/sensors and other supported MJCF physics are retained but their property
editing is outside the current controls. Meshes use compiled triangles; textures
are not rendered (geometry colors are shown). Unknown XML is diagnosed by MuJoCo.
Frame-attached poses and fromto-derived geometry pose/size are read-only with
explicit diagnostics: compiled local coordinates are not the same as source
frame coordinates. Ordinary explicit pose/size fields remain editable.
This is not full native Godot joint/CharacterBody/Area compatibility or walking.

Godot EditorUndoRedoManager stores snapshots against a RefCounted session in global history, never callbacks
on a freed UI Control. Disable releases native ownership; undo history retains
only the document snapshot. Saving uses a temporary file and atomic rename.
An explicit Recover button loads `user://mujoco_editor_recovery.json`.
Independent dot editor GUI acceptance remains required.

Undo routing follows the [EditorUndoRedoManager object-context rules](https://docs.godotengine.org/en/stable/classes/class_editorundoredomanager.html).

Preview layout fills the editor workspace; wheel zoom/right-drag orbit and Frame
all operate on the preview camera only. Input controls are numeric scalar/array
fields with explicit Apply, with read-only metadata labeled separately. Property
panels scroll on smaller screens. The preview uses geometry color rather than
photorealistic materials; it is intended to inspect physical models.
