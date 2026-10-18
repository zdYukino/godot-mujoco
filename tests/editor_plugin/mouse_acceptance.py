import os,sys,time,json,pathlib,subprocess
from Xlib import X,display,XK
from Xlib.ext import xtest
display_name=os.environ.get('DISPLAY',':91');s=display.Display(display_name);folder=pathlib.Path(sys.argv[1]);checks=[]
def state():return json.loads((folder/'state.json').read_text())
def request(**kwargs):
 (folder/'request.tmp').write_text(json.dumps(kwargs));(folder/'request.tmp').replace(folder/'request.json');time.sleep(.4)
def wait_window():
 for _ in range(300):
  for w in s.screen().root.query_tree().children:
   try:
    prop=w.get_full_property(s.intern_atom('_NET_WM_PID'),X.AnyPropertyType)
    if not prop or w.get_attributes().map_state!=X.IsViewable:continue
    args=pathlib.Path('/proc',str(prop.value[0]),'cmdline').read_bytes().split(b'\0')
    if ('--probe-dir='+str(folder)).encode() not in args:continue
    if w.get_geometry().width<1000:continue
    w.configure(stack_mode=X.Above);w.set_input_focus(X.RevertToParent,X.CurrentTime);s.sync();time.sleep(1);return
   except (OSError,Exception):continue
  time.sleep(.1)
 raise RuntimeError('target GUI window not mapped')
def key(name,ctrl=False,shift=False):
 mods=(['Control_L'] if ctrl else [])+(['Shift_L'] if shift else [])
 for k in mods:xtest.fake_input(s,X.KeyPress,s.keysym_to_keycode(XK.string_to_keysym(k)))
 c=s.keysym_to_keycode(XK.string_to_keysym(name));xtest.fake_input(s,X.KeyPress,c);xtest.fake_input(s,X.KeyRelease,c)
 for k in reversed(mods):xtest.fake_input(s,X.KeyRelease,s.keysym_to_keycode(XK.string_to_keysym(k)))
 s.sync();time.sleep(.06)
def move(x,y):xtest.fake_input(s,X.MotionNotify,x=int(x),y=int(y));s.sync()
def click(rect):
 x,y,w,h=rect;move(x+min(w/2,120),y+h/2);xtest.fake_input(s,X.ButtonPress,1);s.sync();time.sleep(.08);xtest.fake_input(s,X.ButtonRelease,1);s.sync();time.sleep(.4)
def item(name,kind=None):return next(i for i in state()['items'] if (i['name']==name or name=='sphere' and i['name'].startswith('sphere_')) and (not kind or i['kind']==kind))
def field(name,text):
 request(scroll=name);click(state()['fields'][name]['rect']);key('a',ctrl=True)
 for c in text:key(c if c not in {'.','-','[',']',',','/','_'} else {'/':'slash','_':'underscore','.':'period','-':'minus','[':'bracketleft',']':'bracketright',',':'comma'}[c])
 time.sleep(.4)
def button(name):
 request(scroll=name)
 matches=[c for c in state()['controls'] if c.get('text')==name]
 click(matches[0]['rect'])
def shot(name):
 move(1550,980);time.sleep(.25);subprocess.run(['import','-display',display_name,'-window','root',str(folder/(name+'.png'))],check=True)
 (folder/(name+'.json')).write_text(json.dumps(state(),indent=2))
def check(v,label):
 checks.append({'name':label,'passed':bool(v)});print('PASS' if v else 'FAIL',label,flush=True)
def locked(draft):
 st=state();return st['selected'].get('name')=='hinge' and st['pending'] and st['fields']['damping']['text']=='0.2' and st['fields']['damping']['id']==draft and [i['name'] for i in st['items'] if i['selected']]==['hinge']

def damping():return float(state()['fields']['damping']['text'])
def type_text(text):
 key('a',ctrl=True)
 for c in text:key({'/':'slash','.':'period','-':'minus','_':'underscore'}.get(c,c))
def dialog_file(path):
 for _ in range(30):
  ds=[c for c in state()['controls'] if c.get('dialog')]
  if ds:break
  time.sleep(.1)
 d=ds[0];click(d['file']);type_text(path);key('Return');time.sleep(.8)
def reopen():
 wait_window()
 for _ in range(150):
  if (folder/'state.json').exists():break
  time.sleep(.2)
 time.sleep(2)
 button('Open document');dialog_file(sys.argv[2]);click(item('hinge')['rect'])
 check(damping()==.2 and item('hinge')['selected'],'editor process restart restores saved physics and selection')
 field('damping','0.2');draft=state()['fields']['damping']['id'];click(item('arm','body')['rect']);move(1550,980);time.sleep(.3)
 check(locked(draft),'pending upper click after process restart');shot('restart-restored')
 button('Discard pending fields')
def main():
 wait_window()
 for _ in range(150):
  if (folder/'state.json').exists():break
  time.sleep(.2)
 click(item('hinge')['rect']);field('damping','0.2');draft=state()['fields']['damping']['id'];before=state()['snapshot']['xml'];shot('01-draft')
 for n in ['arm','sphere','arm','arm','sphere','hinge']:
  click(item(n,'joint' if n=='hinge' else 'body')['rect']);move(1550,980);time.sleep(.3);check(locked(draft),'pending actual click '+n);check(state()['snapshot']['xml']==before,'draft leaves compiled XML unchanged '+n);shot('02-'+str(len(checks))+'-'+n)
 button('Discard pending fields');check(not state()['pending'],'Discard clears pending');click(item('arm','body')['rect']);check(state()['selected']['name']=='arm' and item('arm','body')['selected'],'selection after Discard')
 click(item('hinge')['rect']);field('damping','notjson');button('Apply to physics');check(state()['pending'] and state()['snapshot']['xml']==before and 'FAILED' in state()['status'],'invalid JSON rollback');shot('03-invalid')
 field('damping','0.2');button('Apply to physics');check(not state()['pending'] and damping()==.2 and item('hinge')['selected'],'Apply commits and keeps highlight');shot('04-applied')
 button('Apply to physics');check(not state()['pending'] and damping()==.2,'repeated Apply no change')
 click(item('hinge')['rect']);key('z',ctrl=True);time.sleep(.5);check(damping()==0,'actual Ctrl Z undo');key('z',ctrl=True,shift=True);time.sleep(.5);check(damping()==.2,'actual Ctrl Shift Z redo');shot('05-redo')
 button('Save document');dialog_file(str(folder/'saved.gmj.json'));check((folder/'saved.gmj.json').exists() and not state()['dirty'],'actual Save dialog');shot('06-saved')
 field('damping','0.3');button('Apply to physics');check(damping()==.3,'change after save');button('Open document');dialog_file(str(folder/'saved.gmj.json'));check(damping()==.2 and item('hinge')['selected'],'actual Open dialog restores saved damping');shot('07-reopened')
 click(item('sphere','body')['rect']);check(state()['selected']['name'].startswith('sphere_'),'selection below after Apply');click(item('arm','body')['rect']);check(state()['selected']['name']=='arm','selection above after Apply')
 geom=next(n for n in state()['points'] if n.startswith('sphere_'))
 click(state()['points'][geom]);check(state()['selected'].get('kind')=='geom' and state()['selected']['name']==geom,'actual viewport click selects sphere geometry')
 size=json.loads(state()['fields']['size']['text']);button('Size ×1.1');scaled=json.loads(state()['fields']['size']['text']);check(abs(scaled[0]-size[0]*1.1)<1e-8 and scaled[1:]==[0,0],'actual sphere Size keeps sphere physics')
 click(item(geom,'geom')['rect']);key('z',ctrl=True);time.sleep(.4);check(json.loads(state()['fields']['size']['text'])==size,'actual sphere Size undo')
 button('+ cylinder');name=state()['selected']['name']+'_geom';click(item(name,'geom')['rect']);pos=json.loads(state()['fields']['pos']['text']);button('Move +0.1 m');moved=json.loads(state()['fields']['pos']['text']);check(abs(moved[0]-pos[0]-.1)<1e-8,'actual cylinder move updates physics')
 quat=json.loads(state()['fields']['quat']['text']);button('Rotate +5°');check(json.loads(state()['fields']['quat']['text'])!=quat,'actual cylinder rotate updates physics')
 size=json.loads(state()['fields']['size']['text']);button('Size ×1.1');scaled=json.loads(state()['fields']['size']['text']);check(abs(scaled[0]-size[0]*1.1)<1e-8 and abs(scaled[1]-size[1]*1.1)<1e-8 and scaled[2]==0,'actual cylinder Size uses radius and half height');shot('08-viewport-shapes')
 (folder/'mouse-results.json').write_text(json.dumps(checks,indent=2));request(quit=True)
if __name__=='__main__':
 try:
  reopen() if len(sys.argv)>2 else main()
  if not all(c['passed'] for c in checks):raise SystemExit(1)
 finally:
  (folder/'mouse-results.json').write_text(json.dumps(checks,indent=2))
  request(quit=True)
