#!/usr/bin/env python3
"""One bounded child process group; never attaches to or stops other processes."""
import argparse,json,os,pathlib,signal,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--log',type=pathlib.Path,required=True);p.add_argument('--seconds',type=float,default=45);p.add_argument('--min-available-mib',type=int,default=400);p.add_argument('--max-rss-mib',type=int,default=1800);p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args();cmd=a.command
if cmd and cmd[0]=='--':cmd=cmd[1:]
if not cmd: p.error('command required')
def available():
 return int(next(x.split()[1] for x in pathlib.Path('/proc/meminfo').read_text().splitlines() if x.startswith('MemAvailable:')))
if available()<768*1024:raise SystemExit('Not started: less than 768 MiB available')
def cgroup_snapshot():
 result={}
 # Record the observer's current cgroup, inherited by its new child.
 try:
  rel=next(x.split(':',2)[2] for x in pathlib.Path('/proc/self/cgroup').read_text().splitlines() if x.startswith('0::'))
  base=pathlib.Path('/sys/fs/cgroup')/rel.lstrip('/')
  for name in ['memory.current','memory.events','memory.pressure','io.pressure','cpu.pressure']:
   try:result[str(base/name)]=(base/name).read_text()
   except OSError as e:result[str(base/name)]=str(e)
 except (OSError,StopIteration) as e:result['unavailable']=str(e)
 return result
start=time.monotonic();peak=0;low=available();reason='completed';samples=[];last_sample=-5;cg_before=cgroup_snapshot()
with a.log.open('x') as log:
 child=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
 while child.poll() is None:
  low=min(low,available())
  try:
   status=pathlib.Path(f'/proc/{child.pid}/status').read_text();rss=int(next(x.split()[1] for x in status.splitlines() if x.startswith('VmRSS:')));peak=max(peak,rss)
  except (FileNotFoundError,StopIteration): pass
  elapsed=time.monotonic()-start
  if elapsed-last_sample>=5:
   row={'elapsed':elapsed,'threads':{}}
   try:
    for task in pathlib.Path(f'/proc/{child.pid}/task').iterdir():
     try:
      fields=(task/'stat').read_text().rsplit(')',1)[1].split()
      row['threads'][task.name]={'state':fields[0],'utime_ticks':int(fields[11]),'stime_ticks':int(fields[12]),'wchan':(task/'wchan').read_text().strip()}
     except OSError: pass
   except FileNotFoundError:pass
   samples.append(row);last_sample=elapsed
  if elapsed>=a.seconds:reason='timeout' 
  elif low<a.min_available_mib*1024:reason='low_available_memory'
  elif peak>a.max_rss_mib*1024:reason='rss_limit'
  if reason!='completed':
   try:os.killpg(child.pid,signal.SIGINT)
   except ProcessLookupError:pass
   try:child.wait(timeout=3)
   except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);child.wait()
   break
  time.sleep(.1)
 result={'command':cmd,'elapsed_seconds':time.monotonic()-start,'exit':child.wait(),'reason':reason,'peak_sampled_rss_kib':peak,'lowest_available_kib':low,'cpu_thread_samples':samples,'cgroup_before':cg_before,'cgroup_after':cgroup_snapshot()}
a.log.with_suffix('.resources.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k not in ['cpu_thread_samples','cgroup_before','cgroup_after']}));raise SystemExit(0 if result['exit']==0 and reason=='completed' else 1)
