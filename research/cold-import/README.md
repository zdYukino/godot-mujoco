# Isolated Godot 4.7.2 .NET cold-import lifecycle research

This branch starts from project commit `c8d0286ce2c882c863c2b2a82f74b47629a10d29`.
It does not change main, original model assets, or the existing official engine.
Experimental builds are not approved release binaries or a replacement baseline.

## Source and candidate

- Official engine commit: `ed1daf0bf001b61586d9930840f2f1394092c079`.
- Official source tree: `8cce5a783df3eb396336ecfb9331aaab0c172807`.
- Source archive SHA256: `e607e9985e1c201bc9cdc1aec8a120f0c3f53b9603f1f828e2b748534a2471ef`.
- The full archive tree matches after applying the pinned `.gitattributes` EOL
  normalization (25 CRLF checkout files). No source implementation is altered by
  that verification. Direct GitHub blob hashes also match editor_help.cpp/.h and
  version.py.
- [Issue #111048](https://github.com/godotengine/godot/issues/111048) and
  [issue #111645](https://github.com/godotengine/godot/issues/111645) report the
  same deferred-documentation shutdown fault.
- [PR #123658](https://github.com/godotengine/godot/pull/123658), head
  `5017b3b63302c0e99497a93bd468f019401668bf`, is **open, not merged**, as observed
  during this research. Its two-file owner-lifetime fix is the candidate being
  backported to the pinned source, with attribution retained here.

`godot-4.7.2-doc-owner.patch` binds five deferred documentation call sites to an
Object owner created with the document. Cleanup joins the worker, destroys the
owner, then frees the document. Godot's existing ObjectID-based call queue skips
callbacks whose target was destroyed. This does not drain unrelated work inside
a destructor, force exit, weaken import checks, insert sleeps, or warm caches.
The lifetime-specific owner also distinguishes a stale callback from a later
new documentation owner; a bare global null check would not.

## Reproduction and controls

`minimal_extension.cpp` has no MuJoCo dependency, simulation, manual allocations
or custom teardown. One build registers a RefCounted class with one method; the
other build registers no class. Both log initialization/termination.
`build_minimal.sh` uses the project's pinned godot-cpp headers/library.

`cold_matrix.py` stages independent projects without `.godot` and with private
XDG directories. Layers: empty, extension without class, single registered class,
project native extension only, full portable project. It records exit and shell
status independently of log text, native library hashes, SVG import output and
all discovered GDScript global class cache entries. Failed attempts are retained.

The existing project helper is a timing mitigation, not the candidate repair.
Candidate reliability runs use the official `--headless --editor --import`
command without frame delay: at least 20 serial imports and 10 imports in pairs.
Any crash, backend/script error, leak or missing import artifact fails the run.
A finite all-pass sample is not an absolute stability guarantee.

`official-doc-watch.gdb` contains addresses specific to official binary SHA256
`fc1bd592b5e771c65d52968f99835b4f2b7fe7b7cbc141e202cb63e01c95ec4d`.
Never use those addresses with a custom engine. GDB exit 0 is not proof that its
inferior succeeded: the captured signal and backtrace determine that outcome.

## Supported-flow assessment

The `--import` exit condition covers EditorFileSystem's initial scan, not queued
EditorHelp callbacks. Public filesystem scan/reimport signals therefore cannot
prove documentation completion. `--doctool` returns before the editor importer
and is not a substitute; a previous editor `--script` experiment leaked editor
resources. `ScriptEditor.goto_help` can wait for documentation workers, but that
is not a public completion barrier for all queued callbacks. No supported plugin
flow that repairs the lifetime defect has been established. The candidate fixes
ownership at the deferred-call source rather than adding a project timing delay.
