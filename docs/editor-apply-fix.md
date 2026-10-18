# Editor Apply/Discard signal lifetime correction

Follow-up to `89da392f773d930aee3bdb2c85d6c889ff6606b3`, reported by dot's
independent desktop acceptance. Main remains unchanged.

## Cause and fix

Apply and Discard buttons belonged to the form they synchronously rebuilt.
`pressed → apply_fields → execute → record_change → refresh → build_fields`
called `free()` on the button still emitting its signal. Godot rejects this
locked-object destruction; the interrupted rebuild left a partial property form.
Direct test calls to `apply_fields()` did not exercise that lifetime constraint.

Form rebuilding now detaches old children immediately and destroys them with
`queue_free()` after signal dispatch. Retired buttons are disabled and their
pressed connections are disconnected before detaching. Thus the new form is
available immediately, while an old/repeated activation cannot act on it.
The same centralized path covers Apply, Discard, selection and undo/redo refresh.
Mesh teardown has no UI signal-emitter ownership and is unchanged. File dialogs
already use deferred destruction; plugin shutdown disconnects session signals.

## Verification

The new regression emits real **Button.pressed** signals for joint qpos, actuator
kp and kv, and box position. It checks actual model values and complete live
input-field retention after Apply, undo and redo. It then exercises invalid
Apply, draft retention and Discard through the buttons. Re-emitting a retired
Apply signal must not advance model revision.

Running that regression against the old panel reproduced both locked-object
errors and failed with process exit **1**. Log:
`/workspace/shared/validation/apply-before.log`.

The fixed fresh-project command:

```sh
source /workspace/shared/tools/env.sh
OUT=/workspace/shared/validation/apply-release tests/editor_plugin/run.sh
```

passes **116 checks**, cold import and process exit **0**. Evidence lives in
`apply-release/{import.log,runtime.log,results.json}`. No locked-object, script,
engine or ObjectDB leak errors occur in the headless run. The runner now also
bounds forced shutdown after a timeout so a failed editor test cannot hang on
an unsaved-document dialog.

The same project runs in an actual 1600×1000 OpenGL editor on Xvfb/Mesa with
`--mj-editor-test --capture-dir=...`, passing **119 checks** and exiting **0**, including three screenshot checks. Full logs,
report and screenshots are retained under `apply-release`. Host Vulkan/VSync
diagnostics remain distinct from script errors, as in the parent validation.

Only editor UI, regression tests and documentation changed. C++ physics and
original model assets are untouched. The extension SHA-256 remains
`ba7b43d67115f49d5a794fc8bead0307bc7e76362bb5cb5f58a00521bb53013b`.
Previously accepted backend/dynamic/MjWorld/G1 results are not relabeled as new
runs. Dot should repeat the three reported click sequences on the new exact
commit without switching entities to repair the form, then continue its GUI gate.
