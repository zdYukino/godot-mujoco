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
scope.add_argument('--split-only',action='store_true',help='Four independently optional component combinations and cross-role lifetime')
scope.add_argument('--saved-scenes-only',action='store_true',help='Nested scene/data freshness with stable executing Script identity and scoped loader cleanup')
scope.add_argument('--layout-diagnostic',action='store_true',help='Stop after the first actual Tab layout transition with full state diagnostics')
scope.add_argument('--contract-only',action='store_true',help='Saved custom UI, policy, layout and per-component preferences')
scope.add_argument('--component-only',action='store_true',help='Real no-UI/component lifecycle and gameplay-camera regression')
scope.add_argument('--ui-only',action='store_true',help='Fast UI-only smoke without keyframe/physics regressions; not full acceptance')
scope.add_argument('--analysis-only',action='store_true',help='Capture live integrated Profiler and Sensors; not full acceptance')
scope.add_argument('--bindings-only',action='store_true',help='Probe stale model-bound controls across real rebinds and commits; not full acceptance')
p.add_argument('--install',type=Path)
a=p.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
project=out/'project';project.mkdir(exist_ok=True)
for source in Path(__file__).parent.iterdir():
    if source.suffix in ('.godot','.gd','.tscn','.tres'):shutil.copy2(source,project/source.name)
shutil.copytree(ROOT/'addons',project/'addons',dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.uid'))
if a.install:
    shutil.copytree(a.install/'bin',project/'addons/godot_mujoco/bin',dirs_exist_ok=True)
    native=project/'addons/godot_mujoco/native_view/bin'
    if native.exists():shutil.rmtree(native)
    if (a.install/'native_view/bin').exists():shutil.copytree(a.install/'native_view/bin',native)
# Record the exact fixture, implementation and installed binary snapshot. In
# particular OFF hashes must describe binaries after the --install overlay.
critical = [
    'addons/godot_mujoco/viewer/runtime_viewer.gd',
    'addons/godot_mujoco/viewer/runtime_client.gd',
    'addons/godot_mujoco/viewer/ui_base.gd',
    'addons/godot_mujoco/viewer/shortcuts.gd',
    'addons/godot_mujoco/viewer/godot_extras.gd',
    'addons/godot_mujoco/viewer/extras_ui.gd',
    'addons/godot_mujoco/viewer/extras_ui.tscn',
    'addons/godot_mujoco/viewer/viewer_session.gd',
    'addons/godot_mujoco/viewer/viewer_ui.gd',
    'addons/godot_mujoco/viewer/default_ui.tscn',
    'addons/godot_mujoco/viewer/configuration.gd',
    'addons/godot_mujoco/viewer/extension_binding.gd',
    'addons/godot_mujoco/model/scene_builder.gd',
    'addons/godot_mujoco/model/saved_scene_loader.gd',
    'addons/godot_mujoco/viewer/plot.gd',
    'addons/godot_mujoco/model/runtime_world.gd',
    'addons/godot_mujoco/model/environment_host.gd',
    'addons/godot_mujoco/native_view/runtime_view.gd',
    *[p.name for p in Path(__file__).parent.iterdir() if p.suffix in ('.gd','.godot','.tscn','.tres')],
    *[str(p.relative_to(project)) for p in (project/'addons').rglob('*.so*')],
]
hashes={relative:hashlib.sha256((project/relative).read_bytes()).hexdigest() for relative in sorted(set(critical))}
hashes['@runner/run.py']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
(out/'source-hashes.json').write_text(json.dumps(hashes,indent=2)+'\n')
env=os.environ.copy();env.setdefault('DISPLAY',':0');env.setdefault('XAUTHORITY','/run/user/1000/gdm/Xauthority')
env['GMJ_VIEWER_OUT']=str(out)
if (ROOT/'third_party/dotnet').is_dir(): env.setdefault('DOTNET_ROOT',str(ROOT/'third_party/dotnet'))
for key in ('XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME'):
    d=out/key;d.mkdir(exist_ok=True);env[key]=str(d)
user_args=(['--native'] if a.native else [])+(['--ui-only'] if a.ui_only else [])+(['--analysis-only'] if a.analysis_only else [])+(['--bindings-only'] if a.bindings_only else [])+(['--component-only'] if a.component_only else [])+(['--contract-only'] if a.contract_only else [])+(['--layout-diagnostic'] if a.layout_diagnostic else [])+(['--saved-scenes-only'] if a.saved_scenes_only else [])+(['--split-only'] if a.split_only else [])
commands=[('import',['--headless','--editor','--import','--frame-delay','1000']),('runtime',(['--headless'] if a.headless else [])+['--script','res://acceptance.gd']+(['--',*user_args] if user_args else []))]
for name,flags in commands:
    with (out/(name+'.log')).open('w') as f:
        r=subprocess.run([a.godot,'--path',str(project),'--rendering-method','gl_compatibility','--audio-driver','Dummy',*flags],env=env,stdout=f,stderr=subprocess.STDOUT,timeout=360)
    content=(out/(name+'.log')).read_text(errors='replace')
    errors=[line for line in content.splitlines() if any(s in line for s in ('SCRIPT ERROR:','ERROR:','leaked','received signal','Unicode parsing error'))]
    # Each deliberately invalid configuration must have its own exact passed
    # rejection assertion. Never ignore arbitrary viewer/script/GL errors.
    expected_cases = {
        'ERROR: MjGodotExtras: This target viewport already has Godot Extras': 'duplicate Extras reports failure without hijacking either active role',
        'ERROR: MjRuntimeViewer: This target viewport already has an interactive viewer': 'duplicate target reports failure without hijacking the active component',
        'ERROR: MjRuntimeViewer: Target is not an MjRuntimeWorld.': 'wrong explicit target reports a reason without hijacking the active component',
        'ERROR: MjRuntimeViewer: UI scene must declare a valid render_region Control.': 'missing custom render region is rejected without silent default UI',
        'ERROR: MjRuntimeViewer: UI render_region must be a positive rectangle inside the target viewport.': 'out-of-bounds custom region is rejected without silent default UI',
    }
    if name=='runtime' and (a.component_only or a.split_only):
        report_file=out/('report-native.json' if a.native else 'report-godot.json')
        report=json.loads(report_file.read_text()) if report_file.exists() else {}
        expected_records=[]
        for message, assertion in expected_cases.items():
            count=sum(line.strip()==message for line in errors)
            rejected=any(row.get('passed') and row.get('name')==assertion for row in report.get('checks',[]))
            if count==1 and rejected:
                errors=[line for line in errors if line.strip()!=message]
                expected_records.append({'message':message,'count':count,'assertion':assertion})
        if expected_records:
            (out/'expected-configuration-errors.json').write_text(json.dumps(expected_records,indent=2)+'\n')

    print(name,r.returncode,errors[:10],flush=True)
    if r.returncode or errors:
        print(content[-14000:]);raise SystemExit(1)
print('PASS',out)
