# Shared runtime viewer

`MjRuntimeWorld` installs `MjRuntimeViewer` automatically in games. Godot editing
continues to use Godot input. `MjEnvironmentHost` stages candidates without input
or a native display lease, then binds the viewer after a successful commit.

## Controls

| Input | Action |
|---|---|
| Tab / Shift+Tab | Toggle the original left / right panels independently |
| Alt+F/O/S/W/P/R/V/G/L/J/C/E | Fold the corresponding original section |
| F11 | Open/close Godot extras only (renderer, performance, tools, examples) |
| F1 / F2 / F3 / F4 | Original Help / MuJoCo Info / Profiler / Sensors overlays |
| Left / right / middle drag; wheel | Orbit / pan / zoom; Shift changes the direction |
| Left double-click / PageUp | Select body / select parent |
| Right double-click / Ctrl+right double-click | Center / track |
| Ctrl+left / Ctrl+right drag | Rotate / translate perturbation |
| Space / ← / → | Run/pause / history back / history forward or one new step |
| - / = | Official 0.1–100% speed tiers |
| [ / ] / Esc / Ctrl+A | Fixed cameras / free camera / model framing |
| F6 / F7 / backtick | Frames / labels / Body Tree |
| 0–5 / Shift+0–5 | Geom / Site group visibility |
| Ctrl+C / Ctrl+Shift+C | Copy state as key XML / high precision |
| Backspace / Ctrl+L | Initial reset / reload last saved scene design |
| Ctrl+M / D / P / Q | Model text / data text / composed screenshot / quit game |
| F5 | Standalone fullscreen; embedded GameView reports its editor-managed limitation |

F8–F10 remain Godot debugger controls. In the simulation and original panels,
Tab/Shift+Tab toggle the left/right sidebars; within F11 they move control focus.
Text fields consume editing shortcuts before scene actions. F11 remains available
with an embedded window, text field or popup focused. The help includes the linked
MuJoCo version's display/group shortcuts, renderer differences and example notes.

The left panel contains File, Option, Simulation, Watch, Physics, Rendering,
Visualization, Group enable and Logging in original order. The right contains
Joint, Control and Equality. Both initially appear, independently of F11. Help
and Info draw in the central scene; the four profiler figures stack along its
right edge. Sensors use an overlay without a separate window/title bar.
Godot controls adapt the fixed 3.16 definitions, input and theme; this is not an
embedded GLFW/mjui main loop or a claim of pixel-identical native widget drawing.

Runtime perturbation adds a viewer-owned wrench to existing external forces.
Paused perturbation follows MuJoCo's free-joint/mocap rules. Releasing the mouse,
opening a panel, losing application focus, changing worlds/renderers or stopping
cancels the gesture. No arbitrary-joint IK or editor design writeback is performed.

## State and diagnostics

Backspace and `reset_initial()` restore the compiled design's initial pose at time
zero, clear velocities/forces and retain camera/run state. Capture and explicit
Restore Snapshot use `mjSTATE_INTEGRATION`; Capture does not redefine Backspace.
Legacy `reset_simulation()` retains its previous checkpoint semantics for callers.
`WorldHandle.Read().HasSnapshot` retains that legacy checkpoint meaning;
the viewer frame's `has_snapshot` reports the full integration snapshot.
History is a bounded official-style ring (up to 2000 states and 100,000,000 bytes).
Snapshots/history are invalidated on a new model revision.
Simulation includes Pause/Run, Reset, Reload, Align, Copy state, model keyframe
load/save, control noise, solver workers and a history scrubber. Noise follows the
original Ornstein–Uhlenbeck update and actuator limits. Solver workers use
`mju_threadpool` (0–10). Pause update runs forward diagnostics and updates the
solver warm start without advancing simulation time/history.

F11 → Tools exposes additional exact batches of 1–1000 integration steps and
manual full-integration snapshots. These are separate from original keyframes.
The existing shared-world composer rejects source models containing keyframes
(as it does global userdata/mocap sources). This model-support restriction is
preserved: Key/Load key/Save key remain visible, disabled with a reason when the
compiled model has none; successful keyframe composition is not claimed.
Physics design fields are read-only. The original Busy Wait control is disabled
because the Godot main loop owns scheduling. UI spacing/color/font and supported
VSync/fullscreen options keep their original Option placement.

Joint sliders edit scalar hinge/slide qpos while paused. Control and Equality edit
true runtime data. Clear Control uses `mj_resetCtrl`, including neutral quaternion
controls. Physics parameters are read-only. All Rendering/Visualization/Group
entries are listed; unavailable backend effects are disabled with an explanation.
Godot keeps authored materials/lighting; MuJoCo OpenGL effects are native-only.

Profiler samples the real integration step before the server's final forward
update. CPU timers are milliseconds and are unavailable if another owner installed
an incompatible clock callback. Sensors show normalized values, and support the
simulate user-image convention (width/height integer parameters, RGB values and a
final version marker); a model must supply the data. Watch is a bounds-checked
numeric mjData lookup. Logging Console/File/topics control the actual handler.

MuJoCo Info (F2) and the Godot performance overlay are independent. F2 does not
change FPS/system metrics. F11 → Performance controls the Godot overlay, initially
FPS-only; every metric, including FPS, can be disabled. Optional CPU/RAM/GPU/VRAM numbers
refer to the whole system/card. GPU selection must match the renderer, otherwise
it is unavailable. GPU milliseconds are elapsed render time, not utilization.
Native update FPS and Godot host FPS are labeled separately. Information refreshes
at 5 Hz, optional OS samples at 1 Hz; no optional polling without a visible consumer.

Preferences live in a per-project `user://mujoco_viewer_*.cfg`; simulation state is
not stored there. F11 starts closed; original sidebars default to visible and
original F1–F4 overlays to hidden. Old mixed Info/performance preferences migrate
into separate settings. Each fresh run starts from the
authored camera, including its initial projection. Outputs default to timestamped
folders under `user://mujoco_viewer`; F11 → Tools accepts a different directory.
Original File includes XML/MJB saves, print exports and screenshots. XML exports
the committed compiled world with its session keyframes; it never uses the
process-global last-XML parser slot or writes back editor design. State copying
remains the original key XML operation, including high-precision Ctrl+Shift+C.
Reload is transactional: invalid saved resources preserve the current world.

## Integration

- `world.runtime_viewer` exposes `request_action(Dictionary)` and
  `viewer_command_finished(Dictionary)`, plus `world_changed(Node3D)`.
- `register_extension(key, title, Control, help)` places example controls inside
  F11 → Examples and adds their help to F1.
- `WorldHandle.ResetInitial()/RestoreSnapshot()` and `ViewerHandle` provide C#
  access. Rebind typed world/model handles after `world_changed`.
- `set_controls_visible` / C# `ShowControls` remain aliases for Godot extras.
  `set_overlay` / `SetOverlay` control Godot performance. Original sidebars and
  Info use `set_native_panels` / `ShowNativePanels` and `set_info` / `SetInfo`.
- Native interfaces are `scene_viewer_request(space, revision, frame, sequence,
  command)`, `scene_viewer_frame(space, known_revision, options)` and
  `scene_viewer_ack(space, revision, frame)`. Consume results with
  `scene_viewer_result(request)`; cancel unused requests explicitly.

The core uses public `mjv_*` APIs and adapted MuJoCo 3.16 simulate logic, with no
GLFW or second simulation loop. Frozen scenes use `mjv_copyData`; packets contain
only values and pointer-free SDK structs with an ABI/version check. Picking retains
the displayed CPU frame and its frozen visibility settings. Sidebar layout
changes update both camera projection and native framebuffer/render rectangles;
inputs wait for a matching presented layout before picking. Queued inputs pin
their frames until processed, and at most three frozen scene slots are retained/reused.
A per-world cancellation latch releases perturbation at the next command boundary
even when input/result queues are full; earlier motions cannot restart it.
The CPU viewer owns its model header/display settings and borrows the current
revision's immutable model arrays only on the main thread. Its header/scenes/history
have a 256 MiB admission budget; optional native GPU transport has its own existing
asset/lease limits. These owned-buffer limits do not bound total process RSS.
The core remains available with `GMJ_NATIVE_VIEW_EXPERIMENTAL=OFF`.

See `src/viewer/UPSTREAM.md` and `src/viewer/LICENSE-MUJOCO` for source and licensing.

## Validation

`python3 tests/runtime_viewer/run.py --out build-runtime-viewer/godot`
checks real Godot input, authoritative operations, outputs and saved-scene reload.
Add `--native` for the GLX path or `--headless` for the display-free path.
`tests/runtime_clock/run.sh` retains the existing clock/C# compatibility checks.
The graphical fixture records p50/p95 frame times and process RSS with VSync off
and a 120 FPS cap for overlay off/FPS/all metrics/analysis modes. These short,
capped fixture samples are not uncapped throughput or production benchmarks.

The panel-separation acceptance also captures both renderers with the four sidebar
combinations, F1–F4 and F11; it tests real keyboard/focus routing, central picking,
resize/SubViewport, orthographic/fixed/tracking/off-axis cameras, native-control
outputs and independent data consumers. Historical viewer results predate these
UI criteria; new evidence is recorded separately.
