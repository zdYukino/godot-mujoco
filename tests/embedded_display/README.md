# Linux F5 display comparison

Use the unchanged official Godot 4.7.2 .NET executable. Do not modify the
engine, disable embedding to claim success, or reuse a crashed import as a fresh pass.

1. Open `plain/project.godot` with `--editor --rendering-method gl_compatibility
   --audio-driver Dummy`. Wait until the editor has finished starting.
2. Press F5 with embedding enabled. Record the child command line (including
   `--wid`), its PID, and screenshots after 2, 15 and 60 seconds. The expected
   scene is a green cube. The editor's `--audio-driver Dummy` argument is not
   automatically inherited by the F5 child.
3. Stop with F8. For a host without audio devices, add the following to the
   **project** settings, then repeat F5 without changing embedding:

   ```ini
   [audio]
   driver/driver="Dummy"
   ```

4. Repeat with the generated `RuntimeScene.tscn` from
   `tests/portable_runtime/run_runtime.sh`, which sets it as the main scene.
   Keep the MuJoCo physics backend and GL Compatibility renderer. Expect two
   fixed-base G1 models, a floor and a falling normal Godot rigid body.
5. Compare standalone execution using the same project, renderer and audio
   settings. Save stdout/stderr, commands, process exits and screenshots.
6. Repeat F5/F8 three times, resize the game view, switch editor workspace, and
   pause/resume. A single screenshot is not a stability or contact assertion.

Any ERROR or leak makes that run fail, even with exit 0. Retain startup GPU
probe errors separately; do not silently whitelist them. A grey area while the
child starts is not proof of a persistent rendering defect. Record how long it
persists and whether the child reached renderer/audio/scene initialization.

The plain project intentionally has no extension, editor plugin or audio override:
it is the negative/control fixture for the host's default startup behavior.
