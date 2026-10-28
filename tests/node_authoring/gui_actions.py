#!/usr/bin/env python3
"""Actual mouse/keyboard acceptance for the Godot node authoring UI."""
import argparse
import json
import math
from pathlib import Path
import time
import os
from desktop import Desktop
p=argparse.ArgumentParser();p.add_argument('--pid',required=True,type=int);p.add_argument('--out',type=Path,required=True);p.add_argument('--display',default=os.environ.get('DISPLAY',':0'));p.add_argument('--stage',default='import');a=p.parse_args()
d=Desktop(a.pid,a.display);d.focus()
def state():return json.loads((a.out/'state.json').read_text())
def wait(condition,seconds=30):
    until=time.monotonic()+seconds
    while time.monotonic()<until:
        s=state()
        if condition(s):return s
        time.sleep(.15)
    raise AssertionError('GUI condition timed out: '+str(state().get('panel_status')))
def request(**value):
    (a.out/'request.tmp').write_text(json.dumps(value));(a.out/'request.tmp').replace(a.out/'request.json');time.sleep(.4)
def shot(name):request(capture=name+'.png');(a.out/(name+'.json')).write_text(json.dumps(state(),indent=2))
def button(title):d.click(next(c['rect'] for c in state()['controls'] if c['text']==title))
def row(name):
    request(scroll=name)
    d.click(next(r['rect'] for r in state()['rows'] if r['text']==name))
def valid(s):return s['models'] and all(m['validated']==m['revision'] and not m['error'] for m in s['models'])
def entity(name):return next(e for e in state()['entities'] if e['name']==name)
if a.stage=='import':
    button('载入 MJCF / 模型包')
    s=wait(lambda s:any('dialog' in c for c in s['controls']))
    dialog=next(c for c in s['controls'] if 'dialog' in c)
    d.click(dialog['file']);d.type(str(a.out/'project/fixture.xml'));d.key('Return')
    wait(valid);shot('01-imported')
    row('hinge');shot('02-inspector')
elif a.stage=='duplicate':
    row('arm');d.key('d',ctrl=True)
    wait(lambda s:valid(s) and len([e for e in s['entities'] if e['kind']=='body'])==2)
    shot('03-duplicated')
    d.key('z',ctrl=True)
    wait(lambda s:valid(s) and len([e for e in s['entities'] if e['kind']=='body'])==1)
    d.key('z',ctrl=True,shift=True)
    wait(lambda s:valid(s) and len([e for e in s['entities'] if e['kind']=='body'])==2)
    shot('04-redone')
elif a.stage=='gizmo':
    row('rod');wait(valid)
    # Use the native Move tool, then drag its X-axis shaft with actual XTEST events.
    candidates=[b for b in state()['controls'] if ('Ctrl+拖放' in b.get('tooltip','') or 'Ctrl+Drag' in b.get('tooltip',''))]
    d.click(min(candidates,key=lambda b:b['rect'][0])['rect']);time.sleep(.3)
    before=entity('rod')['position'];before_copy=entity('rod_copy')['position'];revision=state()['models'][0]['revision']
    point=state()['points']['rod'];o=point['origin'];r=point['right'];length=math.dist(o,r);v=[(r[i]-o[i])/length for i in (0,1)]
    start=[o[i]+v[i]*105 for i in (0,1)];end=[start[i]+v[i]*65 for i in (0,1)]
    shot('05-gizmo-before');d.drag(start,end)
    wait(lambda s:valid(s) and next(e for e in s['entities'] if e['name']=='rod')['position']!=before)
    after=entity('rod')['position'];assert entity('rod')['attrs']['type']=='capsule';assert entity('rod_copy')['position']==before_copy
    assert state()['models'][0]['revision']==revision+1,(revision,state()['models'])
    shot('06-gizmo-dragged');d.key('z',ctrl=True)
    wait(lambda s:valid(s) and all(abs(a-b)<1e-5 for a,b in zip(next(e for e in s['entities'] if e['name']=='rod')['position'],before)))
    d.key('z',ctrl=True,shift=True)
    wait(lambda s:valid(s) and all(abs(a-b)<1e-5 for a,b in zip(next(e for e in s['entities'] if e['name']=='rod')['position'],after)))
    shot('06-gizmo-redone')
elif a.stage=='inspector':
    row('hinge');time.sleep(.5)
    if 'mjcf/damping' not in state()['fields']:
        # First Inspector namespace section, at the pinned 1600x1000 test size.
        d.click([1310,227,120,24]);time.sleep(.4)
    d.click(state()['fields']['mjcf/damping'][0]['rect'],count=2);d.type('0.3');d.key('Return')
    wait(lambda s:valid(s) and next(e for e in s['entities'] if e['name']=='hinge')['attrs'].get('damping')=='0.3')
    shot('08-inspector-edited')
elif a.stage=='reopen':
    wait(valid);expected=json.loads((a.out/'gui_expected.json').read_text())
    assert len([e for e in state()['entities'] if e['kind']=='body'])==2
    assert all(abs(x-y)<1e-5 for x,y in zip(entity('rod')['position'],expected['rod_position']))
    assert entity('hinge')['attrs'].get('damping')==expected['damping']
    assert state()['models'][0]['id']==expected['document']
    shot('09-independent-reopen')
elif a.stage=='save':
    row('rod');d.key('s',ctrl=True);time.sleep(1);shot('07-saved')
    assert (a.out/'project/GuiAuthor.tscn').read_text().count('entity_id =')>=6
    (a.out/'gui_expected.json').write_text(json.dumps({'rod_position':entity('rod')['position'],'damping':entity('hinge')['attrs'].get('damping'),'document':state()['models'][0]['id']}))
print('GUI_STAGE_PASS',a.stage,flush=True)
