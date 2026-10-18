#!/usr/bin/env python3
"""Finish the separately labeled portable editor stages after SDK host recovery."""
import argparse,concurrent.futures,json,os,pathlib,shutil,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--lifecycle',type=pathlib.Path,required=True);p.add_argument('--source',type=pathlib.Path,required=True);a=p.parse_args()
def run(i):
 d=a.lifecycle/f'runtime-{i}';project=d/'relocated';shutil.copy2(a.source/'tests/portable_runtime/editor_acceptance.gd',project/'acceptance.gd');config=project/'project.godot';s=config.read_text();assert '[editor_plugins]' not in s;config.write_text(s+'\n[editor_plugins]\nenabled=PackedStringArray("res://addons/mujoco_editor/plugin.cfg")\n');rows=[]
 for label,args in [('editor',['--headless','--editor','--path',str(project),'--','--mj-editor-test']),('restart',['--headless','--path',str(project),'--script','res://restart_editor_scene.gd'])]:
  cmd=['timeout','--kill-after=5','120','nice','-n','10','taskset','-c','0,1' if i%2==0 else '2,3','godot']+args;start=time.monotonic()
  with (d/(label+'-followup.log')).open('w') as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
  text=(d/(label+'-followup.log')).read_text();valid=r.returncode==0 and 'ERROR:' not in text and 'leaked' not in text
  if label=='editor' and valid:valid=json.loads(next(line.split(' ',1)[1] for line in text.splitlines() if line.startswith('PORTABLE_EDITOR_RESULT ')))['failed']==0
  if label=='restart':valid=valid and 'EDITOR_SCENE_RESTART_PASS' in text
  rows.append({'passed':valid,'label':label,'command':cmd,'exit':r.returncode,'seconds':round(time.monotonic()-start,3)});(d/'editor-followup.json').write_text(json.dumps(rows,indent=2));print(json.dumps(rows[-1]),flush=True)
  if r.returncode:break
 return rows
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:batches=list(pool.map(run,[0,1]));batches.append(run(2))

raise SystemExit(1 if any(not row["passed"] for batch in batches for row in batch) else 0)
