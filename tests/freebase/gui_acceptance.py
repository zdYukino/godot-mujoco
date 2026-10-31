"""Actual owned-window input for explicit viewer controls and G1 contact physics."""
import json
import os
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'node_authoring'))
from desktop import Desktop

folder = Path(sys.argv[1]).resolve()
checks = []

def state():
    try:
        return json.loads((folder / 'state.json').read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

def wait(predicate, seconds=40):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        value = state()
        if value and predicate(value):
            return value
        time.sleep(.1)
    raise AssertionError('GUI timeout: ' + str(state()))

def check(ok, label):
    checks.append({'name': label, 'passed': bool(ok)})
    print('PASS' if ok else 'FAIL', label, flush=True)
    if not ok:
        raise AssertionError(label)

try:
    initial = wait(lambda value: value.get('actions') and value.get('ready') and (value['native_active'] if value['native_requested'] else True), 90)
    desktop = Desktop(initial['pid'], os.environ.get('DISPLAY', ':0'))
    desktop.focus()
except Exception as error:
    checks.append({'name':'owned graphical fixture startup: '+str(error),'passed':False})
    (folder/'mouse-results.json').write_text(json.dumps(checks,indent=2))
    (folder/'quit').touch()
    raise

def reveal(action):
    (folder / 'reveal.tmp').write_text(json.dumps({'action': action}))
    (folder / 'reveal.tmp').replace(folder / 'reveal.json')
    time.sleep(.25)

def extras(visible):
    if state()['extras'] != visible:
        desktop.window_key('F11')
        wait(lambda value: value['extras'] == visible)

def action(name):
    extras(name in ['step', 'capture_snapshot', 'restore_snapshot'])
    reveal(name)
    item = state()['actions'][name]
    check(item['visible'], 'actual product control visible: ' + name)
    before = state()
    desktop.window_click(item['rect'])
    if name == 'step':
        wait(lambda value: abs(value['time'] - before['time'] - .002 * before['count_value']) < 1e-9)
    else:
        time.sleep(.3)

def step(n):
    extras(True);reveal('count')
    desktop.window_click(state()['count'])
    desktop.window_key('a', ctrl=True)
    for char in str(n):desktop.window_key(char)
    desktop.window_key('Return')
    wait(lambda value: value['count_value'] == n)
    action('step')

def fixture(mode):
    # Embedded subwindows cover the fixture toolbar until F11 closes them.
    extras(False)
    desktop.window_click(next(value['rect'] for value in state()['controls'] if value['text'] == 'Fixture ' + mode))
    expected = '' if mode == 'invalid' else 'res://FreebaseEnvironment.tscn' if mode == 'original' else 'res://Contact_' + mode + '.tscn'
    wait(lambda value: value['fixture_path'] == expected)
    check(state()['fixture_path'] == expected, 'actual toolbar selects the saved candidate: ' + mode)

def rebuild(mode):
    before=state()['world_id'];fixture(mode);action('reload')
    return wait(lambda value: bool(value['host_error']) if mode == 'invalid' else value['world_id'] != before and value['time'] == 0 and not value['host_error'] and value['ready'] and (value['native_active'] if value['native_requested'] else True), 125)

def capture(name):
    (folder/'capture.json').write_text(json.dumps({'name':name}))
    end=time.monotonic()+10
    while not (folder/(name+'.png')).exists():
        if time.monotonic()>end:raise AssertionError('actual viewport capture timeout: '+name)
        time.sleep(.05)
    (folder / (name + '.json')).write_text(json.dumps(state(), indent=2))

def main():
    if initial['native_requested']:check(initial['native_active'] and initial['native_gl_errors']==0, 'actual native rendering is active with no GL errors')
    before=state();time.sleep(.5)
    check(state()['paused'] and state()['time']==before['time'] and state()['game_elapsed']>before['game_elapsed'], 'game UI time advances while G1 physics is paused');capture('01-paused')
    step(9);check(abs(state()['time']-.018)<1e-9 and state()['paused'], 'actual component Step9 advances exactly0.018 seconds');capture('02-step9')
    action('capture_snapshot');before=state();action('resume');time.sleep(1);action('pause')
    check(state()['time']>before['time'] and state()['paused'], 'actual original Run/Pause controls');capture('03-running-then-paused')
    action('restore_snapshot');check(abs(state()['time']-before['time'])<1e-9 and state()['qpos']==before['qpos'], 'actual snapshot control restores pose and time');capture('04-restored')
    before=state();failed=rebuild('invalid')
    check(failed['world_id']==before['world_id'] and failed['qpos']==before['qpos'] and failed['time']==before['time'], 'failed saved reload preserves actual world and state');capture('05-reload-failed')
    completed=rebuild('original');check(completed['world_id']!=before['world_id'] and completed['paused'], 'successful retry replaces world while preserving pause');capture('06-reload-success')
    travel={}
    contacts={}
    for mode in ['low','high','barrier']:
        rebuild(mode);step(10);step(40);step(50)
        for unused in range(18):action('step')
        value=state();travel[mode]=value['travel'];contacts[mode]={'minimum':value['sole_friction_min'],'maximum':value['sole_friction_max']}
        if value['native_requested']:check(value['native_active'] and value['native_gl_errors']==0, 'actual native renderer survives saved fixture reload: '+mode)
        expected=1.0 if mode=='high' else .001
        check(value['sole_friction_min'] is not None and abs(value['sole_friction_min']-expected)<1e-9 and abs(value['sole_friction_max']-expected)<1e-9, 'authored material reaches actual sole-ground solver contacts: '+mode)
        check(abs(value['time']-2.0)<1e-9, '1000 actual steps: '+mode)
        check(value['contact_seen'] and value['finite'] and value['warnings']==0 and value['deepest']>-.04, 'finite G1 sole contact/penetration: '+mode)
        if mode=='barrier':check(value['barrier_seen'], 'G1 contacts ordinary Godot barrier')
        capture('07-contact-'+mode)
    check(contacts['low']['maximum']<contacts['high']['minimum'], 'distinct material coefficients reach actual G1 contacts')
    (folder/'measurements.json').write_text(json.dumps({'model_com_travel':travel,'solver_contact_friction':contacts,'gravity_m_s2':[2,0,-9.8],'initial_velocity':'zero; transient document qvel is not a saved design field','comparison':'passive articulated tipping does not imply monotonic travel'},indent=2))

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        checks.append({'name':str(error),'passed':False})
        raise
    finally:
        (folder/'mouse-results.json').write_text(json.dumps(checks,indent=2))
        (folder/'quit').touch()
