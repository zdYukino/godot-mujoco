# Typed C# runtime control (Linux, Godot 4.7.2 .NET / MuJoCo 3.16)

The product API is `demo/addons/godot_mujoco/csharp/MuJoCoRuntime.cs`, namespace
`GodotMuJoCo`. Copy the addon into a .NET Godot project; the normal SDK compile
includes its C# sources. Bind existing configured `MjRuntimeWorld` and loaded
`MjModelInstance` nodes on the main thread. This facade uses the existing native
transaction queue; it does not mutate model/data from worker threads.

```csharp
using GodotMuJoCo;
// Called on the Godot main thread after the initial snapshot finishes.
using var world = WorldHandle.Bind(GetNode("Environment")).Value;
using var robot = InstanceHandle.Bind(GetNode("Environment/Robot")).Value;
var control = robot.SetControl("drive", 0.4); // immediate validation/result
var request = world.Step(10);                // requires paused world
if (request.Accepted) {
    var completion = await request.Finished; // actual boundary result
    GD.Print(completion.Success, " ", completion.Error);
}
```

Check `Access<T>.Success` before using `Value`; a failed binding has no handle.
`WorldHandle.Read()` exposes time, timestep, pause, checkpoint, contacts, pending
request and last queue error. `InstanceHandle.Read()` copies named joint states,
controls, body masses/transforms, unique live identity and property revision.
Snapshots are read-only copies. Transforms are Godot Y-up; qpos/qvel and controls
retain MuJoCo units and actuator semantics (not universally radians/torque).

`Pause`, `Step`, `Capture`, `Reset` and `Apply` return a `Request`. `Accepted`
only means enqueued; `Finished` supplies request ID, success, error and applicable
revision/time/pause feedback. A duplicate or initial-snapshot conflict is rejected
immediately. Invalid step counts and stale revisions can be accepted then fail at
the boundary. Do not block the main thread waiting for a task. Body node transforms
can lag native completion until Godot's subsequent synchronization frame.

`ModelDesign.Load(savedResourcePath)` validates a saved portable design;
`robot.Apply(design, expectedRevision)` queues the existing pause/compile/migrate/
commit-or-rollback transaction. Controls update immediately; they are simulation
state. The facade does not save runtime state into design resources. Saving an
editor resource and reopening it preserves design; a fresh World3D begins a new
simulation. Replacing an owner node in a still-live World3D does not reset that
space's clock automatically.

All API calls and disposal belong on the Godot main thread. Worker-thread reads,
bindings, loads and operations are rejected; worker-thread `Dispose` throws.
Dispose handles when finished. Removal, queued deletion, exit/reentry and instance
unload/reload invalidate old handles even when the same node is reused. Bind again
explicitly. Ending a handle completes an outstanding observer task with failure;
it does not promise cancellation of an already accepted native request. Multiple
handles observing one node still respect that node's pending-request gate.

## Lightweight acceptance

Build/stage the matching native extension and MuJoCo library into the demo addon
first (see existing Linux build guide). With Godot and .NET on PATH:

```sh
GODOT_BIN=/path/to/Godot_v4.7.2-stable_mono_linux.x86_64 \
  OUT=/tmp/typed-control-new bash tests/typed_control/run.sh
```

Use a new OUT each time. This creates two tiny hinge models and a normal box,
imports a disposable project, builds C#, and runs bounded checks. No Unitree assets
or stress tests are copied. Logs and `executions.tsv` preserve each executed
stage's exit code; unexecuted stages have no success record. `results.json` is
written only after all checks and strict ERROR/leak scans pass. Timeout/crash is
failure. Import 139 remains the known independent initialization limitation;
this runner does not retry a populated cache or claim an engine fix.

For dot GUI verification, open OUT/project with the fixed .NET editor, build C#,
and run `TypedControl.tscn`. It is a log-driven acceptance scene, not a visual
robot demo. Expect the structured final result and no ERROR/leak. Inspect saved
`Environment.tscn` and portable resources, close/reopen the editor, and run again.
Separately inspect the normal runtime scene for displayed node poses following
step completion; the automated test waits for synchronization before checking box
motion. GUI verification must be reported separately from headless results.
