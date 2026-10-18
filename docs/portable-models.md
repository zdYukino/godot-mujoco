# Project-owned MuJoCo models

Branch `codex/portable-model-runtime`, starting at the accepted
`bb1294e4f1d074d2a7c6a3852b428d83020ae5b3`. Linux only, Godot 4.7.2 .NET,
MuJoCo 3.16.0 and .NET SDK 8; no main promotion without independent acceptance.

## Project resource workflow

Enable the MuJoCo editor plugin, import MJCF or open an existing `.gmj.json`,
and choose **Save project model**. This publishes an immutable bundle beneath
`res://mujoco_models/model_<content-hash>/` containing:

- `model.tres`: `MjModelResource`, canonical MJCF plus authored/saved initial state;
- `model.xml`: human-readable canonical MJCF with include contents expanded;
- `assets/<sha256>.<extension>`: byte-identical mesh/texture dependencies;
- `sources/<sha256>.xml`: archived original XML/include bytes for provenance.

Original files are only read. Original path strings remain in provenance, never
as runtime dependency paths. Actual MJCF assets use `assets/...`, resolved from
the resource's current directory at load time. Copy the entire Godot project,
including its addon binary, to relocate it. Filesystem projects are supported;
PCK/ZIP export requires extracting filesystem assets and is not claimed here.

**Open project model** loads a saved `.tres` for preview/editing. Saving edits
creates a new content-addressed bundle; it does not overwrite an existing bundle
or update every scene using it. This gives an explicit application boundary.
Identical imports deduplicate; same-named assets with different bytes have different
hash filenames. Missing or corrupted dependencies fail validation before replacing
an active document. A complete staged bundle is compiled before atomic directory
rename. Failed operations remove staging files and leave published bundles intact.

Legacy `.gmj.json` files remain supported by **Open document** and still need their
original absolute assets until **Save project model** successfully migrates them.
Do not infer that changing the filename makes an old JSON document portable.
Source includes are archived and flattened into canonical MJCF; their old relative
layout is not used at runtime. Additional dependency classes unsupported by the
existing preview remain explicitly rejected.

## Implementation boundary

`MjEditorDocument.asset_manifest`, `portable_snapshot` and `restore_at` enumerate,
rewrite and validate canonical XML asset attributes, including cube texture faces.
All native string operations cross MuJoCo's C API. Do not dereference an mjStringVec
as a host GCC STL container: the pinned prebuilt library has a different C++
container representation. This was caught with a native backtrace during development.

`package_builder.gd` is usable by editor tools and automated build scripts;
`model_resource.gd` validates dependency hashes and creates independent native
preview documents. Each document owns its own model/data; resource snapshots are
never mutated by a preview.

## Asset acceptance

```sh
source /workspace/shared/tools/env.sh
OUT=/tmp/gmj-portable-new tests/portable_runtime/run_assets.sh
```

This checks includes, duplicate imports, same-label/different-content packages,
same-basename/different-byte meshes, missing-source rollback and missing-packaged
asset diagnostics. It copies the entire project without `.godot`, renames BOTH
original source directories and the original project out of the recorded paths,
then cold-imports and advances the relocated model using MuJoCo. Neither the
original absolute assets nor original project are available during this test.

Runtime scene integration is the next phase of this same milestone; this asset
checkpoint by itself does not claim shared-space runtime scene support.
