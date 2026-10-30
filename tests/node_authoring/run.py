#!/usr/bin/env python3
"""Run authoring tests in an isolated project, leaving examples untouched."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
args = parser.parse_args()
source = Path(__file__).resolve().parents[2]
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=True)
project = out / 'project'
project.mkdir(exist_ok=True)
shutil.copytree(source / 'addons', project / 'addons', dirs_exist_ok=True,
                ignore=shutil.ignore_patterns('*.uid'))
for path in (source / 'tests/node_authoring').glob('*'):
    if path.suffix in {'.gd', '.godot'}:
        shutil.copyfile(path, project / path.name)
with (project / 'project.godot').open('a') as stream:
    stream.write('\n[editor_plugins]\nenabled=PackedStringArray("res://addons/mujoco_editor/plugin.cfg")\n')
    stream.write('\n[physics]\n3d/physics_engine="MuJoCo"\n3d/run_on_separate_thread=false\n')
env = os.environ.copy()
env.setdefault('DISPLAY', ':0')
env.setdefault('XAUTHORITY', '/run/user/1000/gdm/Xauthority')
for name in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
    folder = out / name.lower()
    folder.mkdir(exist_ok=True)
    env[name] = str(folder)
for stage, flags in [('import', ['--editor', '--import', '--frame-delay', '1000']),
                     ('author', ['--script', 'res://acceptance.gd']),
                     ('appearance', ['--script', 'res://appearance_acceptance.gd']),
                     ('collision', ['--script', 'res://collision_acceptance.gd']),
                     ('runtime', ['--script', 'res://runtime_acceptance.gd']),
                     ('editor', ['--editor', '--', '--mj-author-test']),
                     ('live', ['--editor', '--', '--mj-live-test'])]:
    log = out / f'{stage}.log'
    with log.open('w') as stream:
        result = subprocess.run([args.godot, '--headless', '--path', str(project), *flags],
                                env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=180)
    content = log.read_text()
    print(stage, result.returncode, flush=True)
    if result.returncode or any(token in content for token in ['SCRIPT ERROR:', 'ERROR:', 'leaked']):
        print(content[-7000:])
        raise SystemExit(1)
    if stage == 'author':
        reports = [json.loads(line.split(' ', 1)[1]) for line in content.splitlines()
                   if line.startswith('NODE_AUTHORING_RESULT ')]
        assert len(reports) == 1 and reports[0]['failed'] == 0, content
        (out / 'results.json').write_text(json.dumps(reports[0], indent=2) + '\n')
        print(reports[0])
