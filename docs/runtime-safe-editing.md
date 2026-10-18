> [中文使用指南](runtime-safe-editing.zh-CN.md) · [当前范围与验证](freebase-clock-validation.zh-CN.md)。本文保留原阶段的英文说明；版本和支持范围以当前入口为准。

# Applying design revisions safely to running instances

Linux only, unchanged Godot 4.7.2 .NET and MuJoCo 3.16.0. Main-thread physics is
required; `MjRuntimeWorld` rejects `physics/3d/run_on_separate_thread=true`.
This is a synchronous compilation transaction; a large robot can visibly pause.

## Editor workflow and persistence

1. Run the shared runtime scene with F5. MuJoCo workspace lists each connected
   debugger session and instance path. IDs also contain the node generation,
   so deletion/re-addition at the same path cannot target an old instance.
2. Edit the preview, Apply its fields, then **Save project model** to publish an
   immutable design resource. **Apply saved model to runtime** targets only the
   selected running instance and reports pending / applied revision / error.
   Unsaved fields, stale revisions and repeated clicks are rejected explicitly.
3. **Send selected control to runtime** sends the selected actuator control to
   that instance without recompilation. It respects actuator limits. It does
   not save the running robot's state into any design resource.
4. To persist the change for future F5 runs, select one `MjModelInstance` in the
   **local** Godot scene tree, click **Assign saved model to scene selection**,
   then save the Godot scene. This assignment supports normal scene undo/redo.
   Live Apply alone deliberately does not overwrite the scene or its siblings.
5. Restart: the scene loads the saved design resource and its authored initial
   state. Current simulation qpos, qvel, activation and time are not saved back.
   Saving a project model captures the editor preview state as authored initial
   state; it is distinct from taking a snapshot of the running world.

The runtime node API is `request_model_edit(saved_resource, expected_revision)`.
It returns whether a request was queued, not whether compilation succeeded.
Poll `edit_request`/`property_revision`/`last_error` or observe `edit_finished`.
The resource is reread independently from its saved path; in-memory resource edits
must be saved first. This avoids sharing mutable editor resource objects.

## Transaction boundary

`scene_request_model_edit` copies the snapshot into a bounded native request
queue. It does not write the active model/data. At the start of native `_step`,
before any `mj_step`, the server performs:

- Resolve world and instance RID; compare the expected per-instance revision.
- Remember pause state and fractional timestep accumulator, then pause the world.
- Resolve packaged assets and compile the candidate off to the side.
- Reject option conflicts, unsupported global data and incompatible same-name
  joint types / actuator activation dimensions before replacement.
- Replace only that instance's source spec and compile the complete shared world.
  Keep RID and name prefix unchanged. Migrate compatible qpos/qvel, warm-start,
  controls, activation and time; initialize newly inserted names from the design.
- Commit and increment revision only on success. On failure retain original
  spec, initial-state metadata, active model/data and revision. Restore the prior
  pause state and accumulator in both cases, then expose the completion result.

Removing a node cancels its queued request and consumes any completed result.
Instance IDs and revision checks prevent stale operations from applying to a
replacement robot. Queue/result bounds prevent unbounded accumulation. Runtime
visuals rebuild only after successful commit. The default main-thread physics
mode also serializes control updates with stepping; background mutation is not
supported or claimed.

## Automated and GUI verification

```
source /workspace/shared/tools/env.sh
OUT=/tmp/gmj-live-new tests/portable_runtime/run_live.sh
OUT=/tmp/gmj-runtime-new tests/portable_runtime/run_runtime.sh
```

`run_live.sh` stages a fresh project. It checks candidate compilation failure,
option conflicts, same-name joint incompatibility, rollback, retry, paused and
running edits, exact paused state preservation, new internal topology, removal,
12 robot add/edit/delete cycles, saved design and restart state. Its separate
editor process uses the real debugger channel to a real child process, checks
repeated-click gating, instance isolation, controls, session cleanup and scene
assignment undo/redo. The automated child is explicitly headless; this is not
an embedding/display test. Headless persistence uses PackedScene serialization
because the official editor thumbnail path emits a dummy-renderer ERROR.
The GUI variant uses the actual editor Save action.

`run_runtime.sh` also exercises live edits after relocation, original paths
unavailable, C# control, normal Godot body contact, editor save/create/restart.
Its normal-process gate rejects **every** ERROR/leak. The missing-model and
ownership-conflict negative cases run in two independent Godot subprocesses under
`negative/`, each with an exact diagnostic and state-integrity contract. Their
complete raw logs are retained; additional/missing/duplicate diagnostics, leaks,
failed assertions and nonzero/timeout exits fail the suite. No log text is removed
or replaced. See [the isolated-negative follow-up](portable-isolated-rejections.md).


Dot GUI checklist:

1. Load two fixed-base G1s and an ordinary rigid body. Start F5, choose one runtime
   target; change mass/inertia and joint damping. Unsaved Apply must refuse;
   save then Apply twice. Observe one revision increment and continued motion.
2. Pause the runtime world, apply another saved design, verify it remains paused
   and joint state/control continuous. Resume and verify normal contacts.
3. Apply an incompatible saved resource; error and old revision/model remain.
   Correct it and retry. Change selected target while pending; the response must
   remain associated with the originating ID, not overwrite the new target.
4. Add/delete/re-add robots, including one with a pending request. Verify target
   list cleanup and unchanged peers. Stop/restart F5; no stale sessions remain.
5. Assign the saved resource to a local scene instance, undo/redo, save and restart.
   Only that scene reference changes; initial state comes from the design.
6. Confirm Apply/Discard selection protection, frame/fromto read-only fields,
   scalar sphere sizing, and no ERROR/leak in all acceptance logs.

Cloud real-renderer screenshots are evidence of executed UI, not dot acceptance.
Known cold-import 139 and cloud Vulkan surface-probe ERRORs remain unresolved.
