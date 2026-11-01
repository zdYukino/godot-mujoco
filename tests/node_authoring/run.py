#!/usr/bin/env python3
"""Run authoring tests in an isolated project, leaving examples untouched."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

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
env['GMJ_TEST_PYTHON'] = sys.executable
env.setdefault('DISPLAY', ':0')
env.setdefault('XAUTHORITY', '/run/user/1000/gdm/Xauthority')
for name in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
    folder = out / name.lower()
    folder.mkdir(exist_ok=True)
    env[name] = str(folder)
for stage, flags in [('import', ['--editor', '--import', '--frame-delay', '1000']),
                     ('author', ['--script', 'res://acceptance.gd']),
                     ('query', ['--script', 'res://query_acceptance.gd']),
                     ('visual', ['--script', 'res://visual_acceptance.gd']),
                     ('artifact', ['--script', 'res://artifact_acceptance.gd']),
                     ('artifact_relocated', ['--script', 'res://artifact_acceptance.gd', '--', '--artifact-reopen']),
                     ('appearance', ['--script', 'res://appearance_acceptance.gd']),
                     ('collision', ['--script', 'res://collision_acceptance.gd']),
                     ('runtime', ['--script', 'res://runtime_acceptance.gd']),
                     ('live_protocol', ['--editor', '--', '--mj-tool-test=res://live_protocol_acceptance.gd']),
                     ('artifact_editor', ['--editor', '--', '--mj-tool-test=res://artifact_editor_acceptance.gd']),
                     ('editor', ['--editor', '--', '--mj-author-test']),
                     ('live', ['--editor', '--', '--mj-live-test'])]:
    log = out / f'{stage}.log'
    run_project = project
    absent_project = None
    if stage == 'artifact_relocated':
        run_project = out / 'artifact-relocated-project'
        shutil.copytree(project, run_project, dirs_exist_ok=True)
        absent_project = out / 'artifact-original-project-absent'
        project.rename(absent_project)
    # Each editor probe opens its own fixture; startup restoration must not race it.
    if stage != 'import' and '--editor' in flags:
        editor_layout = run_project / '.godot/editor'
        if editor_layout.exists():
            archive = out / f'{stage}-prior-editor-layout'
            suffix = 1
            while archive.exists():
                archive = out / f'{stage}-prior-editor-layout-{suffix}'
                suffix += 1
            shutil.move(str(editor_layout), str(archive))
    try:
        with log.open('w') as stream:
            result = subprocess.run([args.godot, '--headless', '--path', str(run_project), *flags],
                                    env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=180)
    finally:
        if absent_project is not None:
            absent_project.rename(project)
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
    if stage == 'query':
        reports = [json.loads(line.split(' ', 1)[1]) for line in content.splitlines()
                   if line.startswith('NODE_QUERY_RESULT ')]
        assert len(reports) == 1 and reports[0]['failed'] == 0, content
        (out / 'query-results.json').write_text(json.dumps(reports[0], indent=2) + '\n')
        print(reports[0])
    if stage == 'visual':
        reports = [json.loads(line.split(' ', 1)[1]) for line in content.splitlines()
                   if line.startswith('NODE_VISUAL_RESULT ')]
        assert len(reports) == 1 and reports[0]['failed'] == 0, content
        (out / 'visual-results.json').write_text(json.dumps(reports[0], indent=2) + '\n')
        print(reports[0])
    if stage in {'artifact', 'artifact_relocated', 'artifact_editor'}:
        prefix = {'artifact': 'NODE_ARTIFACT_RESULT ',
                  'artifact_relocated': 'NODE_ARTIFACT_REOPEN_RESULT ',
                  'artifact_editor': 'NODE_ARTIFACT_EDITOR_RESULT '}[stage]
        reports = [json.loads(line[len(prefix):]) for line in content.splitlines()
                   if line.startswith(prefix)]
        assert len(reports) == 1 and reports[0]['failed'] == 0, content
        (out / f'{stage}-results.json').write_text(json.dumps(reports[0], indent=2) + '\n')
        print(reports[0])
