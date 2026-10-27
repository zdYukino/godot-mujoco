#!/usr/bin/env python3
"""Check, build and smoke-test the pinned Linux toolchain without host setup."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / 'scripts/ci/toolchain.json').read_text())
INSTALL_GUIDE = ROOT / 'docs/linux-install.zh-CN.md'


class SetupError(Exception):
    pass


def sha256(path):
    with path.open('rb') as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
        return digest.hexdigest()


def executable(name, fix):
    found = shutil.which(name)
    if not found:
        raise SetupError(f'Cannot execute {name!r}. {fix}')
    return str(Path(found).resolve())


def capture(argv, **kwargs):
    return subprocess.run(argv, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=30, **kwargs).stdout.strip()


def exit_status(code):
    return code if code >= 0 else 128 - code


def read_cache(build_dir):
    cache = build_dir / 'CMakeCache.txt'
    values = {}
    if cache.is_file():
        for line in cache.read_text().splitlines():
            match = re.match(r'^([^#/:][^:]*):[^=]+=(.*)$', line)
            if match:
                values[match[1]] = match[2]
    return values


def check_cache(cache, sdk):
    expected = {
        'CMAKE_HOME_DIRECTORY': str(ROOT),
        'MUJOCO_VERSION': CONFIG['mujoco_version'],
        'GODOT_CPP_TAG': CONFIG['godot_cpp_tag'],
        'GODOTCPP_TARGET': 'template_debug',
        'GODOTCPP_PRECISION': 'single',
        'GMJ_ADDON_BIN': str(ROOT / 'addons/godot_mujoco/bin'),
    }
    for key, value in expected.items():
        if key in cache and cache[key] != value:
            if key == 'GMJ_ADDON_BIN' and cache[key] == str(ROOT / 'demo/addons/godot_mujoco/bin'):
                print('[setup] Migrating the previous addon staging path to <repo>/addons on build.', flush=True)
                continue
            raise SetupError(f'CMake cache conflict: {key}={cache[key]!r}, expected {value!r}. '
                             'Use a new --build-dir; the existing cache was preserved.')
    cached_sdk = cache.get('GMJ_MUJOCO_ROOT', '')
    if cache and (str(Path(cached_sdk).resolve()) if cached_sdk else '') != (str(sdk) if sdk else ''):
        raise SetupError('CMake cache uses a different MuJoCo SDK/download mode. '
                         'Use a new --build-dir or select the original --mujoco-root.')
    if sdk and cache.get('MUJOCO_LINK_LIB') and Path(cache['MUJOCO_LINK_LIB']).resolve() != (sdk / 'lib/libmujoco.so').resolve():
        raise SetupError('Cached MUJOCO_LINK_LIB differs from the requested SDK. Use a new --build-dir.')
    for key in ('GMJ_BUILD_MUJOCO_FROM_SOURCE', 'GMJ_ALLOW_UNVERIFIED', 'CMAKE_CROSSCOMPILING'):
        if cache.get(key, '').upper() in ('ON', 'TRUE', 'YES', '1'):
            raise SetupError(f'CMake cache has {key} enabled. Use a new --build-dir for this baseline.')
    requested_generator = os.environ.get('CMAKE_GENERATOR')
    if requested_generator and cache.get('CMAKE_GENERATOR', requested_generator) != requested_generator:
        raise SetupError('CMAKE_GENERATOR conflicts with the cache. Use a new --build-dir.')
    if cache.get('CMAKE_TOOLCHAIN_FILE'):
        raise SetupError('A cross/custom toolchain cache is not supported by setup. Use a new --build-dir.')


def check_sdk(sdk):
    if sdk is None:
        print('[setup] MuJoCo: pinned CMake download (godot-cpp also needs network on first build)', flush=True)
        return
    header = sdk / 'include/mujoco/mujoco.h'
    library = sdk / f'lib/libmujoco.so.{CONFIG["mujoco_version"]}'
    linker_library = sdk / 'lib/libmujoco.so'
    if not all(path.is_file() for path in (header, library, linker_library)):
        raise SetupError(f'Invalid MuJoCo SDK at {sdk}. Extract the official Linux x86_64 SDK '
                         'and pass its include/lib parent with --mujoco-root.')
    major, minor, patch = map(int, CONFIG['mujoco_version'].split('.'))
    version = re.search(r'^\s*#define\s+mjVERSION_HEADER\s+(\d+)\b', header.read_text(), re.MULTILINE)
    if not version or int(version[1]) != major * 1000000 + minor * 1000 + patch:
        raise SetupError(f'MuJoCo SDK headers must be version {CONFIG["mujoco_version"]}.')
    for path in {library.resolve(), linker_library.resolve()}:
        if sha256(path) != CONFIG['mujoco_binary_sha256']:
            raise SetupError(f'MuJoCo SDK runtime checksum mismatch: {path}. Use the pinned official SDK.')
    print(f'[setup] MuJoCo SDK: {sdk} (official runtime verified)', flush=True)


def compiler(language, cache):
    env_name, cache_name, defaults = (
        ('CC', 'CMAKE_C_COMPILER', ('cc', 'gcc', 'clang')) if language == 'c' else
        ('CXX', 'CMAKE_CXX_COMPILER', ('c++', 'g++', 'clang++')))
    configured = os.environ.get(env_name) or cache.get(cache_name)
    if configured:
        # An executable path with spaces is one argument; compiler+flags use shell quoting.
        argv = [configured] if Path(configured).is_file() else shlex.split(configured)
    else:
        argv = [next((name for name in defaults if shutil.which(name)), defaults[0])]
    if not argv:
        raise SetupError(f'Invalid {env_name}. Set it to a C/C++ compiler executable.')
    argv[0] = executable(argv[0], f'Install a C/C++17 toolchain or set {env_name}.')
    if os.environ.get(env_name) and cache.get(cache_name):
        # CMake does not switch compilers in an existing cache when CC/CXX changes.
        cached = str(Path(cache[cache_name]).resolve())
        if argv[0] != cached or len(argv) > 1:
            raise SetupError(f'{env_name} differs from the cached compiler. Use a new --build-dir.')
    source = '#include <optional>\nstatic_assert(__cplusplus >= 201703L);\nint main() { std::optional<int> x; }' if language == 'c++' else 'int main(void) { return 0; }'
    flags = ['-std=c++17'] if language == 'c++' else []
    try:
        capture(argv + flags + ['-fsyntax-only', '-x', language, '-'], input=source)
    except subprocess.CalledProcessError as error:
        raise SetupError(f'{env_name} compiler check failed. Install a working C/C++17 toolchain '
                         f'or set {env_name}.\n{error.stdout}') from error


def check_environment(cache):
    if sys.version_info < (3, 10):
        raise SetupError('Python 3.10+ is required. Install it and select python3 on PATH.')
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        raise SetupError('This setup supports Linux x86_64 only.')
    executable('git', 'Install git and add it to PATH.')
    cmake = executable('cmake', 'Install CMake >=3.24 and add it to PATH.')
    version = re.search(r'cmake version (\d+)\.(\d+)', capture([cmake, '--version']))
    minimum = tuple(map(int, CONFIG['cmake_minimum_version'].split('.')))
    if not version or tuple(map(int, version.groups())) < minimum:
        raise SetupError(f'CMake >={CONFIG["cmake_minimum_version"]} is required. Select a newer cmake on PATH.')
    generator = cache.get('CMAKE_GENERATOR') or os.environ.get('CMAKE_GENERATOR')
    if not generator:
        generator = 'Unix Makefiles' if shutil.which('make') else 'Ninja'
    if generator not in ('Unix Makefiles', 'Ninja'):
        raise SetupError('Select CMAKE_GENERATOR="Unix Makefiles" or "Ninja" for this Linux setup.')
    executable(cache.get('CMAKE_MAKE_PROGRAM') or ('ninja' if generator == 'Ninja' else 'make'),
               'Install make or ninja; CMAKE_GENERATOR=Ninja selects Ninja for a new build directory.')
    compiler('c', cache)
    compiler('c++', cache)
    godot = executable(os.environ.get('GODOT_BIN') or 'godot',
                       'Set GODOT_BIN=/absolute/path/to/the/official/Godot.NET executable.')
    if capture([godot, '--version']) != CONFIG['godot_version']:
        raise SetupError(f'Expected Godot {CONFIG["godot_version"]}. Set GODOT_BIN to that .NET executable.')
    if sha256(Path(godot)) != CONFIG['godot_binary_sha256']:
        raise SetupError('Godot executable checksum mismatch. Set GODOT_BIN directly to the official '
                         '.NET executable (or a symlink), rather than a launcher script.')
    dotnet = executable('dotnet', f'Install .NET SDK {CONFIG["dotnet_sdk_version"]}; set DOTNET_ROOT and PATH.')
    if capture([dotnet, '--version'], cwd=ROOT) != CONFIG['dotnet_sdk_version']:
        raise SetupError(f'Select .NET SDK {CONFIG["dotnet_sdk_version"]} via DOTNET_ROOT/PATH or global.json.')
    print(f'[setup] Linux x86_64; Godot {CONFIG["godot_version"]}; .NET SDK {CONFIG["dotnet_sdk_version"]}', flush=True)
    print(f'[setup] Godot: {godot}\n[setup] CMake: {cmake}; generator: {generator}', flush=True)
    return cmake, generator, godot


def positive_int(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError('must be a positive integer')
    return number


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('check', 'build'):
        command = commands.add_parser(name, help='Check the environment' if name == 'check' else 'Check, configure and build')
        command.add_argument('--build-dir', type=Path, default=ROOT / 'build-linux', help='CMake directory (default: <repo>/build-linux)')
        command.add_argument('--mujoco-root', type=Path, default=os.environ.get('MUJOCO_SDK_DIR') or None,
                             help='Official SDK include/lib parent (default: MUJOCO_SDK_DIR, otherwise download)')
        if name == 'build':
            command.add_argument('--jobs', type=positive_int, default=2, help='Parallel build jobs (default: 2)')
    smoke = commands.add_parser('smoke', help='Check tools and run the existing strict isolated smoke (no build)')
    smoke.add_argument('--out', type=Path, default=os.environ.get('OUT') or None,
                       help='New/empty report directory (default: OUT, otherwise a fresh temp directory)')
    args = parser.parse_args(argv)
    try:
        cache = {}
        sdk = None
        if args.command != 'smoke':
            args.build_dir = args.build_dir.expanduser().resolve()
            if args.mujoco_root is not None:
                sdk = args.mujoco_root.expanduser().resolve()
            cache = read_cache(args.build_dir)
            check_cache(cache, sdk)
        cmake, generator, godot = check_environment(cache)
        if args.command == 'smoke':
            out = args.out.expanduser().resolve() if args.out else Path(tempfile.mkdtemp(prefix='gmj-smoke-'))
            if out.exists() and (not out.is_dir() or any(out.iterdir())):
                raise SetupError('Smoke --out/OUT must be new or empty. Existing results were preserved.')
            print(f'[setup] Smoke results: {out}', flush=True)
            env = dict(os.environ, GODOT_BIN=godot, OUT=str(out), PYTHONDONTWRITEBYTECODE='1')
            return exit_status(subprocess.run(['bash', str(ROOT / 'tests/mjworld_smoke/run.sh')], env=env).returncode)
        check_sdk(sdk)
        print(f'[setup] Build directory: {args.build_dir}', flush=True)
        if args.command == 'check':
            print('[setup] Environment OK; no downloads or build files created.', flush=True)
            return 0
        configure = [cmake, '-S', str(ROOT), '-B', str(args.build_dir), '-G', generator,
                     f'-DGMJ_ADDON_BIN:PATH={ROOT / "addons/godot_mujoco/bin"}',
                     f'-DMUJOCO_VERSION={CONFIG["mujoco_version"]}', f'-DGODOT_CPP_TAG={CONFIG["godot_cpp_tag"]}',
                     '-DGMJ_BUILD_MUJOCO_FROM_SOURCE=OFF', '-DGMJ_ALLOW_UNVERIFIED=OFF',
                     f'-DGMJ_MUJOCO_ROOT:PATH={sdk or ""}']
        subprocess.run(configure, check=True)
        subprocess.run([cmake, '--build', str(args.build_dir), '--parallel', str(args.jobs)], check=True)
        print(f'[setup] Built addon: {ROOT / "addons/godot_mujoco"}', flush=True)
        print('[setup] Next: bash scripts/setup.sh smoke; then open the editor for GUI verification.', flush=True)
        return 0
    except SetupError as error:
        print(f'[setup] {error}\nInstallation guide: {INSTALL_GUIDE}', file=sys.stderr)
        return 2
    except subprocess.CalledProcessError as error:
        if error.stdout:
            print(error.stdout, file=sys.stderr)
        print(f'[setup] Command failed ({error.returncode}): {shlex.join(error.cmd)}', file=sys.stderr)
        return exit_status(error.returncode)
    except subprocess.TimeoutExpired as error:
        print(f'[setup] Tool check timed out: {shlex.join(error.cmd)}', file=sys.stderr)
        return 124
    except OSError as error:
        print(f'[setup] {error}\nInstallation guide: {INSTALL_GUIDE}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
