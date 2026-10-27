#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
: "${GODOT_BIN:=godot}"
: "${OUT:=$(mktemp -d /tmp/gmj-shape-gallery.XXXXXX)}"
python3 - "$ROOT/examples/shape_gallery/assets" <<'PYASSET'
import hashlib,pathlib,sys
p=pathlib.Path(sys.argv[1]); hdr=p/'kloofendal_43d_clear_puresky_4k.hdr'
assert hashlib.sha256(hdr.read_bytes()).hexdigest()=='1f92cbf17e46659ff37c9770d065280da226896b0f56091c4c1fca071da7fbeb'
settings=hdr.with_suffix('.hdr.import').read_text()
for key in ['compress/mode','compress/hdr_compression','detect_3d/compress_to']:
 assert key+'=0\n' in settings,key
PYASSET
mkdir -p "$OUT/project"
# Exclude the shared addon symlink and editor cache from isolated fixtures.
python3 - "$ROOT/examples/shape_gallery" "$OUT/project" <<'PYCOPY'
import shutil, sys
shutil.copytree(sys.argv[1], sys.argv[2], dirs_exist_ok=True,
                ignore=shutil.ignore_patterns("addons", ".godot", ".godot.*"))
PYCOPY
cp -a "$ROOT/addons" "$OUT/project/"
cp "$ROOT/tests/shape_gallery/acceptance.gd" "$OUT/project/"
timeout --kill-after=5 120 bash "$ROOT/scripts/import_headless.sh" "$OUT/project" > "$OUT/import.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://acceptance.gd > "$OUT/shipped.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://prepare.gd > "$OUT/prepare.log" 2>&1
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://acceptance.gd > "$OUT/runtime.log" 2>&1
mv "$OUT/project/assets/gallery.xml" "$OUT/source-unavailable.xml"
timeout --kill-after=5 120 "$GODOT_BIN" --headless --path "$OUT/project" --script res://acceptance.gd > "$OUT/missing-source.log" 2>&1
mkdir -p "$OUT/project/addons/gallery_test"
cp "$ROOT/tests/shape_gallery/editor_plugin.gd" "$OUT/project/addons/gallery_test/"
cat > "$OUT/project/addons/gallery_test/plugin.cfg" <<'CFG'
[plugin]
name="Gallery test"
description="Isolated editor regression"
author="godot-mujoco"
version="1"
script="editor_plugin.gd"
CFG
python3 - "$OUT/project/project.godot" <<'PYPLUGIN'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);p.write_text(p.read_text().replace('"res://addons/mujoco_editor/plugin.cfg")','"res://addons/mujoco_editor/plugin.cfg", "res://addons/gallery_test/plugin.cfg")'))
PYPLUGIN
timeout --kill-after=5 120 "$GODOT_BIN" --headless --editor --path "$OUT/project" -- --grid-editor-test > "$OUT/editor.log" 2>&1
python3 - "$OUT" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);settings=(p/'project/assets/kloofendal_43d_clear_puresky_4k.hdr.import').read_text()
for key in ['compress/mode','compress/hdr_compression','detect_3d/compress_to']: assert key+'=0\n' in settings,key
s=(p/'runtime.log').read_text();rows=[x.split(' ',1)[1] for x in s.splitlines() if x.startswith('SHAPE_GALLERY_RESULT ')];assert len(rows)==1,s
r=json.loads(rows[0]);assert r['failed']==0,r
for name in ['shipped.log','missing-source.log']:
 rows=[x.split(' ',1)[1] for x in (p/name).read_text().splitlines() if x.startswith('SHAPE_GALLERY_RESULT ')];assert len(rows)==1,name
 result=json.loads(rows[0]);assert result['failed']==0,result
 r[name]=result
rows=[x.split(' ',1)[1] for x in (p/'editor.log').read_text().splitlines() if x.startswith('GALLERY_EDITOR_RESULT ')];assert len(rows)==1
r['editor']=json.loads(rows[0]);assert r['editor']['failed']==0
for f in p.glob('*.log'):
 s=f.read_text();assert 'SCRIPT ERROR:' not in s and '\nERROR:' not in s and 'leaked' not in s,str(f)
(p/'results.json').write_text(json.dumps(r,indent=2)+'\n');print('SHAPE GALLERY PASS',r,p)
PY
