#!/usr/bin/env python3
"""Bounded smoke. Always record stage outcomes; never retry a failed import."""
import hashlib
import json
import os
import pathlib
import platform
import shutil
import subprocess
import sys
from audit import positive, negative

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONFIG = json.loads((ROOT / 'scripts/ci/toolchain.json').read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def process(argv, log, timeout):
    # timeout kills/reaps the process group, including descendants.
    with log.open('w') as stream:
        child = subprocess.Popen(argv, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = child.wait(timeout=timeout)
            return {'argv': argv, 'exit_code': code, 'timed_out': False}
        except subprocess.TimeoutExpired:
            import signal
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
            return {'argv': argv, 'exit_code': child.returncode, 'timed_out': True}


def classify_import(text, result):
    if result['timed_out']:
        return 'failed', 'initialization_timeout'
    if result['exit_code'] in (139, -11):
        return 'blocked', 'known_initialization_139'
    if result['exit_code'] != 0 or 'ERROR:' in text or 'leak' in text.lower():
        return 'failed', 'initialization_failure'
    return 'passed', ''


def run(out, godot):
    out = pathlib.Path(out).resolve()
    if out.exists() and any(out.iterdir()):
        raise RuntimeError('OUT must be a new or empty directory; no cached retries')
    out.mkdir(parents=True, exist_ok=True)
    result = {'status': 'failed', 'toolchain': CONFIG, 'stages': {
        name: {'status': 'not_run'} for name in ('verify', 'import', 'positive', 'negative', 'audit_tests')},
        'fresh_scope': 'New project cache; shared SDK/XDG retained. Not an independent cold-environment stability test.',
        'source_commit': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip() if (ROOT / '.git').exists() else 'unavailable'}
    def save():
        (out / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    save()
    try:
        result['stages']['verify'] = {'status': 'failed'}
        if platform.system() != 'Linux' or platform.machine() != 'x86_64':
            raise RuntimeError('Only Linux x86_64 is supported')
        binary = pathlib.Path(shutil.which(godot) or godot).resolve()
        if digest(binary) != CONFIG['godot_binary_sha256']:
            raise RuntimeError('Expected the exact official Godot .NET executable')
        verification = process([str(binary), '--version'], out / 'version.log', 20)
        result['stages']['verify'].update(godot=str(binary), version_process=verification)
        save()
        if verification['exit_code'] != 0 or verification['timed_out'] or (out / 'version.log').read_text().strip() != CONFIG['godot_version']:
            raise RuntimeError('Godot version check failed')
        native = ROOT / 'demo/addons/godot_mujoco/bin'
        mujoco = native / 'libmujoco.so.3.16.0'
        extension = native / 'libgodot_mujoco.linux.template_debug.x86_64.so'
        if digest(mujoco) != CONFIG['mujoco_binary_sha256']:
            raise RuntimeError('Expected the pinned official MuJoCo 3.16.0 runtime')
        result['stages']['verify'] = {'status': 'passed', 'godot': str(binary),
            'version_process': verification, 'extension_sha256': digest(extension), 'mujoco_sha256': digest(mujoco)}
        project = out / 'project'
        project.mkdir()
        # Only small MjWorld fixtures, no Unitree assets or migration/G1 runners.
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Strict MjWorld smoke"\n')
        shutil.copy2(ROOT / 'demo/HeadlessTest.tscn', project)
        (project / 'scripts').mkdir()
        shutil.copy2(ROOT / 'demo/scripts/headless_smoke_test.gd', project / 'scripts')
        shutil.copytree(ROOT / 'demo/models', project / 'models')
        shutil.copytree(ROOT / 'demo/addons/godot_mujoco', project / 'addons/godot_mujoco')
        shutil.copy2(ROOT / 'tests/mjworld_smoke/invalid_qpos.gd', project)
        save()
        imp = process([str(binary), '--headless', '--editor', '--path', str(project), '--import', '--frame-delay', '1000'], out / 'import.log', 120)
        status, reason = classify_import((out / 'import.log').read_text(errors='replace'), imp)
        result['stages']['import'] = dict(imp, status=status, reason=reason)
        if status != 'passed':
            result['status'] = status
            return 3 if status == 'blocked' else 1
        for name, args, seconds, audit in (
            ('positive', ['res://HeadlessTest.tscn'], 120, positive),
            ('negative', ['--script', 'res://invalid_qpos.gd'], 30, negative),
        ):
            log = out / (name + '.log')
            record = process([str(binary), '--headless', '--path', str(project)] + args, log, seconds)
            record['status'] = 'failed'
            result['stages'][name] = record
            try:
                if record['timed_out']:
                    raise AssertionError('timeout')
                audit(log.read_text(errors='replace'), record['exit_code'])
                record['status'] = 'passed'
            except (AssertionError, ValueError) as error:
                record['error'] = str(error)
            save()
        record = process([sys.executable, '-m', 'unittest', 'discover', '-s', str(ROOT / 'tests/mjworld_smoke'), '-p', 'test_*.py'], out / 'audit-tests.log', 30)
        record['status'] = 'passed' if record['exit_code'] == 0 and not record['timed_out'] else 'failed'
        result['stages']['audit_tests'] = record
        result['status'] = 'passed' if all(s['status'] == 'passed' for s in result['stages'].values()) else 'failed'
        return 0 if result['status'] == 'passed' else 1
    except Exception as error:
        result['error'] = str(error)
        return 1
    finally:
        save()
        print(json.dumps({'status': result['status'], 'report': str(out / 'results.json')}))


if __name__ == '__main__':
    sys.exit(run(sys.argv[1], os.environ.get('GODOT_BIN', 'godot')))
