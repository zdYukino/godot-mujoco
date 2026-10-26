#!/usr/bin/env python3
"""Lightweight monitor tests; no Godot, MuJoCo, assets or user processes."""
import json
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
OUT = pathlib.Path(tempfile.mkdtemp(prefix='gmj-monitor-test-'))
helper = OUT / 'child.py'
helper.write_text('''import json,os,pathlib,signal,subprocess,sys,time
p=pathlib.Path(sys.argv[1]);mode=sys.argv[2]
signal.signal(signal.SIGTERM,signal.SIG_IGN)
if mode=='clean': p.write_text(json.dumps([os.getpid()]));sys.exit(0)
c=subprocess.Popen([sys.executable,'-c','import signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);print("ready",flush=True);time.sleep(60)'],stdout=subprocess.PIPE,text=True)
c.stdout.readline()
p.write_text(json.dumps([os.getpid(),c.pid]))
if mode=='orphan':sys.exit(0)
time.sleep(60)
''')
results = []
# Sentinel is created by this test, in a different group; must remain untouched.
sentinel = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(60)'], start_new_session=True)
try:
    for case in ['normal', 'normal_orphan', 'timeout', 'interrupt', 'exception']:
        pids = OUT / (case + '.pids.json')
        log = OUT / (case + '.log')
        mode = 'clean' if case == 'normal' else 'orphan' if case == 'normal_orphan' else 'sleep'
        args = ['--log', str(log), '--seconds', '.5' if case == 'timeout' else '10', '--', sys.executable, str(helper), str(pids), mode]
        if case == 'exception':
            wrapper = OUT / 'inject.py'
            wrapper.write_text('''import sys,time,pathlib
sys.path.insert(0,sys.argv[1]);import bounded
count=0
def sample():
 global count
 count+=1
 if count>1:
  deadline=time.monotonic()+3
  while not pathlib.Path(sys.argv[2]).exists() and time.monotonic()<deadline:time.sleep(.01)
  raise OSError('injected /proc read failure')
 return 10000000
raise SystemExit(bounded.main(sys.argv[3:],memory_sample=sample))
''')
            cmd = [sys.executable, str(wrapper), str(HERE), str(pids)] + args
        else:
            cmd = [sys.executable, str(HERE / 'bounded.py')] + args
        with (OUT / (case + '.monitor.log')).open('w') as output:
            monitor = subprocess.Popen(cmd, stdout=output, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 5
                while not pids.exists() and time.monotonic() < deadline:
                    time.sleep(.02)
                assert pids.exists(), case
                if case == 'interrupt':
                    monitor.send_signal(signal.SIGTERM)
                code = monitor.wait(timeout=12)
                result = json.loads(log.with_suffix('.resources.json').read_text())
                expected = {'normal':'completed','normal_orphan':'completed','timeout':'timeout','interrupt':'monitor_interrupted','exception':'monitor_exception'}[case]
                assert result['reason'] == expected, result
                assert code == (0 if case.startswith('normal') else 1), result
                assert not result['cleanup']['remaining'] and not result['cleanup']['errors'], result
                assert all(not pathlib.Path(f'/proc/{pid}').exists() for pid in json.loads(pids.read_text())), case
                assert sentinel.poll() is None, 'unrelated group touched'
                if case != 'normal': assert 'SIGKILL' in result['cleanup']['signals'], result
                results.append({'case':case,'passed':True,'reason':result['reason'],'cleanup':result['cleanup']})
            finally:
                if monitor.poll() is None:
                    monitor.terminate();monitor.wait(timeout=10)
finally:
    sentinel.terminate();sentinel.wait(timeout=5)
(OUT / 'results.json').write_text(json.dumps(results, indent=2)+'\n')
print('MONITOR PASS',len(results),OUT)
