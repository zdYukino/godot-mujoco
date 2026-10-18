#!/usr/bin/env python3
"""Explicit post-import coverage after fresh-XDG NuGet host initialization failure."""
import argparse,concurrent.futures,json,os,pathlib,shutil,subprocess,time
parser=argparse.ArgumentParser();parser.add_argument('--lifecycle',type=pathlib.Path,required=True);root=parser.parse_args().lifecycle
def run(i):
 d=root/f'runtime-{i}';p=d/'relocated';shutil.copy2(pathlib.Path(__file__).parent/'runtime_pressure.gd',p/'runtime_pressure.gd');rows=[]
 cmds=[('pressure',['godot','--headless','--path',str(p),'--script','res://runtime_pressure.gd']),('dotnet-shared-data',['dotnet','build',str(p/'PortableRuntime.csproj'),'-c','Debug']),('csharp',['godot','--headless','--path',str(p),'res://RuntimeBinding.tscn'])]
 for label,cmd in cmds:
  full=['timeout','--kill-after=5','300','nice','-n','10','taskset','-c','0,1' if i%2==0 else '2,3']+cmd;start=time.monotonic()
  with (d/(label+'-followup.log')).open('w') as log:r=subprocess.run(full,stdout=log,stderr=subprocess.STDOUT)
  text=(d/(label+'-followup.log')).read_text();valid=r.returncode==0 and 'ERROR:' not in text and 'leaked' not in text
  if label=='pressure' and valid:valid=json.loads(next(line.split(' ',1)[1] for line in text.splitlines() if line.startswith('PRESSURE_RESULT ')))['failed']==0
  if label=='csharp':valid=valid and 'PORTABLE CSHARP PASS' in text
  rows.append({'passed':valid,'label':label,'command':full,'exit':r.returncode,'seconds':round(time.monotonic()-start,3),'XDG_DATA_HOME':os.environ.get('XDG_DATA_HOME')});(d/'followup.json').write_text(json.dumps(rows,indent=2));print(json.dumps(rows[-1]),flush=True)
 return rows
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 list(pool.map(run,[0,1]));run(2)
