#!/usr/bin/env python3
"""Bounded independent GUI, portable, and runtime-pressure trials."""
import argparse,concurrent.futures,json,os,pathlib,shutil,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--source',type=pathlib.Path,required=True);p.add_argument('--out',type=pathlib.Path,required=True);a=p.parse_args();a.out.mkdir(parents=True,exist_ok=False)
manifest=json.loads((a.out.parent/'frozen-manifest.json').read_text());rows=[];cpus=sorted(os.sched_getaffinity(0));groups=[cpus[:2],cpus[2:4] or cpus[:2]]
def run(kind,index,slot):
 d=a.out/f'{kind}-{index}';d.mkdir();env=os.environ.copy();env['OUT']=str(d)
 for key,suffix in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:env[key]=str(d/'env'/suffix);pathlib.Path(env[key]).mkdir(parents=True)
 prefix=['nice','-n','10','taskset','-c',','.join(map(str,groups[slot]))];commands=[]
 def execute(label,cmd,limit=600):
  command=['timeout','--kill-after=5',str(limit)]+prefix+cmd;start=time.monotonic()
  with (d/(label+'.log')).open('w') as f:r=subprocess.run(command,cwd=a.source,env=env,stdout=f,stderr=subprocess.STDOUT)
  record={'label':label,'command':command,'exit':r.returncode,'shell_exit':128-r.returncode if r.returncode<0 else r.returncode,'seconds':round(time.monotonic()-start,3)};commands.append(record);(d/'commands.json').write_text(json.dumps(commands,indent=2));return r.returncode
 if kind in ['assets','runtime']:
  rc=execute('runner',[str(a.source/f'tests/portable_runtime/run_{kind}.sh')])
  if kind=='runtime' and rc==0:
   project=d/'relocated';shutil.copy2(pathlib.Path(__file__).parent/'runtime_pressure.gd',project/'runtime_pressure.gd')
   rc=execute('pressure',['godot','--headless','--path',str(project),'--script','res://runtime_pressure.gd'],300)
   if rc==0:
    text=(d/'pressure.log').read_text();result=json.loads(next(x.split(' ',1)[1] for x in text.splitlines() if x.startswith('PRESSURE_RESULT ')));rc=0 if result['failed']==0 and 'ERROR:' not in text and 'leaked' not in text else 1
 else:
  project=d/'project';shutil.copytree(a.source/'tests/editor_plugin',project);shutil.copytree(a.source/'demo/addons',project/'addons');assert not(project/'.godot').exists()
  rc=execute('import',[str(a.source/'scripts/import_headless.sh'),str(project)],120)
  if rc==0:
   env['DISPLAY']=':97';env['LIBGL_ALWAYS_SOFTWARE']='1'
   rc=execute('editor',['godot','--editor','--path',str(project),'--rendering-method','gl_compatibility','--audio-driver','Dummy','--resolution','1600x1000','--','--mj-editor-test','--report='+str(d/'results.json')],180)
   if rc==0:
    result=json.loads((d/'results.json').read_text());text=(d/'editor.log').read_text();host_errors={'ERROR: Required Vulkan instance extension VK_KHR_surface not found.','ERROR: Condition \"err != OK\" is true. Returning: err'};unexpected=[line for line in text.splitlines() if 'ERROR:' in line and line not in host_errors];rc=0 if result['failed']==0 and not unexpected and 'leaked' not in text else 1
 record={'kind':kind,'index':index,'exit':rc,'commands':commands,'source_commit':manifest['remote_commit'],'source_tree':manifest['tree'],'engine_sha256':manifest['engine_sha256'],'extension_sha256':manifest['extension_sha256'],'private_xdg':{k:v for k,v in env.items() if k.startswith('XDG_')}};(d/'trial.json').write_text(json.dumps(record,indent=2));print(json.dumps({'kind':kind,'index':index,'exit':rc}),flush=True);return record
jobs=[('runtime',i) for i in range(3)]+[('assets',i) for i in range(3)]+[('gui',i) for i in range(5)]
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 for n in range(0,len(jobs),2):
  batch=jobs[n:n+2];rows.extend(pool.map(lambda args:run(*args),[(kind,i,slot) for slot,(kind,i) in enumerate(batch)]));(a.out/'results.json').write_text(json.dumps(rows,indent=2))
