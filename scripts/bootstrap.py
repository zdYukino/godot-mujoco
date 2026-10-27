#!/usr/bin/env python3
"""下载、配置、检查并编译 / Download, configure, check and build."""
import argparse
import contextlib
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

from ci.install_godot import install as download_godot
from local_tools import (ADDONS, EXAMPLES, PINS, ROOT, THIRD_PARTY, ToolError,
                         check_addons, check_dotnet, digest, environment_script,
                         godot_binary, output, save_config, say, supported_platform,
                         tool_environment, write_atomic)


def confirm(chinese, english, yes=False):
    if yes:
        return True
    try:
        answer = input(f'{chinese} / {english} [y/N] ').strip().lower()
    except EOFError as error:
        raise ToolError('需要交互输入，或显式传入 --yes。 / Interactive input required, or pass --yes explicitly.') from error
    return answer in ('y', 'yes', '是')


def download(url, path, expected, algorithm):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        partial = path.with_suffix(path.suffix + '.part')
        say(f'下载 {path.name}', f'Downloading {url}')
        try:
            with urllib.request.urlopen(url, timeout=60) as source, partial.open('wb') as target:
                shutil.copyfileobj(source, target, 1024 * 1024)
            if digest(partial, algorithm) != expected:
                raise ToolError(f'下载校验失败。 / Download checksum mismatch: {url}')
            partial.replace(path)
        finally:
            partial.unlink(missing_ok=True)
    if digest(path, algorithm) != expected:
        raise ToolError(f'缓存校验失败，请移走该文件后重试。 / Invalid cache; move this file aside and retry: {path}')
    return path


def extract_tar(archive, destination):
    """Validate all names and link targets before extracting on Python 3.10+."""
    destination = destination.resolve()
    with tarfile.open(archive, 'r:gz') as package:
        entries = package.getmembers()
        for entry in entries:
            path = destination / entry.name
            if not path.resolve().is_relative_to(destination):
                raise ToolError('压缩包路径越界。 / Archive path escapes destination.')
            if not (entry.isfile() or entry.isdir() or entry.issym() or entry.islnk()):
                raise ToolError('压缩包包含不支持的特殊文件。 / Unsupported special file in archive.')
            if entry.issym() or entry.islnk():
                target = (path.parent if entry.issym() else destination) / entry.linkname
                if not target.resolve().is_relative_to(destination):
                    raise ToolError('压缩包链接越界。 / Archive link escapes destination.')
        # Symlinks can never be extraction parents. This also rejects link chains
        # that change the meaning of a later path after the initial validation.
        links = {Path(entry.name) for entry in entries if entry.issym() or entry.islnk()}
        for entry in entries:
            if any(parent in links for parent in Path(entry.name).parents):
                raise ToolError('压缩包通过链接写入目录。 / Archive writes through a link.')
        package.extractall(destination, members=entries)


def copy_tool(source, destination):
    source = source.resolve()
    # Dereference internal links so an imported installation remains independent.
    for path in source.rglob('*'):
        if path.is_symlink() and not path.resolve().is_relative_to(source):
            raise ToolError(f'工具包含外部链接。 / Tool contains an external link: {path}')
    shutil.copytree(source, destination)


def external_candidates():
    """Bounded discovery of normal install locations; never scan the filesystem."""
    candidates = {'godot': [], 'dotnet': []}
    for name in ('godot', 'godot-mono', 'godot4'):
        binary = shutil.which(name)
        if binary:
            candidates['godot'].append(Path(binary).resolve().parent)
    configured = os.environ.get('GODOT_BIN')
    if configured:
        binary = shutil.which(configured) or configured
        candidates['godot'].insert(0, Path(binary).expanduser().resolve().parent)
    home = Path.home()
    for parent in (home / 'software', home / '.local/opt'):
        if parent.is_dir():
            candidates['godot'].extend(sorted(parent.glob('Godot*')))
            candidates['godot'].extend(sorted(parent.glob('godot*')))
    candidates['godot'].extend((home / '.local/share/godot-mujoco/godot', Path('/opt/godot')))
    for variable in ('DOTNET_ROOT', 'DOTNET_ROOT_X64'):
        if os.environ.get(variable):
            candidates['dotnet'].append(Path(os.environ[variable]).expanduser())
    binary = shutil.which('dotnet')
    if binary:
        candidates['dotnet'].append(Path(binary).resolve().parent)
        try:
            text = output([binary, '--list-sdks'])
            for version, directory in re.findall(r'^(\S+)\s+\[([^\]]+)\]$', text, re.MULTILINE):
                if version == PINS['dotnet_sdk_version']:
                    candidates['dotnet'].append(Path(directory).parent)
        except (OSError, subprocess.SubprocessError):
            pass
    candidates['dotnet'].extend((home / '.dotnet', Path('/usr/share/dotnet'), Path('/usr/lib/dotnet')))
    return candidates


def inspect_environment():
    say('先检查当前环境（不下载、不安装）', 'Inspecting the current environment (no downloads or installation)')
    say(f'要求 Godot {PINS["godot_version"]}，.NET SDK {PINS["dotnet_sdk_version"]}', 'Required pinned tool versions')
    tools = {}
    # Check the repository tools first, even when environment.json was removed.
    candidates = external_candidates()
    for name in ('godot', 'dotnet'):
        local = THIRD_PARTY / name
        tools[name] = {'local': None, 'external': None}
        seen = set()
        for directory in [local] + candidates[name]:
            directory = Path(directory).expanduser().resolve()
            if directory in seen or not directory.is_dir():
                continue
            seen.add(directory)
            try:
                selected = godot_binary(directory) if name == 'godot' else check_dotnet(directory)
                selected = selected.parent if name == 'godot' else selected
            except (ToolError, OSError, subprocess.SubprocessError) as error:
                # Ignore unrelated common directories; show broken repository
                # installs and explicitly discovered SDK/Godot directories.
                if directory == local.resolve():
                    say(f'{name}：仓库工具不可用：{error}', f'{name}: repository installation needs repair')
                continue
            category = 'local' if selected.is_relative_to(local.resolve()) else 'external'
            tools[name][category] = selected
            version = PINS['godot_version'] if name == 'godot' else PINS['dotnet_sdk_version']
            say(f'{name}：已找到匹配版本 {version}，路径 {selected}', f'{name}: compatible installation found ({category})')
            break
        if not any(tools[name].values()):
            say(f'{name}：未找到匹配的完整安装', f'{name}: no compatible complete installation found')
    system_ready = True
    say(f'Python：{sys.version.split()[0]}，{sys.executable}', 'Python interpreter available')
    for name in ('git', 'cc', 'c++'):
        path = shutil.which(name)
        say(f'{name}：{path or "缺失"}', f'{name}: {"found" if path else "missing"}')
        system_ready = system_ready and bool(path)
    builder = shutil.which('make') or shutil.which('ninja')
    say(f'Make/Ninja：{builder or "缺失"}', f'Build tool: {"found" if builder else "missing"}')
    system_ready = system_ready and bool(builder)
    cmake = THIRD_PARTY / 'cmake' / f'cmake-{PINS["cmake_bootstrap_version"]}-linux-x86_64/bin/cmake'
    if not cmake.is_file():
        cmake = shutil.which('cmake')
    try:
        version = output([cmake, '--version']).splitlines()[0] if cmake else ''
        match = re.search(r'cmake version (\d+)\.(\d+)', version)
        cmake_ready = bool(match and tuple(map(int, match.groups())) >= tuple(map(int, PINS['cmake_minimum_version'].split('.'))))
    except (OSError, subprocess.SubprocessError):
        version, cmake_ready = '', False
    say(f'CMake：{version or "缺失"}，要求 >= {PINS["cmake_minimum_version"]}', f'CMake: {"ready" if cmake_ready else "needs installation/upgrade"}')
    try:
        check_addons()
        say('插件运行库：已存在；编译时仍会检查源码更新', 'Addon libraries exist; build will check source changes')
    except ToolError:
        say('插件运行库：缺失，需要编译并部署', 'Addon libraries are missing; build and staging required')
    return tools, system_ready and cmake_ready


def install_tool(name, source, *, reinstall=False):
    target = THIRD_PARTY / name
    validate = godot_binary if name == 'godot' else check_dotnet
    selected = None
    if source:
        selected = (godot_binary(source, check_version=False) if name == 'godot'
                    else check_dotnet(source))
        selected = selected.parent if name == 'godot' else selected
    if target.exists() and not reinstall:
        # Do not overwrite an incomplete or unrelated user directory.
        try:
            validate(target)
        except (ToolError, OSError, subprocess.SubprocessError) as error:
            raise ToolError(f'请移走无效目录后重试，原内容已保留。 / Move the invalid directory aside and retry: {target}\n{error}') from error
        say(f'复用 {name}', f'Reusing {target}')
        return target
    THIRD_PARTY.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f'.{name}-', dir=THIRD_PARTY) as temporary:
        stage = Path(temporary) / 'tool'
        if selected:
            if target.is_relative_to(selected):
                raise ToolError('源目录不能包含目标目录。 / Source directory cannot contain the destination.')
            say(f'复制 {name}', f'Copying {selected} to {target}')
            copy_tool(selected, stage)
        elif name == 'godot':
            say('下载并安装 Godot（校验缓存可复用）', 'Downloading/installing Godot; verified cache can be reused')
            extracted = Path(temporary) / 'extracted'
            binary = download_godot(extracted, archive_dir=THIRD_PARTY / 'cache')
            binary.parent.rename(stage)
        else:
            archive = download(PINS['dotnet_url'], THIRD_PARTY / 'cache' / 'dotnet-sdk.tar.gz',
                               PINS['dotnet_archive_sha512'], 'sha512')
            stage.mkdir()
            extract_tar(archive, stage)
        if name == 'godot':
            binary = stage / Path(PINS['godot_binary']).name
            binary.chmod(binary.stat().st_mode | 0o111)
        validate(stage)
        if target.exists():
            # Keep the original installation until the replacement validates.
            backup = Path(temporary) / 'previous'
            target.rename(backup)
            try:
                stage.rename(target)
                validate(target)
            except BaseException:
                if target.exists():
                    target.rename(stage)
                backup.rename(target)
                raise
        else:
            stage.rename(target)
    return target


def choose_source(name, argument, yes, detected):
    if argument:
        return argument, False
    local, external = detected['local'], detected['external']
    if yes:
        return (None if local else external), False
    say(f'配置 {name}', f'Configure {name}')
    say('1. 自动下载锁定版本', 'Download the pinned version')
    say('2. 指定已解压的完整目录', 'Use an existing extracted directory')
    if local:
        say('3. 复用仓库已有工具（默认）', 'Reuse the repository tool (default)')
    elif external:
        say(f'3. 导入已检测到的工具（默认）：{external}', 'Import the detected compatible installation (default)')
    default = '3' if local or external else '1'
    try:
        choice = input(f'选择 / Choice [{default}]: ').strip() or default
        if choice == '2':
            value = input('目录路径（无需引号） / Directory path (no quotes): ').strip()
            if not value:
                raise ToolError('目录不能为空。 / Directory must not be empty.')
            return value, False
        if choice == '1':
            say(f'已选择下载并安装 {name}；完成两项工具选择后开始执行', 'Selected download/install; execution starts after both tool choices')
            return None, True
        if choice == '3' and (local or external):
            return (None if local else external), False
    except EOFError as error:
        raise ToolError('需要交互输入，或显式传入 --yes。 / Interactive input required, or pass --yes explicitly.') from error
    raise ToolError('无效选择，请重新运行。 / Invalid choice; rerun the wizard.')


def os_release():
    values = {}
    for line in Path('/etc/os-release').read_text().splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            values[key] = value.strip('"')
    return values


def ensure_system_dependencies(yes):
    release = os_release()
    ubuntu = release.get('ID') == 'ubuntu' and release.get('VERSION_ID') in ('22.04', '24.04')
    missing = []
    for program, package in (('git', 'git'), ('cc', 'build-essential'), ('c++', 'build-essential')):
        if not shutil.which(program):
            missing.append(package)
    if not any(shutil.which(program) for program in ('make', 'ninja')):
        missing.append('make')
    if ubuntu:
        packages = ['ca-certificates', 'python3', 'libc6', 'libstdc++6', 'zlib1g',
                    'libfontconfig1', 'libx11-6', 'libxcursor1', 'libxinerama1',
                    'libxi6', 'libxrandr2', 'libxrender1', 'libgl1', 'libasound2' if release['VERSION_ID'] == '22.04' else 'libasound2t64',
                    'libicu70' if release['VERSION_ID'] == '22.04' else 'libicu74',
                    'libssl3' if release['VERSION_ID'] == '22.04' else 'libssl3t64',
                    'libgssapi-krb5-2']
        for package in packages:
            result = subprocess.run(['dpkg-query', '-W', '-f=${Status}', package],
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            if result.returncode or result.stdout.strip() != 'install ok installed':
                missing.append(package)
    if missing:
        missing = sorted(set(missing))
        if not ubuntu:
            raise ToolError('请手动安装缺少的系统依赖。 / Install missing system dependencies: ' + ', '.join(missing))
        say('需要安装系统依赖：' + ' '.join(missing), 'System dependencies required')
        if not confirm('允许使用 sudo apt-get 安装？', 'Allow sudo apt-get installation?', yes):
            raise ToolError('已取消，安装依赖后重试。 / Cancelled; install dependencies and retry.')
        prefix = [] if os.geteuid() == 0 else ['sudo']
        subprocess.run(prefix + ['apt-get', 'update'], check=True)
        subprocess.run(prefix + ['apt-get', 'install', '-y'] + missing, check=True)
    return ubuntu


def ensure_cmake(ubuntu):
    local = THIRD_PARTY / 'cmake' / f'cmake-{PINS["cmake_bootstrap_version"]}-linux-x86_64' / 'bin'
    minimum = tuple(map(int, PINS['cmake_minimum_version'].split('.')))
    for binary in (local / 'cmake', shutil.which('cmake')):
        if binary and Path(binary).is_file():
            version = re.search(r'cmake version (\d+)\.(\d+)\.(\d+)', output([binary, '--version']))
            if version and tuple(map(int, version.groups())) >= minimum:
                return str(local.relative_to(ROOT)) if Path(binary) == local / 'cmake' else None
    if not ubuntu:
        raise ToolError(f'请安装 CMake >= {PINS["cmake_minimum_version"]}。 / Install a newer CMake and rerun.')
    archive = download(PINS['cmake_url'], THIRD_PARTY / 'cache' / 'cmake.tar.gz',
                       PINS['cmake_archive_sha256'], 'sha256')
    target = THIRD_PARTY / 'cmake'
    if target.exists():
        raise ToolError(f'CMake 目录无效，请移走后重试。 / Invalid CMake directory; move aside and retry: {target}')
    with tempfile.TemporaryDirectory(prefix='.cmake-', dir=THIRD_PARTY) as temporary:
        stage = Path(temporary) / 'tool'
        stage.mkdir()
        extract_tar(archive, stage)
        binary = stage / local.relative_to(target) / 'cmake'
        if f'cmake version {PINS["cmake_bootstrap_version"]}' not in output([binary, '--version']):
            raise ToolError('CMake 版本校验失败。 / CMake version mismatch.')
        stage.rename(target)
    return str(local.relative_to(ROOT))


def update_profile(path, block):
    start, end = '# >>> godot-mujoco >>>', '# <<< godot-mujoco <<<'
    text = path.read_text() if path.exists() else ''
    pattern = re.compile(r'(?m)^' + re.escape(start) + r'\n.*?^' + re.escape(end) + r'\n?', re.DOTALL)
    if (start in text or end in text) and not pattern.search(text):
        raise ToolError(f'环境配置标记不完整，请修复后重试。 / Incomplete managed profile block: {path}')
    replacement = f'{start}\n{block}{end}\n'
    if pattern.search(text):
        text = pattern.sub(lambda match: replacement, text)
    else:
        text = text.rstrip('\n') + '\n\n' + replacement
    write_atomic(path, text)


def install_terminal(config):
    home = Path.home()
    env_file = THIRD_PARTY / 'environment.sh'
    write_atomic(env_file, environment_script(config))
    for name, command in (('godot', '"$GODOT_BIN"'), ('dotnet', '"$DOTNET_ROOT/dotnet"')):
        wrapper = '#!/bin/sh\nset -eu\n'
        wrapper += f'if [ ! -f {shlex.quote(str(env_file))} ]; then\n'
        wrapper += '  echo "仓库已移动，请重新运行 boostup.sh。 / Repository moved; rerun boostup.sh." >&2\n  exit 2\nfi\n'
        wrapper += f'. {shlex.quote(str(env_file))}\nexec {command} "$@"\n'
        write_atomic(home / '.local/bin' / name, wrapper, 0o755)
    block = f'if [ -f {shlex.quote(str(env_file))} ]; then\n    . {shlex.quote(str(env_file))}\nfi\n'
    # Bash interactive shells and login shells both load the same managed block.
    for name in ('.bashrc', '.profile'):
        update_profile(home / name, block)
    # Bash ignores .profile if one of these already exists.
    for name in ('.bash_profile', '.bash_login'):
        if (home / name).exists():
            update_profile(home / name, block)
            break


def stage_examples():
    for name in EXAMPLES:
        project = ROOT / 'examples' / name
        if not (project / 'project.godot').is_file():
            raise ToolError(f'例程缺少工程源码。 / Missing example project source: {project}')
        target = project / 'addons'
        if target.is_symlink() and target.resolve() == ADDONS.resolve():
            continue
        if target.is_symlink() and target.resolve() == ROOT / 'demo/addons':
            # Migrate only the known old shared link; preserve user addon folders.
            target.unlink()
        if target.exists() or target.is_symlink():
            raise ToolError(f'例程 addons 已存在且不是共享链接，请移走后重试。 / Existing example addons preserved: {target}')
        target.symlink_to(os.path.relpath(ADDONS, project), target_is_directory=True)
    assets = ROOT / 'examples/pendulum/assets'
    if not assets.exists() and not assets.is_symlink():
        assets.symlink_to('../../assets', target_is_directory=True)


@contextlib.contextmanager
def installation_lock():
    import fcntl
    THIRD_PARTY.mkdir(parents=True, exist_ok=True)
    with (THIRD_PARTY / '.boostup.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ToolError('另一个安装向导正在运行。 / Another boostup process is running.') from error
        yield


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot-dir', type=Path, help='已有 Godot Mono 解压目录 / Existing extracted Godot Mono directory')
    parser.add_argument('--dotnet-dir', type=Path, help='已有 .NET SDK 目录 / Existing .NET SDK directory')
    parser.add_argument('--yes', action='store_true', help='接受操作，优先复用或导入已有工具 / Accept operations; prefer existing compatible tools')
    parser.add_argument('--build-dir', type=Path, default=ROOT / 'build-linux', help='构建目录 / Build directory')
    parser.add_argument('--mujoco-root', type=Path, default=os.environ.get('MUJOCO_SDK_DIR') or None, help='可选本地 MuJoCo SDK / Optional local MuJoCo SDK')
    parser.add_argument('--jobs', type=int, default=2, help='编译并行数，默认 2 / Parallel build jobs, default 2')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--rebuild', action='store_true', help='复用仓库工具直接编译，跳过安装菜单 / Build with repository tools without install menus')
    mode.add_argument('--configure', action='store_true', help='重新选择工具来源 / Choose tool installation sources again')
    mode.add_argument('--check', action='store_true', help='只检查现有环境，不安装或编译 / Inspect only; no installation or build')
    args = parser.parse_args(argv)
    try:
        supported_platform()
        if sys.version_info < (3, 10) or args.jobs < 1:
            raise ToolError('需要 Python 3.10+ 且 jobs 必须为正数。 / Python 3.10+ and positive jobs are required.')
        detected, system_ready = inspect_environment()
        repository_ready = all(detected[name]['local'] for name in ('godot', 'dotnet'))
        if args.check:
            return 0 if system_ready and all(any(item.values()) for item in detected.values()) else 2
        if args.rebuild and not repository_ready:
            raise ToolError('仓库工具尚未就绪，请运行 ./boostup.sh --configure。 / Repository tools are not ready; run ./boostup.sh --configure.')
        rebuilding = repository_ready and not args.configure and not (args.godot_dir or args.dotnet_dir)
        if rebuilding:
            say('Godot 和 .NET 已就绪，直接编译；需要重新安装时使用 --configure', 'Godot and .NET are ready; building directly. Use --configure to reinstall.')
            godot_source = dotnet_source = None
            godot_reinstall = dotnet_reinstall = False
        else:
            godot_source, godot_reinstall = choose_source('godot', args.godot_dir, args.yes, detected['godot'])
            dotnet_source, dotnet_reinstall = choose_source('dotnet', args.dotnet_dir, args.yes, detected['dotnet'])
        say(f'工具位置：{THIRD_PARTY}', 'Tools will be stored under third_party')
        say('将配置用户 godot/dotnet 命令、Bash 环境，并检查、编译和部署插件。',
            'Configure user godot/dotnet commands and Bash profiles; check, build and stage the addon.')
        say('现有命令入口将被替换；不删除已有软件或用户数据。',
            'Existing command launchers will be replaced; existing software and user data are retained.')
        if not rebuilding and not confirm('开始配置？', 'Start setup?', args.yes):
            return 0
        with installation_lock():
            ubuntu = ensure_system_dependencies(args.yes)
            cmake_bin = ensure_cmake(ubuntu)
            godot = install_tool('godot', godot_source, reinstall=godot_reinstall)
            dotnet = install_tool('dotnet', dotnet_source, reinstall=dotnet_reinstall)
            config = dict(pins=PINS, godot_bin=str(godot_binary(godot).relative_to(ROOT)),
                          dotnet_root=str(dotnet.relative_to(ROOT)), cmake_bin=cmake_bin, built=False)
            save_config(config)
            env = tool_environment(config)
            common = ['--build-dir', str(args.build_dir.expanduser().resolve())]
            if args.mujoco_root:
                common += ['--mujoco-root', str(args.mujoco_root.expanduser().resolve())]
            say('检查环境', 'Checking environment')
            subprocess.run([sys.executable, str(ROOT / 'scripts/setup.py'), 'check'] + common, env=env, check=True)
            say('编译并部署插件', 'Building and staging the addon')
            if not (args.build_dir.expanduser().resolve() / 'CMakeCache.txt').is_file():
                say('构建目录不存在或已清空，将重新配置并完整编译；首次获取依赖需要联网', 'Build cache is missing; configuring and compiling from scratch, with network needed for uncached dependencies')
            subprocess.run([sys.executable, str(ROOT / 'scripts/setup.py'), 'build'] + common + ['--jobs', str(args.jobs)], env=env, check=True)
            check_addons()
            stage_examples()
            install_terminal(config)
            config['built'] = True
            save_config(config)
        say('配置和编译完成。', 'Setup and build completed.')
        say('新终端可直接运行 godot、dotnet；当前终端可执行：', 'New terminals can use godot/dotnet; for this terminal run:')
        print('source ' + shlex.quote(str(THIRD_PARTY / 'environment.sh')))
        print(f'{ROOT / "em_run.sh"}\n{ROOT / "em_run.sh"} --exp\n{ROOT / "em_run.sh"} --new my-project')
        return 0
    except subprocess.CalledProcessError as error:
        if error.output:
            print(error.output, file=sys.stderr)
        say(f'命令失败（{error.returncode}），修复后重跑 ./boostup.sh。', 'Command failed; fix the issue and rerun ./boostup.sh.')
        return error.returncode if error.returncode > 0 else 128 - error.returncode
    except (ToolError, OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        print(f'{error}\n配置未完成；修复后重跑 ./boostup.sh。 / Setup incomplete; fix the issue and rerun ./boostup.sh.', file=sys.stderr)
        return 2
    except (KeyboardInterrupt, EOFError):
        print('\n已取消，可重新运行。 / Cancelled; rerun when ready.', file=sys.stderr)
        return 130


if __name__ == '__main__':
    sys.exit(main())
