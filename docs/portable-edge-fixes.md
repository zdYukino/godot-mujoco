# Independent acceptance findings and repairs — 2026-10-18

Base: `bedc0965b35395cc4faf222ded12aa709a8cba9c`, branch
`codex/portable-model-runtime`. Main is not changed. This follow-up supersedes
any inference that earlier cloud passes established reliable first import on dot.

## 1. First headless import: shutdown fault diagnosed, not an engine fix

Dot reported first-import shell status **139** for both portable runners despite
`--frame-delay 1000`; G1/dynamic first import also failed. GUI import and other
independent passes do not cancel these failures. Dot's original logs end after
`loading_editor_layout` and have no native stack. Its separately built extension
hash is `1ebe6f6fe751e45a93438dcd4a4ea764be339657fd137fe2b96c812383d7400e`.

The two supplied Library evidence ZIPs were materialized into a new cloud folder,
verified readable and extracted; no dot acceptance directory was accessed or changed.
Evidence IDs: `libfile_8c74393458848191b929d578f1b2cb57` and
`libfile_3e41bfe9e0ec8191b46a1831990a0f1b`.

Cloud diagnostic root: `/workspace/shared/validation/dot-fixes/`:

- Original helper, fresh asset-runner project: exit 0. Separate fresh import with
  an empty private editor cache and the 1000 ms delay: exit 0. The analogous
  fresh delayed GDB run exited normally. None establishes reliability on dot.
- Without frame delay, **six independent fresh projects** (three empty global
  editor caches, three copies of the existing global doc cache) all returned
  Python **-11**, equivalent to shell **139**. No project cache was reused.
  Commands/results are in `cache-matrix-env/*.log` and `cache-matrix-env/results.json`; the inherited
  toolchain environment was sourced for every trial. An earlier matrix omitted
  part of that environment and emitted setup errors; it is retained separately
  and is not the clean comparison reported here.
- A separate fresh native-only project, containing the extension but no
  portable/editor GDScripts, also returned -11 without frame delay
  (`native-only-env.log`). This separates the fault from the new resource
  validation and node lifecycle scripts. An earlier unsourced-environment
  native-only attempt failed to find hostfxr and is excluded.
- Fresh GDB reproduction: main thread SIGSEGV, PC `0x11364af`; caller chain
  `0x1cf3324 → 0x1cf9a35 → 0x4ec7d1d → 0x49cf3f4 → 0x599ce6`.
  See `gdb-fast.log`. GDB itself can exit 0 while its inferior crashes;
  **that debugger status is not an import pass**.
- A second fresh run with a hardware watchpoint observed the native documentation
  pointer at `0x9088240` first allocated, then reset to zero during shutdown,
  then used by the same delayed call chain. At the fault, `rbx=rdi=8` and
  instruction `mov 0x20(%rbx),%eax` dereferences address `0x28`.
  See `doc-watch.gdb` and `gdb-watch.log`.

The official executable is stripped. The function mapping is established by
comparing its disassembly with source at the pinned engine commit, rather than
claiming GDB emitted symbolic function names:

- Function at `0x1cf9a20` loads the global document pointer, calls generation
  with flags **3**, then conditionally merges a second global document.
  This matches [`EditorHelp::_gen_extensions_docs`](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/doc/editor_help.cpp#L3083).
- [`_load_doc_thread`](https://github.com/godotengine/godot/blob/ed1daf0bf/editor/doc/editor_help.cpp#L3031)
  queues extension documentation with `call_deferred`; `cleanup_doc` waits for
  the worker, deletes the document, and clears its pointer. Waiting for the
  worker does not by itself consume its queued main-thread callbacks.
- The observed cleared-pointer call is the shutdown ordering described by
  [Godot issue #111048](https://github.com/godotengine/godot/issues/111048).
  The captured stack contains engine addresses, not extension physics frames.

Engine SHA-256 for these address-specific diagnostics:
`fc1bd592b5e771c65d52968f99835b4f2b7fe7b7cbc141e202cb63e01c95ec4d`,
reporting `4.7.2.stable.mono.official.ed1daf0bf`.
The watchpoint addresses must not be reused with a different executable.

This proves the cloud shutdown fault and explains why a timing delay can appear
to work and still fail elsewhere. Dot's logs alone cannot prove every reported
139 has this exact stack; capture its inferior stack to establish that identity.
A real engine repair must finish/cancel deferred documentation work before
freeing its owner. This change does **not** patch the engine, change pinned
versions, increase sleep, transplant caches, retry a failed first import, or
substitute GUI success. `scripts/import_headless.sh` retains its documented
mitigation and actual exit propagation. **Reliable headless first import remains
an acceptance blocker**, with a concrete root-cause diagnosis now available.

A diagnostic custom `--editor --script` probe was also discarded: although it
exited 0, it leaked editor resources. It is not an accepted replacement importer.

## 2. Failed world entry now recovers

`MjRuntimeWorld._exit_tree()` previously returned when `ready_for_models=false`,
skipping `request_ready()`. A failed first entry had still consumed `_ready`, so
remove/fix/re-add configured a paused world but never applied `start_paused=false`.

The exit path now requests another ready notification for every runtime entry,
including failed ones; native cleanup and owner removal still require successful
ownership. Regressions cover both missing model and ownership conflict, retained
ownership of the existing world, successful recovery and cleared error state.

## 3. Validate the complete asset reference set

`MjModelResource.validate_package()` now parses the packaged MJCF before opening
it, compares the set of actual file references (including cube faces) with the
manifest, and requires exact coverage. Missing entries, unlisted references and
extra entries fail. Each listed dependency still requires its declared hash.

Paths must be canonical relative `assets/...` paths: absolute paths, traversal,
backslashes, empty/dot components and colon redirects fail. Include directives,
compiler asset-directory redirection and unsupported file-reference elements
are rejected before any MuJoCo compilation. This enforces the flattened portable
format, not general-purpose loading of arbitrary MJCF dependency layouts.

The integrity contract detects malformed manifests and mismatching bytes; it is
not a signature/authenticity mechanism against someone rewriting both XML and
all hashes. The raw document API continues to accept authored snapshots; callers
loading a packaged resource use its validated `open_document` or runtime nodes.

## Regression entry points and results

`tests/portable_runtime/recovery_integrity_test.gd` adds **47 checks** and is run
by the official runtime runner in its relocated project. It persists and reloads
malformed resources, rejects them from a live world, and asserts unchanged model
state and space revision. It also changes a valid OBJ, removes its manifest entry,
and verifies that the checksum can no longer be bypassed.

The missing-model and ownership-conflict errors are intentional. The runner
accepts exactly those two error lines in that test log; unexpected errors,
script failures, leaks or a nonzero process status still fail validation.

The supplied independent 10-check reproduction passed after the fixes, exit 0,
in a disposable cloud project (`edges-runtime.log`). The expanded 47-check
suite passed, exit 0 (`recovery-integrity2.log`). An earlier local trial reused
a deliberately corrupted fixture package and correctly refused to overwrite it;
that exit-1 log is retained as `recovery-integrity.log`, not counted as a pass.

Fresh full runners also passed on this cloud host (both exit 0):

```sh
source /workspace/shared/tools/env.sh
OUT=/workspace/shared/validation/dot-fixes/assets-fixed tests/portable_runtime/run_assets.sh
OUT=/workspace/shared/validation/dot-fixes/runtime-fixed tests/portable_runtime/run_runtime.sh
```

The asset runner includes fresh original and relocated imports, cube textures and
corruption diagnostics. The runtime runner includes 30 assertions before and
after relocation, the new 47 assertions, C# drive motion, 9 editor checks and
separate-process editor-authored scene execution. Raw logs/results are beneath
the two OUT directories. These one-shot cloud successes do not reclassify dot's
first-run failures or resolve the engine shutdown race. Dot subsequently also
reported fresh2 passes; those are independent runs, not retroactive passes.

Use the `OUT` environment variable: the current runners do not interpret a
positional directory argument. All reproduction paths above are explicit.
No native extension source or original Unitree asset is modified by this repair.
