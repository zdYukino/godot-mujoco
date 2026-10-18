#!/usr/bin/env python3
"""One-shot fresh import matrix. Run after sourcing the fixed toolchain env."""
import argparse,concurrent.futures,hashlib,json,os,pathlib,shutil,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--source',type=pathlib.Path,required=True);p.add_argument('--out',type=pathlib.Path,required=True);a=p.parse_args()
a.out.mkdir(parents=True,exist_ok=False)
godot=os.environ.get('GODOT_BIN','godot');cpus=sorted(os.sched_getaffinity(0));groups=[cpus[:2],cpus[2:4] or cpus[:2]]
manifest=json.loads((a.out.parent/'frozen-manifest.json').read_text());rows=[]
def trial(mode,index,slot=0):
 d=a.out/f'{mode}-{index:02}';d.mkdir();project=d/'project';project.mkdir()
 shutil.copytree(a.source/'demo/addons',project/'addons');shutil.copytree(a.source/'tests/portable_runtime',project,dirs_exist_ok=True)
 assert not (project/'.godot').exists()
 env=os.environ.copy()
 for key,suffix in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
  env[key]=str(d/'env'/suffix);pathlib.Path(env[key]).mkdir(parents=True)
 command=[str(a.source/'scripts/import_headless.sh'),str(project)] if mode!='official' else [godot,'--headless','--editor','--path',str(project),'--import']
 command=['nice','-n','10','taskset','-c',','.join(map(str,groups[slot]))]+command
 record={'mode':mode,'index':index,'command':command,'cwd':str(a.source),'fresh_project_cache':True,'private_xdg':{k:env[k] for k in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']},'source_commit':manifest['remote_commit'],'source_tree':manifest['tree'],'engine_sha256':manifest['engine_sha256'],'extension_sha256':manifest['extension_sha256']}
 (d/'command.json').write_text(json.dumps(record,indent=2)+'\n');start=time.monotonic()
 with (d/'import.log').open('w') as log:
  try:r=subprocess.run(['timeout','--kill-after=5','120']+command,cwd=a.source,env=env,stdout=log,stderr=subprocess.STDOUT);rc=r.returncode
  except Exception as e:rc=255;log.write(repr(e))
 text=(d/'import.log').read_text(errors='replace');record.update(returncode=rc,shell_exit=128-rc if rc<0 else rc,seconds=round(time.monotonic()-start,3),log=str(d/'import.log'),passed=rc==0 and 'ERROR:' not in text and 'leaked' not in text)
 (d/'result.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps({k:record[k] for k in ['mode','index','shell_exit','passed','seconds']}),flush=True);return record
# Two matching crash statuses reproduce an already watchpoint-diagnosed defect.
# Stop each mode separately; the other modes remain independent experiments.
plans=[('official',3),('sequential',20)]
for mode,count in plans:
 crashes=0
 for i in range(count):
  r=trial(mode,i);rows.append(r);crashes+=r['shell_exit']==139
  if crashes>=2:
   rows.append({'mode':mode,'skipped':count-i-1,'reason':'two fresh SIGSEGVs; prior same-binary native watchpoint evidence retained'});break
crashes=0
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 for i in range(0,10,2):
  batch=list(pool.map(lambda args:trial(*args),[('parallel',i,0),('parallel',i+1,1)]));rows.extend(batch);crashes+=sum(x['shell_exit']==139 for x in batch)
  if crashes>=2:
   rows.append({'mode':'parallel','skipped':10-i-2,'reason':'two fresh SIGSEGVs under bounded pair load'});break
(a.out/'results.json').write_text(json.dumps(rows,indent=2)+'\n')

raise SystemExit(1 if any(not row.get("passed", True) for row in rows) else 0)
