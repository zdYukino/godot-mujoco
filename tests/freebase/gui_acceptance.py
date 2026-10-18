"""真实 XTEST 输入：G1 运行控件、状态重置、环境事务与接触摩擦。"""
import sys,pathlib,time,json
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'editor_plugin'))
import mouse_acceptance as m
s=m.state

def button(suffix):
 m.click(next(c['rect'] for c in s()['controls'] if c['text'].endswith(suffix)))
def step(n):
 m.click(s()['count']);m.type_text(str(n));m.key('Return');button('Step N');time.sleep(.3)
def rebuild(mode):
 before=s()['world_id'];button('Fixture '+mode);button('重建已保存环境：丢弃运行时增删')
 for _ in range(100):
  st=s()
  if (mode=='invalid' and 'Environment rebuild failed' in st['status']) or (mode!='invalid' and st['world_id']!=before and st['time']==0 and 'Environment rebuild succeeded' in st['status']):return
  time.sleep(.1)
 raise RuntimeError('rebuild completion not observed: '+mode)
def capture(name):m.shot(name)
def main():
 m.wait_window()
 for _ in range(200):
  if (m.folder/'state.json').exists():break
  time.sleep(.2)
 a=s();time.sleep(.6);m.check(s()['paused'] and s()['time']==a['time'] and s()['game_elapsed']>a['game_elapsed'],'UI time continues while G1 physics paused');capture('01-paused')
 step(9);m.check(abs(s()['time']-.018)<1e-10 and s()['paused'],'actual Step9 exactly 0.018 seconds');capture('02-step9')
 button('Capture');a=s();button('Resume');time.sleep(1);button('Pause');m.check(s()['time']>a['time'] and s()['paused'],'actual Resume and Pause');capture('03-running-then-paused')
 button('Reset state');m.check(abs(s()['time']-a['time'])<1e-10 and s()['qpos']==a['qpos'],'actual snapshot Reset restores qpos and time');capture('04-reset')
 before=s();rebuild('invalid');m.check(s()['world_id']==before['world_id'] and s()['qpos']==before['qpos'] and s()['time']==before['time'] and 'Environment rebuild failed' in s()['status'],'invalid candidate visible failure and unchanged old world');capture('05-rebuild-failed')
 rebuild('original');m.check(s()['world_id']!=before['world_id'] and s()['time']==0 and s()['paused'] and 'Environment rebuild succeeded' in s()['status'],'valid retry replaces world and preserves pause');capture('06-rebuild-success')
 travel={}
 for mode in ['low','high','barrier']:
  rebuild(mode);m.check(s()['time']==0 and s()['paused'],'fresh contact environment '+mode)
  # 分段精确步进，记录脚底接触与障碍碰撞，避免依赖帧率。
  step(10);step(40);step(50)
  for _ in range(18):button("Step N")
  st=s();travel[mode]=st['travel'];m.check(abs(st['time']-2.0)<1e-10,'1000 exact steps '+mode);m.check(st['contact_seen'],'G1 sole physical contact '+mode);m.check(st['finite'] and st['warnings']==0 and st['deepest']>-.04,'finite contact state and penetration bound '+mode)
  if mode=='barrier':m.check(st['barrier_seen'],'G1 collision with ordinary Godot barrier')
  capture('07-contact-'+mode)
 m.check(travel['low']>travel['high']+.05,'lower friction slides further: '+str(travel))
 (m.folder/'measurements.json').write_text(json.dumps(travel,indent=2))
if __name__=='__main__':
 try:
  main()
  if not all(c['passed'] for c in m.checks):raise SystemExit(1)
 finally:
  (m.folder/'mouse-results.json').write_text(json.dumps(m.checks,indent=2));(m.folder/'quit').touch()
