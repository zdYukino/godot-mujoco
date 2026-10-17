#!/usr/bin/env python3
"""Verify pinned original bytes and deterministically generate synthetic fixtures."""
import argparse, hashlib, json, pathlib, shutil, subprocess, xml.etree.ElementTree as ET
p=argparse.ArgumentParser();p.add_argument('--assets',type=pathlib.Path,required=True);p.add_argument('--out',type=pathlib.Path,required=True);p.add_argument('--native',type=pathlib.Path,required=True);a=p.parse_args()
src=a.assets.resolve();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
manifest=json.loads((src/'upstream-manifest.json').read_text())
for f in manifest['files']:
 b=(src/f['path']).read_bytes();assert hashlib.sha256(b).hexdigest()==f['sha256'],f['path'];assert hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==f['git_blob_sha1']
original=(src/'g1_29dof_mode_18.urdf').read_bytes();root=ET.fromstring(original)
assert len(root.findall('link'))==38
joints=[]
for j in root.findall('joint'):
 if j.get('type')=='revolute':
  x={'name':j.get('name')};x.update({k:float(v) for k,v in j.find('limit').attrib.items()});joints.append(x)
assert len(joints)==29 and sum(j.get('type')=='fixed' for j in root.findall('joint'))==8
assert len({m.get('filename') for m in root.iter('mesh')})==34
(out/'joint-inventory.json').write_text(json.dumps(joints,indent=2)+'\n')
(out/'joint-inventory.tsv').write_text(''.join(f"{j['name']} {j['lower']:.17g} {j['upper']:.17g} {j['effort']:.17g} {j['velocity']:.17g}\n" for j in joints))
# Byte-preserving single modification, including upstream CRLF.
needle=b'<compiler meshdir="meshes" discardvisual="false"/>';assert original.count(needle)==1
derived=original.replace(needle,b'<compiler meshdir="meshes" discardvisual="false" strippath="true"/>')
(out/'g1_29dof_mode_18.mujoco316.urdf').write_bytes(derived)
if (out/'meshes').exists():
 assert (out/'meshes').resolve()==(src/'meshes').resolve(), 'Use a fresh output directory'
else:(out/'meshes').symlink_to(src/'meshes',target_is_directory=True)
canonical=out/'canonical.xml'
subprocess.run([str(a.native.resolve()),'--canonical',str(out/'g1_29dof_mode_18.mujoco316.urdf'),str(canonical)],check=True,cwd='/tmp')
r=ET.parse(canonical).getroot();r.set('model','g1_29dof_mode_18_SYNTHETIC_ACTUATION_TEST')
c=r.find('compiler');c.set('meshdir','meshes')
opt=r.find('option')
if opt is None:opt=ET.SubElement(r,'option')
opt.set('timestep','0.001');opt.set('gravity','0 0 0');opt.set('integrator','implicitfast');ET.SubElement(opt,'flag',contact='disable')
by={j['name']:j for j in joints}
for j in r.iter('joint'):
 if j.get('name') in by:
  x=by[j.get('name')];j.set('range',f"{x['lower']:.17g} {x['upper']:.17g}")
act=ET.SubElement(r,'actuator')
for j in joints:
 ET.SubElement(act,'position',name=j['name']+'_position',joint=j['name'],gear='1',kp='10',kv='5',ctrllimited='true',ctrlrange=f"{j['lower']:.17g} {j['upper']:.17g}",forcelimited='true',forcerange=f"{-j['effort']:.17g} {j['effort']:.17g}")
ET.indent(r);ET.ElementTree(r).write(out/'actuation-test.xml',encoding='unicode',xml_declaration=False)
print('Verified 36 upstream blobs; generated derived URDF, inventory, synthetic actuation fixture')
