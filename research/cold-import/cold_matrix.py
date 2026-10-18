#!/usr/bin/env python3
"""Fresh directory imports; never retry, prewarm or hide a nonzero exit."""
import argparse,concurrent.futures,hashlib,json,os,pathlib,re,shutil,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--engine',required=True);p.add_argument('--source',type=pathlib.Path,required=True);p.add_argument('--minimal',type=pathlib.Path,required=True);p.add_argument('--out',type=pathlib.Path,required=True);p.add_argument('--kinds',default='empty,no_class,class,native,full');p.add_argument('--modes',default='official,helper');p.add_argument('--count',type=int,default=2);p.add_argument('--parallel',type=int,choices=[1,2],default=1);p.add_argument('--cpu-groups',default='3,4;3,4');p.add_argument('--stop-after-crashes',type=int,default=2);p.add_argument('--load-note',default='No concurrent engine build');a=p.parse_args();a.out.mkdir(parents=True,exist_ok=False);groups=a.cpu_groups.split(';');rows=[]
def trial(kind,mode,index,slot):
 d=a.out/f'{kind}-{mode}-{index:02}';project=d/'project';project.mkdir(parents=True);env=os.environ.copy();env['GODOT_BIN']=a.engine
 for key,suffix in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:env[key]=str(d/'env'/suffix);pathlib.Path(env[key]).mkdir(parents=True)
 (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Cold import research"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
 if kind in ['class','no_class']:
  shutil.copy2(a.minimal/f'libcold_probe_{kind}.so',project/'libcold_probe.so');(project/'probe.gdextension').write_text('[configuration]\nentry_symbol="cold_probe_init"\ncompatibility_minimum="4.5"\n[libraries]\nlinux.debug.x86_64="res://libcold_probe.so"\n')
 elif kind in ['native','full']:
  shutil.copytree(a.source/'demo/addons/godot_mujoco',project/'addons/godot_mujoco')
  if kind=='native':
   # Only the native descriptor/library: no model runtime or editor scripts.
   shutil.rmtree(project/'addons/godot_mujoco/model')
  else:
   shutil.copytree(a.source/'demo/addons/mujoco_editor',project/'addons/mujoco_editor');shutil.copytree(a.source/'tests/portable_runtime',project,dirs_exist_ok=True);shutil.copytree(a.source/'demo/assets',project/'assets')
 (project/'probe.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16" fill="#33aaff"/></svg>')
 (project/'probe_script.gd').write_text('class_name ColdImportScript\nextends RefCounted\nfunc answer(): return 42\n')
 assert not(project/'.godot').exists()
 if kind in ['native','full']:assert (project/'addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').exists(), 'Stage the built extension before running this layer'
 args=[a.engine,'--headless','--editor','--path',str(project),'--import'] if mode=='official' else [str(a.source/'scripts/import_headless.sh'),str(project)]
 command=['timeout','--kill-after=5','180','nice','-n','10','taskset','-c',groups[slot]]+args;start=time.monotonic()
 record={'kind':kind,'mode':mode,'index':index,'command':command,'engine_sha256':hashlib.sha256(pathlib.Path(a.engine).read_bytes()).hexdigest(),'fresh_dot_godot':True,'private_xdg':{k:env[k] for k in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']},'load_note':a.load_note,'extension_hashes':{str(f.relative_to(project)):hashlib.sha256(f.read_bytes()).hexdigest() for f in project.rglob('*.so')}}
 (d/'command.json').write_text(json.dumps(record,indent=2))
 with (d/'import.log').open('w') as f:r=subprocess.run(command,cwd=a.source,env=env,stdout=f,stderr=subprocess.STDOUT)
 text=(d/'import.log').read_text(errors='replace');cache=project/'.godot/global_script_class_cache.cfg';cachetext=cache.read_text() if cache.exists() else '';expected=[]
 for script in project.rglob('*.gd'):expected+=re.findall(r'^class_name\s+(\w+)',script.read_text(),re.M)
 missing=[name for name in expected if '"'+name+'"' not in cachetext];textures=list((project/'.godot/imported').glob('probe.svg-*.ctex'));errors=[l for l in text.splitlines() if 'ERROR:' in l or 'leaked' in l];artifacts=bool(textures) and all(f.stat().st_size>16 for f in textures) and not missing
 record.update(exit=r.returncode,shell_exit=128-r.returncode if r.returncode<0 else r.returncode,seconds=round(time.monotonic()-start,3),expected_script_classes=expected,missing_script_classes=missing,texture_artifacts=[str(f.relative_to(project)) for f in textures],artifacts_complete=artifacts,errors=errors,passed=r.returncode==0 and artifacts and not errors,log_sha256=hashlib.sha256((d/'import.log').read_bytes()).hexdigest());(d/'result.json').write_text(json.dumps(record,indent=2));print(json.dumps({k:record[k] for k in ['kind','mode','index','shell_exit','artifacts_complete','passed']}),flush=True);return record
with concurrent.futures.ThreadPoolExecutor(max_workers=a.parallel) as pool:
 for kind in a.kinds.split(','):
  for mode in a.modes.split(','):
   crashes=0
   for i in range(0,a.count,a.parallel):
    batch=list(pool.map(lambda x:trial(*x),[(kind,mode,j,slot) for slot,j in enumerate(range(i,min(i+a.parallel,a.count)))]));rows.extend(batch);crashes+=sum(x['shell_exit']==139 for x in batch)
    (a.out/'results.json').write_text(json.dumps(rows,indent=2))
    if a.stop_after_crashes and crashes>=a.stop_after_crashes:
     rows.append({'kind':kind,'mode':mode,'skipped':a.count-i-len(batch),'reason':'demonstrated SIGSEGV stop rule'});break
(a.out/'results.json').write_text(json.dumps(rows,indent=2));raise SystemExit(1 if any(not r.get('passed',True) for r in rows) else 0)
