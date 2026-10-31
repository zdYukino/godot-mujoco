#!/usr/bin/env python3
"""Exercise the editor selector and actual F5 gallery with the official GLX host."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--godot', default=os.environ.get('GODOT_BIN', 'godot'))
parser.add_argument('--install', type=Path, help='Optional staged bin/ and native_view/bin/ tree')
parser.add_argument('--without-native', action='store_true', help='Verify the GL-OFF selector, actual Godot F5 and saved-native-request fallback')
parser.add_argument('--preview-only', action='store_true', help='Capture and validate actual editor component previews without launching a game')
parser.add_argument('--preset-only', action='store_true', help='Validate actual editor panel preset, Undo/Redo and saved bindings')
args = parser.parse_args()
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=False)
project = out / 'project'
shutil.copytree(ROOT / 'examples/shape_gallery', project,
                ignore=shutil.ignore_patterns('addons', '.godot', '*.uid'))
shutil.copytree(ROOT / 'addons', project / 'addons', ignore=shutil.ignore_patterns('*.uid'))
if args.install:
    for name in ('bin', 'native_view/bin'):
        target = project / 'addons/godot_mujoco' / name
        if target.exists():
            shutil.rmtree(target)
        if (args.install / name).exists():
            shutil.copytree(args.install / name, target)
shutil.copy2(ROOT / 'tests/runtime_viewer/custom_ui.tscn', project / 'custom_ui.tscn')
for script in Path(__file__).parent.glob('*.gd'):
    shutil.copy2(script, project / script.name)
critical = [str(path.relative_to(project)) for path in project.rglob('*')
            if path.is_file() and (path.suffix in ('.gd', '.tscn', '.so') or '.so.' in path.name)]
hashes = {name: hashlib.sha256((project / name).read_bytes()).hexdigest() for name in critical}
hashes['@runner/run.py'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
(out / 'source-hashes.json').write_text(json.dumps(hashes, indent=2)+'\n')
env = os.environ.copy()
env.setdefault('DISPLAY', ':0')
env.setdefault('XAUTHORITY', '/run/user/1000/gdm/Xauthority')
if (ROOT / 'third_party/dotnet').is_dir():
    env.setdefault('DOTNET_ROOT', str(ROOT / 'third_party/dotnet'))
env['GMJ_RENDER_TEST_OUT'] = str(out)
for name in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'DOTNET_CLI_HOME'):
    folder = out / name
    folder.mkdir()
    env[name] = str(folder)
stages = [('import', ['--headless', '--editor', '--import', '--frame-delay', '1000']),
          ('preview', ['--editor', '--', '--mj-tool-test=res://editor_acceptance.gd', '--component-preview']),
          ('f5', ['--editor', '--', '--mj-tool-test=res://editor_acceptance.gd']),
          ('reopen', ['--editor', '--', '--mj-tool-test=res://editor_acceptance.gd', '--reopen']),
          ('fallback', ['--headless', '--script', 'res://fallback_acceptance.gd'])]
if args.preview_only:
    stages = stages[:2]
if args.preset_only:
    stages = [stages[0], ('preset', ['--editor', '--', '--mj-tool-test=res://editor_acceptance.gd', '--component-preset']),
              ('preset-reopen', ['--editor', '--', '--mj-tool-test=res://editor_acceptance.gd', '--component-preset-reopen'])]
rows = []
for name, flags in stages:
    if args.without_native and name in ('preview', 'f5', 'reopen'):
        flags = [*flags, '--without-native']
    log = out / f'{name}.log'
    with log.open('w') as stream:
        result = subprocess.run([args.godot, '--path', str(project), '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', *flags],
                                env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=240)
    content = log.read_text(errors='replace')
    errors = [line for line in content.splitlines() if any(token in line for token in ('ERROR:', 'leaked', 'received signal'))]
    # The pinned official editor's SeparationRay probe is an existing backend
    # limitation. Preserve and report it explicitly; other errors always fail.
    baseline = ['ERROR: Parameter "s" is null.'] if 'unsupported _separation_ray_shape_create' in content and '_shape_set_data' in content else []
    unexpected = [line for line in errors if line not in baseline]
    reports = [json.loads(line.split(' ', 1)[1]) for line in content.splitlines() if line.startswith('F5_RENDERER_RESULT ')]
    ok = result.returncode == 0 and not unexpected and (name=='import' or len(reports)==1 and reports[0]['failed']==0)
    rows.append(dict(stage=name, ok=ok, returncode=result.returncode, reports=reports, baseline_errors=[e for e in errors if e in baseline], unexpected_errors=unexpected))
    (out / 'stages.json').write_text(json.dumps(rows, indent=2)+'\n')
    print(name, 'PASS' if ok else 'FAIL', reports, flush=True)
    if not ok:
        print(content[-6000:])
        raise SystemExit(1)
