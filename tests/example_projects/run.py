#!/usr/bin/env python3
"""Verify the projects opened directly from examples/, in an isolated repo layout."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', type=Path, required=True, help='New output directory')
parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
args = parser.parse_args()
source = Path(__file__).resolve().parents[2]
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=False)
repo = out / 'repo'
env = os.environ.copy()
for key in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
    target = out / key.lower()
    target.mkdir()
    env[key] = str(target)

shutil.copytree(source / 'addons', repo / 'addons', ignore=shutil.ignore_patterns('*.uid'))
shutil.copytree(source / 'assets', repo / 'assets')
shutil.copytree(source / 'examples/_shared', repo / 'examples/_shared')
names = ['shape_gallery', 'g1_passive', 'sdf_terrain', 'pendulum']
for name in names:
    shutil.copytree(
        source / 'examples' / name, repo / 'examples' / name, symlinks=True,
        ignore=shutil.ignore_patterns('.godot', '.godot.*', '*.uid'),
    )

results = {}
for name in names:
    project = repo / 'examples' / name
    assert (project / 'project.godot').is_file(), f'{name}: project.godot missing'
    assert (project / 'addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').is_file(), 'Build the native addon first'
    for path in project.rglob('*'):
        if path.is_symlink():
            target = path.resolve(strict=True)
            assert target.is_relative_to(repo), f'Example link escapes the repo: {path}'
    shutil.copyfile(source / 'tests/example_projects/acceptance.gd', project / 'example_project_acceptance.gd')
    for step, flags in [
        ('import', ['--editor', '--import', '--frame-delay', '1000']),
        ('runtime', ['--fixed-fps', '60', '--script', 'res://example_project_acceptance.gd']),
    ]:
        log = out / f'{name}-{step}.log'
        print(f'START {name} {step}', flush=True)
        with log.open('w') as output:
            result = subprocess.run(
                [args.godot, '--headless', '--path', str(project), *flags],
                env=env, stdout=output, stderr=subprocess.STDOUT, timeout=120,
            )
        text = log.read_text()
        assert result.returncode == 0, f'{name} {step}: exit {result.returncode}; see {log}'
        assert not any(token in text for token in ['ERROR:', 'SCRIPT ERROR:', 'leaked']), f'{name} {step}: see {log}'
        if step == 'runtime':
            reports = [line.split(' ', 1)[1] for line in text.splitlines() if line.startswith('EXAMPLE_PROJECT_RESULT ')]
            assert len(reports) == 1, f'{name}: missing result'
            results[name] = json.loads(reports[0])
            assert results[name]['failed'] == 0, results[name]
        print(f'PASS {name} {step}', flush=True)
(out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
print('DIRECT EXAMPLE PROJECTS PASS', json.dumps(results), flush=True)
