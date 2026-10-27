# MJCF EditorPlugin acceptance (Linux)

Build the pinned Linux extension first, then:

```sh
source /workspace/shared/tools/env.sh # if using the cloud tool installation
OUT=/tmp/gmj-editor-new tests/editor_plugin/run.sh
```

The runner uses a fresh isolated project and the cold-import helper. It runs an
actual `--editor` process with the enabled EditorPlugin, not a runtime imitation.
116 assertions cover import, real body mass/inertia-derived size/density, kp/kv
and non-PD rejection, joint movement, controls, geometry visuals, failed candidate
compilation, rollback, state migration, EditorUndoRedoManager, atomic persistence,
external include/OBJ resolution, unsupported content, draft recovery, scene switch,
repeated native activation and actual plugin disable/enable. An independent
cylinder falls onto a plane using real MuJoCo contact. Reports include the addon
SHA-256. Nonzero process exit, missing reports, failed checks, script/engine errors
or ObjectDB leak diagnostics fail the headless runner. The existing MjWorld smoke
has an intentional bad-qpos diagnostic; it is separate from this runner.

For the same staged project's **actual editor screenshots** on a Linux desktop:

```sh
godot --editor --path /tmp/gmj-editor-new/project \
  --rendering-method gl_compatibility --audio-driver Dummy \
  --resolution 1600x1000 -- --mj-editor-test \
  --report=/tmp/gmj-editor-new/render-results.json \
  --capture-dir=/tmp/gmj-editor-new/screenshots
```

The three screenshots are engine viewport captures of the editor itself. Capture
adds three assertions (119 total). Cloud rendering uses Mesa llvmpipe and Xvfb;
it does not replace dot's independent actual desktop acceptance.

## Manual acceptance

1. Build/stage the addon. Open `examples/pendulum/project.godot`, enable **MuJoCo Model Editor**
   under Project Settings → Plugins, and choose the **MuJoCo** main workspace.
2. Import `tests/editor_plugin/fixtures/pendulum.xml` through the file chooser
   (filesystem access accepts files outside the project). Select body, joint and
   each of the three actuator types. Verify units, limits, N/A and read-only fields.
3. Select `position_drive`, edit control to `0.5`, Apply, then Run. Observe joint
   qpos in the live line and the moving physical arm. Pause; change kp/kv separately.
4. Add box, sphere and cylinder. Select their geom children to edit MJCF half sizes,
   density and friction; select bodies to edit mass and local position/quaternion.
   Apply is explicit. Once body mass is made explicit, density is rejected with
   an explanation. Run to see true falling/contact; wheel zoom and right drag orbit.
5. Delete a body, use Godot Ctrl+Z/Ctrl+Shift+Z, and verify both tree and physics.
   Save `.gmj.json`, change parameters, reopen and compare. Do not move external
   source assets; this document uses absolute resolved paths, not bundled assets.
6. Try a missing/invalid MJCF and invalid dimensions. Confirm the old model and
   pending text remain. Draft edits block destructive UI navigation. Recover reads
   the autosaved document/draft. Switch scenes, disable/enable the plugin and exit.
7. Repeat with `fixtures/external/model.xml` and its complete neighboring folder.
   Capture before/after screenshots independently. Source XML/meshes must not change.

See [scope and ownership details](../../docs/mjcf-editor.md). This milestone does
not add CharacterBody/Area/native-joint compatibility or walking validation.

The Apply regression emits actual Button.pressed signals for qpos, kp, kv and
body position, checks complete form retention after Apply/undo/redo/Discard, and
checks invalid input and repeated signals on retired controls. Direct calls to
apply_fields alone do not reproduce signal-emitter lifetime bugs.
