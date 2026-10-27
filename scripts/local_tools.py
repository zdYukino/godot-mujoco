"""Shared repository-local tool configuration for boostup and em_run."""
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
THIRD_PARTY = ROOT / 'third_party'
STATE = THIRD_PARTY / 'environment.json'
PINS = json.loads((ROOT / 'scripts/ci/toolchain.json').read_text())
ADDONS = ROOT / 'addons'
NATIVE = 'libgodot_mujoco.linux.template_debug.x86_64.so'
EXAMPLES = ('shape_gallery', 'g1_passive', 'sdf_terrain', 'pendulum')


class ToolError(Exception):
    pass


def say(chinese, english):
    print(f'{chinese} / {english}', flush=True)


def supported_platform():
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        raise ToolError('仅支持 Linux x86_64。 / Only Linux x86_64 is supported.')


def digest(path, algorithm='sha256'):
    value = hashlib.new(algorithm)
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def output(argv, **kwargs):
    return subprocess.check_output([str(arg) for arg in argv], text=True,
                                   stderr=subprocess.STDOUT, timeout=30, **kwargs).strip()


def godot_binary(directory, check_version=True):
    directory = Path(directory).expanduser().resolve()
    name = Path(PINS['godot_binary']).name
    candidates = [directory / name] + sorted(directory.glob(f'*/{name}'))
    found = [path for path in candidates if path.is_file()]
    if len(found) != 1:
        raise ToolError(f'请选择完整的 Godot Mono 解压目录。 / Select the complete extracted Godot Mono directory: {directory}')
    binary = found[0]
    sharp = binary.parent / 'GodotSharp'
    if not all((sharp / part).is_dir() and any((sharp / part).rglob('*.dll'))
               for part in ('Api', 'Tools')):
        raise ToolError(f'GodotSharp 不完整。 / Incomplete GodotSharp directory: {sharp}')
    if digest(binary) != PINS['godot_binary_sha256']:
        raise ToolError('Godot 校验失败，请使用锁定的官方 Mono 版本。 / Godot checksum mismatch; use the pinned official Mono build.')
    if check_version and output([binary, '--version']) != PINS['godot_version']:
        raise ToolError(f'Godot 版本必须为 / Required Godot version: {PINS["godot_version"]}')
    return binary


def dotnet_environment(directory, base=None):
    env = dict(os.environ if base is None else base)
    env.update(DOTNET_ROOT=str(directory), DOTNET_ROOT_X64=str(directory),
               DOTNET_MULTILEVEL_LOOKUP='0')
    env['PATH'] = str(directory) + os.pathsep + env.get('PATH', '')
    return env


def check_dotnet(directory):
    directory = Path(directory).expanduser().resolve()
    version = PINS['dotnet_sdk_version']
    if not (directory / 'dotnet').is_file() or not (directory / 'sdk' / version / 'dotnet.dll').is_file():
        raise ToolError(f'需要完整的 .NET SDK {version} 目录。 / Complete .NET SDK {version} directory required: {directory}')
    env = dotnet_environment(directory)
    if output([directory / 'dotnet', '--version'], env=env, cwd=ROOT) != version:
        raise ToolError(f'.NET SDK 版本必须为 / Required .NET SDK version: {version}')
    return directory


def tool_environment(config):
    # All persisted paths are repository-relative, so the scripts survive a move.
    env = dotnet_environment(local_path(config['dotnet_root']))
    env['GODOT_BIN'] = str(local_path(config['godot_bin']))
    if config.get('cmake_bin'):
        env['PATH'] = str(local_path(config['cmake_bin'])) + os.pathsep + env['PATH']
    return env


def local_path(relative):
    path = (ROOT / relative).resolve()
    if not path.is_relative_to(THIRD_PARTY.resolve()):
        raise ToolError('工具配置路径必须位于 third_party。 / Configured tools must be under third_party.')
    return path


def load_config(require_build=False):
    try:
        config = json.loads(STATE.read_text())
        if config['pins'] != PINS:
            raise ValueError('toolchain pins changed')
        godot_binary(local_path(config['godot_bin']).parent)
        check_dotnet(local_path(config['dotnet_root']))
        if require_build:
            if not config.get('built'):
                raise ValueError('build not completed')
            check_addons()
        return config
    except (OSError, ValueError, KeyError, ToolError, subprocess.SubprocessError) as error:
        raise ToolError(f'环境未就绪，请运行 {ROOT / "boostup.sh"}。 / Environment not ready; run boostup.sh.\n{error}') from error


def check_addons():
    for relative in (f'godot_mujoco/bin/{NATIVE}',
                     f'godot_mujoco/bin/libmujoco.so.{PINS["mujoco_version"]}',
                     'godot_mujoco/godot_mujoco.gdextension', 'mujoco_editor/plugin.cfg'):
        if not (ADDONS / relative).is_file():
            raise ToolError(f'插件缺失，请运行 ./boostup.sh。 / Missing addon; run ./boostup.sh: {relative}')


def write_atomic(path, content, mode=None):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.gmj-tmp')
    try:
        temporary.write_text(content)
        if mode is not None:
            temporary.chmod(mode)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def save_config(config):
    write_atomic(STATE, json.dumps(config, indent=2) + '\n')


def environment_script(config):
    env = tool_environment(config)
    paths = [str(Path.home() / '.local/bin')]
    if config.get('cmake_bin'):
        paths.append(str(local_path(config['cmake_bin'])))
    paths.append(str(local_path(config['dotnet_root'])))
    lines = ['# Generated by godot-mujoco boostup.sh; rerun after moving the repository.']
    for name in ('GODOT_BIN', 'DOTNET_ROOT', 'DOTNET_ROOT_X64', 'DOTNET_MULTILEVEL_LOOKUP'):
        lines.append(f'export {name}={shlex.quote(env[name])}')
    lines.append('export PATH=' + shlex.quote(os.pathsep.join(paths)) + ':"$PATH"')
    return '\n'.join(lines) + '\n'
