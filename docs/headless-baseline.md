> [中文使用指南](linux-install.zh-CN.md) · [当前范围与验证](freebase-clock-validation.zh-CN.md)。本文保留原阶段的英文说明；版本和支持范围以当前入口为准。

# Linux headless baseline

The recovery baseline is **Godot 4.7.2 .NET**, **MuJoCo 3.16.0**, Linux x86_64.
The extension remains a native GDExtension, with the existing `godot-4.5-stable`
bindings/API target for compatibility. The demo itself uses GDScript; the .NET
engine can run it without converting the demo to C#.

This is a newly reconstructed and tested baseline, not a byte-identical recovery
of a lost local commit. Historical 3.12.0 examples or validation records are not
evidence for 3.16.0. No Windows, macOS, Android or iOS runtime validation is claimed
by this Linux-only work. Existing platform definitions are retained, and the
existing release checksum pins are updated without claiming those builds passed.

## Reproduce

Use the actual .NET executable, not an older `godot` elsewhere on PATH:

```sh
source /workspace/shared/tools/env.sh  # local environment, if available
export GODOT_BIN=/workspace/shared/tools/bin/godot
"$GODOT_BIN" --version
# Expected: 4.7.2.stable.mono.official.ed1daf0bf

cmake -S . -B /workspace/shared/builds/godot-mujoco-3.16 \
  -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++
cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 8
scripts/import_headless.sh
"$GODOT_BIN" --headless --path demo res://HeadlessTest.tscn
"$GODOT_BIN" --headless --path demo res://ChaosPendulumTest.tscn
"$GODOT_BIN" --headless --path demo res://VisualDebugTest.tscn
"$GODOT_BIN" --headless --path demo --quit-after 120
```

The separate build directory preserves the old `build/` cache. Do not reuse a
3.12.0 CMake cache and assume the default version changed its cached selection.
The local reconstruction used official CMake 4.4.4 and the existing
`godot-4.5-stable` source checkout via `FETCHCONTENT_SOURCE_DIR_GODOT-CPP`.

## First-import crash and workaround

**2026-10-18 independent acceptance update:** dot's first portable, G1 and
dynamic imports returned 139 even with the helper's 1000 ms delay. Reliability
is not established. The cloud follow-up reproduced a shutdown-time cleared
EditorHelp document pointer with a native watchpoint; see
[the diagnosis and evidence](portable-edge-fixes.md). The helper remains a
mitigation, not an engine fix; preserve every first-run failure.

Fresh headless imports can race during GDExtension documentation generation.
This matches the reported behavior in
[Godot issue #111048](https://github.com/godotengine/godot/issues/111048), which
remains an upstream issue. A populated `.godot` cache can hide the first-import
failure; a second successful run is not proof the first run succeeded.

`scripts/import_headless.sh` adds `--frame-delay 1000` to a single
`--headless --editor --import` invocation. This is a timing workaround, **not an
engine fix or a guarantee**. It requires Godot 4.7.2 .NET, refuses a mismatched
version, and propagates the actual Godot exit status. It does not automatically
retry or turn a crash into success. A timeout supplied by a caller must likewise
be treated as a failed validation. Do not use `|| true` for this import or judge a
test only by a PASS marker if its process later crashes.

The older `scripts/cloud_setup.sh` and existing CI workflow still use their
historical standard-engine import flow; their swallowed import errors do not
establish this .NET baseline. Use the helper above for the validated procedure.

## Supply chain and source compatibility

- Release: https://github.com/google-deepmind/mujoco/releases/tag/3.16.0
- Linux x86_64 archive SHA-256:
  `139577c541d43716a63992ab698cbc7b09788b1d547fb82b682d59b40ef49b9d`
- Source archive SHA-256:
  `45fe830707c80cf2fa54b37811ea13d7cc1774400704f69d85d2ecc1a151a236`

The binary hashes are pinned from the official release metadata; the source hash
was calculated from the official tag archive. CMake verifies downloaded content.
The obsolete mobile `localtime_r` patch hunk was removed because upstream 3.16.0
already handles Linux (including Android). The remaining patch was dry-run
against the new source archive; that is patch compatibility, not mobile build or
runtime validation.

## Fresh reconstruction results (2026-10-17 UTC)

Verified locally on Linux x86_64 with Godot
`4.7.2.stable.mono.official.ed1daf0bf`, .NET 8.0.32, and CMake 4.4.4:

- Clean separate native extension build: exit 0.
- Runtime linkage: `NEEDED libmujoco.so.3.16.0`, `RUNPATH $ORIGIN`; `ldd`
  resolves that runtime from the demo's bundled `bin/` directory.
- Fresh plain `--headless --editor --import`: SIGSEGV (Python return -11,
  equivalent shell status 139). This run did not emit a useful stack trace, so
  matching the upstream issue is a diagnosis from its behavior, not a proven
  stack-level root cause.
- Fresh import with `--quit-after 120`: exit 0 in one trial. This differs from
  earlier observations; one pass of a timing-dependent race does not establish
  it as a reliable fix.
- Helper with `--frame-delay 1000`: six separate fresh-cache trials passed,
  each exit 0. No cached retry was used.
- ChaosPendulumTest and VisualDebugTest: PASS and exit 0.
- Main scene: 120 frames, exit 0, reports MuJoCo 3.16.0.
- Separate C# engine smoke: build and runtime exit 0; reports .NET 8.0.32.
  This proves C# execution, not C# access to every extension API.
- Helper contract checks: a stub engine returning 37 remains status 37;
  a 4.6.3 version is rejected with status 2. Shell syntax and `git diff --check`
  passed.

The first isolated smoke harness accidentally excluded nested `models/assets`,
so its multifile-model test correctly failed. That harness failure is retained
in local logs; the complete-fixture rerun is recorded below. The corrected full-fixture copy
excludes only the separately tested top-level G1 robot assets from this baseline's scope.

Complete-fixture rerun: fresh helper import exit 0 (a seventh fresh pass);
HeadlessTest, ChaosPendulumTest, and VisualDebugTest each PASS with exit 0;
Main scene again exits 0 after 120 frames. HeadlessTest's invalid-input error
messages are intentional rejection checks, and its multifile model now loads.

Local detailed logs: `/workspace/shared/validation/mujoco-3.16/`. These are
machine-local evidence, not committed or portable build artifacts.
