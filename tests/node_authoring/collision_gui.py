#!/usr/bin/env python3
"""Rendered Godot Inspector acceptance through ordinary Window GUI input.

Use --stage prepare to keep a controlled editor open for additional GUI checks.
Outputs and the test PID live in --out; real examples are never modified.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from desktop import Desktop


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
parser.add_argument('--stage', choices=['prepare', 'appearance', 'collision', 'world', 'export', 'reopen', 'all'], default='all')
args = parser.parse_args()
source = Path(__file__).resolve().parents[2]
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=True)
project = out / 'project'
project.mkdir(exist_ok=True)
env = os.environ.copy()
env.setdefault('DISPLAY', ':0')
env['LIBGL_ALWAYS_SOFTWARE'] = '1'
for key in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
    directory = out / key.lower()
    directory.mkdir(exist_ok=True)
    env[key] = str(directory)


def run(label, flags):
    with (out / (label + '.log')).open('w') as log:
        result = subprocess.run([args.godot, '--headless', '--path', str(project), *flags], env=env,
                                stdout=log, stderr=subprocess.STDOUT, timeout=150)
    text = (out / (label + '.log')).read_text()
    assert result.returncode == 0 and 'ERROR:' not in text and 'leaked' not in text, (label, text[-5000:])


def start_editor():
    log = (out / 'editor.log').open('a')
    child = subprocess.Popen([args.godot, '--editor', '--path', str(project), '--display-driver', 'x11',
                              '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--',
                              '--mj-author-gui', '--probe-dir=' + str(out)], env=env,
                             stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    (out / 'pid').write_text(str(child.pid))
    return child.pid


def state():
    try:
        return json.loads((out / 'state.json').read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def wait(condition, seconds=40):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = state()
        if value and condition(value):
            return value
        time.sleep(.15)
    raise AssertionError('GUI timeout: ' + str(state().get('models', state())))


def request(**value):
    wait(lambda _: not (out / 'request.json').exists())
    value['id'] = str(time.monotonic_ns())
    (out / 'request.tmp').write_text(json.dumps(value))
    (out / 'request.tmp').replace(out / 'request.json')
    if value.get('quit'): return
    wait(lambda current: current.get('completed_request') == value['id'])


def valid(value):
    return value.get('models') and all(m['validated'] == m['revision'] and m['context_valid'] and not m['error'] for m in value['models'])


def shot(name):
    request(capture=name + '.png')
    (out / (name + '.json')).write_text(json.dumps(state(), indent=2))


def row(name):
    request(scroll=name)
    # The probe initially opens the MuJoCo dock. Re-selecting the already
    # selected saved node does not emit Godot's selection_changed signal.
    if name in state()['selected']:
        alternate = 'GuiAuthor' if name != 'GuiAuthor' else 'Model'
        desktop.click(next(item['rect'] for item in state()['rows'] if item['text'] == alternate))
        wait(lambda current: alternate in current['selected'])
    desktop.click(next(item['rect'] for item in state()['rows'] if item['text'] == name))
    wait(lambda current: name in current['selected'] and current.get('inspected') == name)
    time.sleep(.3)


def field(name, kind=None):
    values = state()['fields'][name]
    return next(value for value in values if kind is None or value['class'] == kind)


def expand(name):
    clicked = set()
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        current = state()
        if name in current['fields']: return
        sections = [value for value in current['controls'] if 'section' in value and value['section'] not in clicked]
        matching = [value for value in sections if name in value.get('properties', [])]
        candidates = matching[-1:] or sections[:1]
        if candidates:
            section = candidates[0]; clicked.add(section['section'])
            area = section['rect']
            desktop.click([area[0], area[1], area[2], 22])
        time.sleep(.5)
    raise AssertionError(('section', name))


def dropdown(name, item_id):
    current = field(name, 'OptionButton')
    if not current['popup_visible']:
        desktop.click(current['rect'])
    current = wait(lambda value: value['fields'][name][0]['popup_visible'])['fields'][name][0]
    index = next(index for index, item in enumerate(current['items']) if item['id'] == item_id)
    x, y = current['popup_position']
    width, height = current['popup_size']
    row_height = height / len(current['items'])
    desktop.click([x, y + index * row_height, width, row_height])


def number(name, value):
    values = state()['fields'][name]
    editor = next((item for item in values if item['class'] == 'LineEdit'), None)
    if not editor:
        desktop.click(next(item['rect'] for item in values if item['class'] == 'EditorSpinSlider'), count=2)
        wait(lambda current: any(item['class'] == 'LineEdit' for item in current['fields'][name]))
        editor = field(name, 'LineEdit')
    desktop.click(editor['rect'])
    desktop.type(str(value))
    desktop.key('Return')


if args.stage in ['prepare', 'all']:
    assert not (project / 'GuiAuthor.tscn').exists(), 'Use a fresh --out for preparation'
    shutil.copytree(source / 'addons', project / 'addons', dirs_exist_ok=True)
    shutil.copyfile(source / 'tests/node_authoring/gui_probe.gd', project / 'gui_probe.gd')
    shutil.copyfile(source / 'tests/node_authoring/export_reload.gd', project / 'export_reload.gd')
    (project / 'project.godot').write_text('''config_version=5
[application]
config/name="Geom collision GUI acceptance"
[rendering]
renderer/rendering_method="gl_compatibility"
[physics]
3d/physics_engine="MuJoCo"
[editor_plugins]
enabled=PackedStringArray("res://addons/mujoco_editor/plugin.cfg")
''')
    (project / 'fixture.obj').write_text('v 0 0 0\nv 1 0 0\nv 0 1 0\nv 0 0 1\nf 1 3 2\nf 1 2 4\nf 1 4 3\nf 2 3 4\n')
    (project / 'fixture.xml').write_text('''<mujoco model="collision_gui"><asset><mesh name="shared" file="fixture.obj" scale=".3 .3 .3"/></asset><worldbody><geom name="ground" type="plane" size="3 3 .1"/><body name="part_a" pos="0 0 1"><freejoint name="free_a"/><geom name="mesh_a" type="mesh" mesh="shared" mass="1" rgba=".5 .7 .9 1"/></body><body name="part_b" pos="1 0 1"><freejoint name="free_b"/><geom name="mesh_b" type="mesh" mesh="shared" mass="1"/></body></worldbody></mujoco>''')
    (project / 'prepare_gui.gd').write_text('''extends SceneTree
func _initialize():call_deferred("run")
func run():
 var result=await load("res://addons/godot_mujoco/model/author_builder.gd").import_file("res://fixture.xml")
 if not result.error.is_empty():printerr(result.error);quit(1);return
 var world=load("res://addons/godot_mujoco/model/scene_builder.gd").create(result.design)
 world.name="GuiAuthor"
 var packed=PackedScene.new();packed.pack(world);ResourceSaver.save(packed,"res://GuiAuthor.tscn");world.free();quit()
''')
    run('import', ['--editor', '--import', '--frame-delay', '1000'])
    run('prepare', ['--script', 'res://prepare_gui.gd'])
    if (out / 'state.json').exists():
        (out / 'state.json').unlink()
    pid = start_editor()
else:
    pid = int((out / 'pid').read_text())

class GuiInput:
    pressed = False
    def __init__(self): self.keyboard = Desktop(pid, env['DISPLAY'])
    def focus(self): self.keyboard.focus()
    def move(self,x,y):
        self.point=(x,y)
        request(input=[{"kind":"motion","x":x,"y":y,"held":self.pressed}])
    def button(self,pressed):
        request(input=[{"x":self.point[0],"y":self.point[1],"pressed":pressed}]);self.pressed=pressed
    def click(self,rect,count=1):
        self.input_point = (rect[0]+min(100,rect[2]/2),rect[1]+rect[3]/2)
        self.keyboard.window_click(rect,count=count)
        time.sleep(.3)
    def key(self,name,ctrl=False,shift=False):
        if name == 'Return':
            x,y=self.input_point
            request(input=[{"kind":"key","key":"Return","pressed":True,"x":x,"y":y},{"kind":"key","key":"Return","pressed":False,"x":x,"y":y}])
            return
        if ctrl and name.lower() in ['z', 'y', 's']:
            self.keyboard.key('Escape')
            self.keyboard.focus()
            self.keyboard.window_key(name,ctrl=ctrl,shift=shift)
            return
        self.keyboard.key(name,ctrl=ctrl,shift=shift)
    def type(self,value):
        x,y=self.input_point
        events=[{"kind":"key","key":"A","ctrl":True,"pressed":pressed,"x":x,"y":y} for pressed in [True,False]]
        events.extend(event for character in value for event in [{"kind":"key","key":character.upper(),"unicode":ord(character),"pressed":True,"x":x,"y":y},{"kind":"key","key":character.upper(),"unicode":ord(character),"pressed":False,"x":x,"y":y}])
        request(input=events)

desktop = GuiInput()
wait(valid)
desktop.focus()
report = json.loads((out / 'results.json').read_text()) if (out / 'results.json').exists() else {}

if args.stage in ['appearance', 'all']:
    row('mesh_a')
    expand('mjcf/color')
    before = field('mjcf/color', 'ColorPickerButton')
    desktop.click(before['rect'])
    wait(lambda value: value['fields']['mjcf/color'][0]['popup_visible'])
    surface = next(item['rect'] for item in state()['fields']['mjcf/color']
                   if item['class'] == 'Control' and item['rect'][2] >= 200 and item['rect'][2] == item['rect'][3])
    x, y, width, height = surface
    desktop.move(x + width*.3, y + height*.3)
    desktop.button(True)
    colors = []
    end = (.2, .65) if before['color'][0] > .65 else (.6, .5)
    for a, b in [(.4, .35), (.5, .4), end]:
        desktop.move(x + width*a, y + height*b)
        current = field('mjcf/color', 'ColorPickerButton')
        assert current['instance'] == before['instance'] and current['popup_visible']
        colors.append(current['color'])
    assert len({tuple(color) for color in colors}) == 3
    shot('00-continuous-color-drag')
    desktop.button(False)
    picker = field('mjcf/color', 'ColorPickerButton')
    desktop.keyboard.window_click(next(item['rect'] for item in state()['rows'] if item['text'] == 'mesh_a'),
                                  target_rect=picker['popup_position'] + picker['popup_size'])
    desktop.focus()
    wait(lambda value: not value['fields']['mjcf/color'][0]['popup_visible'] and valid(value))
    after = field('mjcf/color', 'ColorPickerButton')['color']
    assert after != before['color'], 'The dragged color is committed when the popup closes'
    desktop.key('z', ctrl=True)
    wait(lambda value: valid(value) and all(abs(a-b)<1e-5 for a,b in zip(value['fields']['mjcf/color'][0]['color'], before['color'])))
    desktop.key('y', ctrl=True)
    wait(lambda value: valid(value) and value['fields']['mjcf/color'][0]['color'] == after)
    report['appearance'] = {'continuous_colors': colors, 'stable_popup': True, 'undo_redo': True, 'color': after}

if args.stage in ['collision', 'all']:
    row('ground')
    expand('mjcf/collision_mode')
    assert field('mjcf/collision_mode')['disabled'], 'native primitive representation is read-only'
    row('mesh_a')
    expand('mjcf/collision_mode')
    dropdown('mjcf/collision_mode', 1)
    wait(lambda value: valid(value) and value['models'][0]['collision_stats'])
    dropdown('mjcf/collision_sdf_depth', 5)
    saved = wait(lambda value: valid(value) and list(value['models'][0]['mesh_options'].values()) == [{'octree_maxdepth': 5}])
    warning = next(value for value in saved['fields']['mjcf/collision_sdf_depth'] if value.get('text') == '!')
    assert '不随 MJCF 导出' in warning['tooltip']
    desktop.keyboard.window_motion(warning['rect'][0] + 4, warning['rect'][1] + 8)
    wait(lambda value: any('不随 MJCF 导出' in text for text in value['tooltip_texts']))
    shot('01-custom-depth-warning')
    desktop.move(1400, 700)
    desktop.key('z', ctrl=True)
    wait(lambda value: valid(value) and not value['models'][0]['mesh_options'])
    desktop.key('y', ctrl=True)
    wait(lambda value: valid(value) and list(value['models'][0]['mesh_options'].values()) == [{'octree_maxdepth': 5}])
    shot('02-depth-redo')
    row('mesh_b')
    expand('mjcf/collision_maxhullvert')
    assert field('mjcf/collision_mode')['selected'] == 0
    desktop.click(next(item['rect'] for item in state()['fields']['mjcf/collision_maxhullvert'] if item.get('text') == '不限'))
    number('mjcf/collision_maxhullvert', 8)
    wait(valid)
    shot('03-independent-hull')
    report['collision'] = {'native_read_only': True, 'depth': 5, 'warning_tooltip': warning['tooltip'], 'undo_redo': True, 'independent_hull': 8}

if args.stage in ['world', 'all']:
    row('GuiAuthor')
    expand('mjcf/collision_nativeccd')
    assert all('mjcf/collision_' + key in state()['fields'] for key in ['nativeccd', 'multiccd', 'ccd_iterations', 'ccd_tolerance', 'sdf_iterations', 'sdf_initpoints'])
    desktop.click(next(item['rect'] for item in state()['fields']['mjcf/collision_nativeccd'] if item['class'] in ['CheckBox', 'CheckButton']))
    number('mjcf/collision_sdf_iterations', 17)
    wait(lambda value: valid(value) and value['worlds'][0]['settings']['sdf_iterations'] == 17)
    desktop.key('z', ctrl=True)
    wait(lambda value: valid(value) and value['worlds'][0]['settings']['sdf_iterations'] == 10)
    desktop.key('y', ctrl=True)
    wait(lambda value: valid(value) and value['worlds'][0]['settings']['sdf_iterations'] == 17)
    shot('04-world-controls')
    report['world'] = state()['worlds'][0]['settings']

if args.stage in ['export', 'all']:
    row('mesh_a')
    request(scope=0)
    (project / 'exported').mkdir(exist_ok=True)
    desktop.click(next(item['rect'] for item in state()['controls'] if item.get('text') == '导出 MJCF 与依赖'))
    wait(lambda value: any(item.get('dialog') for item in value['controls']))
    folder = next(item for item in state()['controls'] if item.get('list_item') == 'exported')
    desktop.click(folder['rect'], count=2)
    wait(lambda value: any(item.get('dialog') and item['directory'] == str(project / 'exported') for item in value['controls']))
    shot('05-export-directory')
    dialog = next(item for item in state()['controls'] if item.get('dialog'))
    desktop.keyboard.window_click(dialog['ok'])
    wait(lambda _: bool(list((project / 'exported').glob('*.xml'))))
    text = next((project / 'exported').glob('*.xml')).read_text()
    assert 'octree_maxdepth' not in text and 'mesh_options' not in text
    assert 'maxhullvert="8"' in text and 'sdf_iterations="17"' in text and 'nativeccd="disable"' in text
    run('export-reload', ['--script', 'res://export_reload.gd'])
    shot('05-exported')
    report['export'] = {'standard_xml': True, 'depth_sidecar': False, 'world_controls': True, 'standalone_depth': 6}

if args.stage in ['collision', 'world', 'export', 'all']:
    desktop.key('s', ctrl=True)
    time.sleep(1)
    saved = (project / 'GuiAuthor.tscn').read_text()
    assert 'octree_maxdepth' in saved
    report['saved_instance'] = state()['models'][0]['id']
    (out / 'results.json').write_text(json.dumps(report, indent=2) + '\n')

if args.stage == 'all':
    request(quit=True)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if os.waitpid(pid, os.WNOHANG)[0]: break
        time.sleep(.1)
    else: raise AssertionError('Controlled editor did not exit')
    (out / 'state.json').unlink()
    pid = start_editor()
    desktop = GuiInput()
    wait(valid)
    desktop.focus()

if args.stage in ['reopen', 'all']:
    assert state()['models'][0]['id'] == report['saved_instance']
    assert list(state()['models'][0]['mesh_options'].values()) == [{'octree_maxdepth': 5}]
    assert state()['worlds'][0]['settings']['sdf_iterations'] == 17
    row('mesh_a')
    expand('mjcf/collision_sdf_depth')
    assert field('mjcf/collision_sdf_depth')['selected'] == 3
    assert all(abs(a-b)<1e-5 for a,b in zip(field('mjcf/color', 'ColorPickerButton')['color'], report['appearance']['color']))
    shot('06-independent-reopen')
    report['reopen'] = True

if args.stage == 'all': request(quit=True)

(out / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
print('COLLISION_GUI_STAGE_PASS', args.stage, flush=True)
