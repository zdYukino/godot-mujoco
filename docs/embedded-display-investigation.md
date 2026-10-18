# F5 embedded display investigation — 2026-10-18

Application baseline: `c8d0286ce2c882c863c2b2a82f74b47629a10d29`.
New branch: `codex/application-editing`. Remote main was verified as
`bb1294e4f1d074d2a7c6a3852b428d83020ae5b3` and was not changed.

## Result and scope

Persistent grey embedding was **not reproduced** after startup completed on this
cloud Xorg dummy-display host. Actual F5 embedded windows displayed both the plain
Godot green cube and the generated two-G1 scene with ordinary Godot rigid body.
This does **not** establish that dot's reported persistent grey view is fixed.
No engine changes, cold-import research, or embedding-disable workaround occurred.

The editor CLI `--audio-driver Dummy` was absent from the F5 child arguments.
The plain child attempted ALSA, emitted an ERROR, then fell back to Dummy and
rendered. The portable physics acceptance project now explicitly selects Dummy
in project settings, so F5 and standalone use the same silent audio configuration.
This is a project configuration correction, not a claimed rendering-engine fix.

Both editors emitted Vulkan surface-probe ERRORs despite subsequently using GL
Compatibility. Under the requested strict gate these runs **fail**. Screenshots
prove rendering, not clean acceptance. Cold import 139 remains an independent known
limitation; it was not investigated or claimed fixed.

## Evidence

- [Plain embedded window](evidence/embedded-display/plain-embedded.png)
- [Two G1 embedded window](evidence/embedded-display/mujoco-embedded.png)
- [Plain editor and F5 child log](evidence/embedded-display/plain-editor.log)
- [MuJoCo editor and F5 child log](evidence/embedded-display/mujoco-editor.log)
- [C# build failure](evidence/embedded-display/dotnet-build.log)

Official executable reported `4.7.2.stable.mono.official.ed1daf0bf`; MuJoCo 3.16.0.
Host renderer: Mesa llvmpipe OpenGL 4.5, Xorg dummy screen 1600x1000. Tests use
`/workspace/shared/validation/application-display/`; application regression logs
use `/workspace/shared/validation/application-runtime/`.

Editor launch (plain/mujoco project path respectively):

```
godot --editor --path PROJECT --rendering-method gl_compatibility --audio-driver Dummy --resolution 1600x1000
```

Observed MuJoCo F5 child arguments (plain used the same form with Main.tscn):

```
Godot_v4.7.2-stable_mono_linux.x86_64 --path /workspace/shared/validation/application-display/mujoco --remote-debug tcp://127.0.0.1:6007 --editor-pid 2484 --scene res://RuntimeScene.tscn --wid 6291535 --display-driver x11 --position 224,176 --resolution 1152x648
```

The `--wid` and screenshots establish actual embedding. Input was sent through
X11 XTEST F5/F8 events, not a replacement standalone launch. The scene used the
runtime suite's authored resource bundles; no source robot assets were modified.

## Command results

| Command | Exit / result |
| --- | --- |
| `cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 4` | 0 |
| `OUT=/workspace/shared/validation/application-runtime tests/portable_runtime/run_runtime.sh` | 1 at C# build; not a suite pass |
| Initial fresh import / author / runtime | 0 / 0 / 0; runtime 30/30 |
| Relocated fresh import / runtime / recovery-integrity | 0 / 0 / 0; runtime 30/30; intentional negative diagnostics retained |
| `dotnet build .../PortableRuntime.csproj -c Debug` | 1, NuGet-Migrations named mutex IOException |
| Plain standalone `--audio-driver Dummy --rendering-method gl_compatibility --quit-after 120` | 0 |

C# build failure prevents claiming full portable/C# regression. Changing TMPDIR
and granting `/dev/shm` write access did not resolve it; no result was relabeled
successful. GUI editor probe ERRORs are also retained and remain failures.

For dot's next independent comparison, use the exact generated RuntimeScene main
scene, GL Compatibility, project-level Dummy audio, and embedding **enabled**.
Record the child arguments, first-frame delay, complete logs and a screenshot.
Follow [the controlled comparison procedure](../tests/embedded_display/README.md).
Do not replace persistent-grey evidence with a successful standalone run.
