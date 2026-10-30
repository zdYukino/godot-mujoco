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
renderer = parser.add_mutually_exclusive_group()
renderer.add_argument('--native', action='store_true', help='Run the examples in real X11 windows with the native renderer')
renderer.add_argument('--graphical', action='store_true', help='Run the examples in real windows with Godot 3D rendering')
args = parser.parse_args()
source = Path(__file__).resolve().parents[2]
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=False)
repo = out / 'repo'
env = os.environ.copy()
env['GMJ_EXAMPLE_OUT'] = str(out)
env.setdefault('DISPLAY', ':0')
env.setdefault('XAUTHORITY', '/run/user/1000/gdm/Xauthority')
for key in ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
    target = out / key.lower()
    target.mkdir()
    env[key] = str(target)

shutil.copytree(source / 'addons', repo / 'addons', ignore=shutil.ignore_patterns('__pycache__'))
shutil.copytree(source / 'assets', repo / 'assets')
shutil.copytree(source / 'examples/_shared', repo / 'examples/_shared')
names = ['shape_gallery', 'g1_passive', 'sdf_terrain', 'pendulum', 'light_workflow', 'new_project']
shutil.copyfile(source / 'global.json', repo / 'global.json')
for name in names:
    shutil.copytree(
        source / 'examples' / ('templates/new_project' if name == 'new_project' else name), repo / 'examples' / name, symlinks=True,
        ignore=shutil.ignore_patterns('.godot', '.godot.*', '__pycache__'),
    )

results = {}
graphics = {}
for name in names:
    project = repo / 'examples' / name
    assert (project / 'project.godot').is_file(), f'{name}: project.godot missing'
    if name == 'new_project':
        config = project / 'project.godot'
        config.write_text(config.read_text().replace('__PROJECT_NAME__', '"Template Acceptance"'))
        (project / 'addons').symlink_to('../../addons', target_is_directory=True)
    if args.native or args.graphical:
        import re
        config=project/'project.godot'
        content=config.read_text()
        choice = 1 if args.native else 0
        if re.search(r'^mujoco_native_view/renderer=',content,re.M):
            content=re.sub(r'^mujoco_native_view/renderer=.*$', f'mujoco_native_view/renderer={choice}',content,flags=re.M)
        else:
            content=content.replace('[rendering]', f'[rendering]\nmujoco_native_view/renderer={choice}',1)
        config.write_text(content)
        if args.native and name=='g1_passive':
            # Start admitted, then acceptance.gd exercises a real stop -> 64 MiB
            # fallback -> 192 MiB re-admission on this isolated project copy.
            config.write_text(config.read_text().replace('[rendering]', '[rendering]\nmujoco_native_view/max_model_mib=192',1))
    if name == 'light_workflow':
        dotnet = source / 'third_party/dotnet'
        env.update(DOTNET_ROOT=str(dotnet), DOTNET_ROOT_X64=str(dotnet), DOTNET_MULTILEVEL_LOOKUP='0')
        env['PATH'] = str(dotnet) + os.pathsep + env.get('PATH','')
        with (out / 'light_workflow-build.log').open('w') as stream:
            subprocess.run([str(dotnet / 'dotnet'), 'build', str(project / 'LightWorkflow.csproj'), '-c', 'Debug'], env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=180, check=True)
    assert (project / 'addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so').is_file(), 'Build the native addon first'
    for path in project.rglob('*'):
        if path.is_symlink():
            target = path.resolve(strict=True)
            assert target.is_relative_to(repo), f'Example link escapes the repo: {path}'
    shutil.copyfile(source / 'tests/example_projects/acceptance.gd', project / 'example_project_acceptance.gd')
    env['GMJ_EXAMPLE_NAME'] = name
    stages = [
        ('import', ['--editor', '--import', '--frame-delay', '1000']),
        ('runtime', ['--fixed-fps', '60', '--script', 'res://example_project_acceptance.gd']),
    ]
    if args.graphical and name == 'light_workflow':
        # Exercise the normal C# main scene's real Godot picture separately,
        # while retaining its typed-operation self-test as the runtime stage.
        stages.insert(1, ('graphics', ['--fixed-fps', '60', '--script', 'res://example_project_acceptance.gd', '--', '--graphics-probe']))
    for step, flags in stages:
        if name == 'light_workflow' and step == 'runtime': flags = ['--fixed-fps', '60', '--', '--self-test']
        log = out / f'{name}-{step}.log'
        print(f'START {name} {step}', flush=True)
        with log.open('w') as output:
            result = subprocess.run(
                [args.godot, *([] if (args.native or args.graphical) and step!='import' else ['--headless']), '--path', str(project), *flags],
                env=env, stdout=output, stderr=subprocess.STDOUT, timeout=180,
            )
        text = log.read_text()
        pictures = [json.loads(line.split(' ', 1)[1]) for line in text.splitlines()
                    if line.startswith('EXAMPLE_GRAPHICS_FRAME ')]
        if pictures:
            graphics.setdefault(name, []).extend(pictures)
        if name == 'g1_passive' and step == 'runtime':
            probes = [json.loads(line.split(' ', 1)[1]) for line in text.splitlines()
                      if line.startswith('G1_BUDGET_RESULT ')]
            if probes:
                (out / 'g1-budget.json').write_text(json.dumps(probes, indent=2) + '\n')
        assert result.returncode == 0, f'{name} {step}: exit {result.returncode}; see {log}'
        assert not any(token in text for token in ['ERROR:', 'SCRIPT ERROR:', 'leaked']), f'{name} {step}: see {log}'
        if step == 'graphics':
            probes = [json.loads(line.split(' ', 1)[1]) for line in text.splitlines()
                      if line.startswith('EXAMPLE_GRAPHICS_RESULT ')]
            assert len(probes) == 1 and probes[0]['failed'] == 0, probes
            (out / f'{name}-graphics.json').write_text(json.dumps(probes[0], indent=2) + '\n')
        if step == 'runtime':
            reports = [line.split(' ', 1)[1] for line in text.splitlines() if line.startswith(('EXAMPLE_PROJECT_RESULT ', 'LIGHT_WORKFLOW_RESULT '))]
            assert len(reports) == 1, f'{name}: missing result'
            results[name] = json.loads(reports[0])
            assert results[name]['failed'] == 0, results[name]
        print(f'PASS {name} {step}', flush=True)
(out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
if args.graphical:
    assert set(graphics) == set(names), 'Missing actual Godot pictures for one or more entry projects'
    assert sum(map(len, graphics.values())) == 8, 'Expected all eight scene entry points across six projects'
    (out / 'graphics.json').write_text(json.dumps(graphics, indent=2) + '\n')
print('DIRECT EXAMPLE PROJECTS PASS', json.dumps(results), flush=True)
