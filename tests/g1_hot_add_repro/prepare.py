#!/usr/bin/env python3
"""Extract existing snapshots verbatim; copy only referenced assets, never re-import."""
import argparse, hashlib, json, pathlib, shutil, subprocess, xml.etree.ElementTree as ET
p=argparse.ArgumentParser();p.add_argument('--out',type=pathlib.Path,required=True);p.add_argument('--sdk',type=pathlib.Path,required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2];out=a.out.resolve()
if out.exists(): raise SystemExit('Use a fresh --out; existing evidence is never overwritten')
out.mkdir(parents=True);project=out/'project';project.mkdir();manifest={}
for name,pattern in [('floor','gallery_floor_*'),('g1','passive_g1_*')]:
 package=next((root/'examples/g1_passive/models').glob(pattern));source=package/'model.tres'
 snapshot,_=json.JSONDecoder(strict=False).raw_decode(source.read_text().split('snapshot = ',1)[1])
 target=project/name;target.mkdir();(target/'model.xml').write_text(snapshot['xml']);(target/'snapshot.json').write_text(json.dumps(snapshot))
 for elem in ET.fromstring(snapshot['xml']).iter():
  if 'file' not in elem.attrib: continue
  rel=pathlib.Path(elem.attrib['file']);assert not rel.is_absolute() and '..' not in rel.parts
  src=package/rel;dst=target/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
  manifest[str(dst.relative_to(project))]=hashlib.sha256(dst.read_bytes()).hexdigest()
 manifest[str(target.relative_to(project)/'model.xml')]=hashlib.sha256((target/'model.xml').read_bytes()).hexdigest()
addon=project/'addons/godot_mujoco';(addon/'bin').mkdir(parents=True)
source=root/'demo/addons/godot_mujoco';shutil.copyfile(source/'godot_mujoco.gdextension',addon/'godot_mujoco.gdextension')
for name in ['libgodot_mujoco.linux.template_debug.x86_64.so','libmujoco.so.3.16.0']:
 shutil.copyfile(source/'bin'/name,addon/'bin'/name);manifest[name]=hashlib.sha256((addon/'bin'/name).read_bytes()).hexdigest()
(project/'.godot').mkdir();(project/'.godot/extension_list.cfg').write_text('res://addons/godot_mujoco/godot_mujoco.gdextension\n')
for name in ['project.godot','runtime.gd']: shutil.copyfile(pathlib.Path(__file__).parent/name,project/name)
for name in ['UPSTREAM_LICENSE','upstream-manifest.json']: shutil.copyfile(root/'examples/g1_passive'/name,out/name)
manifest['base_commit']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
manifest['sdk_library_sha256']=hashlib.sha256((a.sdk/'lib/libmujoco.so.3.16.0').read_bytes()).hexdigest()
assert manifest['sdk_library_sha256']==manifest['libmujoco.so.3.16.0'],'SDK and staged on-disk library hashes differ'
manifest['library_identity_scope']='On-disk SDK and staged files only; actual runtime loader resolution is not verified.'
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
subprocess.run(['c++','-std=c++17','-O0','-g','-I'+str(a.sdk/'include'),'-I'+str(root/'src/physics'),str(pathlib.Path(__file__).parent/'native.cpp'),'-L'+str(a.sdk/'lib'),'-Wl,-rpath,'+str(a.sdk/'lib'),'-lmujoco','-o',str(out/'native')],check=True)
print(out)
