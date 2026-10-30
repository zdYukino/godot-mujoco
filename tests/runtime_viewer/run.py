#!/usr/bin/env python3
"""Isolated shared-viewer acceptance on real Godot, optionally native GLX."""
import argparse,hashlib,json,os,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--out',required=True,type=Path)
p.add_argument('--godot',default=os.environ.get('GODOT_BIN','godot'))
p.add_argument('--native',action='store_true')
p.add_argument('--headless',action='store_true')
scope=p.add_mutually_exclusive_group()
scope.add_argument('--ui-only',action='store_true',help='Fast UI-only smoke without keyframe/physics regressions; not full acceptance')
scope.add_argument('--analysis-only',action='store_true',help='Capture live integrated Profiler and Sensors; not full acceptance')
scope.add_argument('--bindings-only',action='store_true',help='Probe stale model-bound controls across real rebinds and commits; not full acceptance')
p.add_argument('--install',type=Path)
a=p.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
project=out/'project';project.mkdir(exist_ok=True)
for source in Path(__file__).parent.iterdir():
    if source.suffix in ('.godot','.gd'):shutil.copy2(source,project/source.name)
shutil.copytree(ROOT/'addons',project/'addons',dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.uid'))
hashes={}
for relative in ('addons/godot_mujoco/viewer/plot.gd','addons/godot_mujoco/viewer/runtime_viewer.gd'):
    hashes[relative]=hashlib.sha256((project/relative).read_bytes()).hexdigest()
(out/'source-hashes.json').write_text(json.dumps(hashes,indent=2)+'\n')
if a.install:
    shutil.copytree(a.install/'bin',project/'addons/godot_mujoco/bin',dirs_exist_ok=True)
    native=project/'addons/godot_mujoco/native_view/bin'
    if native.exists():shutil.rmtree(native)
    if (a.install/'native_view/bin').exists():shutil.copytree(a.install/'native_view/bin',native)
env=os.environ.copy();env.setdefault('DISPLAY',':0');env.setdefault('XAUTHORITY','/run/user/1000/gdm/Xauthority')
env['GMJ_VIEWER_OUT']=str(out)
if (ROOT/'third_party/dotnet').is_dir(): env.setdefault('DOTNET_ROOT',str(ROOT/'third_party/dotnet'))
for key in ('XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME'):
    d=out/key;d.mkdir(exist_ok=True);env[key]=str(d)
user_args=(['--native'] if a.native else [])+(['--ui-only'] if a.ui_only else [])+(['--analysis-only'] if a.analysis_only else [])+(['--bindings-only'] if a.bindings_only else [])
commands=[('import',['--headless','--editor','--import','--frame-delay','1000']),('runtime',(['--headless'] if a.headless else [])+['--script','res://acceptance.gd']+(['--',*user_args] if user_args else []))]
for name,flags in commands:
    with (out/(name+'.log')).open('w') as f:
        r=subprocess.run([a.godot,'--path',str(project),'--rendering-method','gl_compatibility','--audio-driver','Dummy',*flags],env=env,stdout=f,stderr=subprocess.STDOUT,timeout=360)
    content=(out/(name+'.log')).read_text(errors='replace')
    errors=[line for line in content.splitlines() if any(s in line for s in ('SCRIPT ERROR:','ERROR:','leaked','received signal','Unicode parsing error'))]
    print(name,r.returncode,errors[:10],flush=True)
    if r.returncode or errors:
        print(content[-14000:]);raise SystemExit(1)
print('PASS',out)
