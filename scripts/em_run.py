#!/usr/bin/env python3
"""启动 Godot、例程或新工程 / Open Godot, an example, or a new project."""
import argparse
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

from local_tools import (ADDONS, EXAMPLES, ROOT, ToolError, check_addons,
                         load_config, say, supported_platform, tool_environment)


def create_project(name):
    # Keep all user-created projects inside the ignored workspace directory.
    if (not name.strip() or name in ('.', '..') or len(name) > 120
            or any(char in '/\\' or ord(char) < 32 or ord(char) == 127 for char in name)):
        raise ToolError('工程名必须是单个目录名，不可包含路径。 / Project name must be a single directory name, not a path.')
    parent = ROOT / 'projects'
    if parent.is_symlink():
        raise ToolError('projects 不能是外部链接。 / projects must not be a symlink.')
    destination = parent / name
    if destination.exists() or destination.is_symlink():
        raise ToolError(f'工程目录已存在，内容已保留。 / Project directory exists; contents preserved: {destination}')
    check_addons()
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.new-', dir=parent) as temporary:
        stage = Path(temporary) / 'project'
        shutil.copytree(ROOT / 'examples/templates/new_project', stage)
        project_file = stage / 'project.godot'
        project_file.write_text(project_file.read_text().replace('__PROJECT_NAME__', json.dumps(name, ensure_ascii=False)))
        shutil.copy2(ROOT / 'global.json', stage / 'global.json')
        ignore = shutil.ignore_patterns('.godot', 'obj', '__pycache__', '*.pyc', '.DS_Store')
        for addon in ('godot_mujoco', 'mujoco_editor'):
            shutil.copytree(ADDONS / addon, stage / 'addons' / addon, ignore=ignore)
        # rename is atomic and never merges or partially overwrites a project.
        stage.rename(destination)
    say(f'已创建工程：{destination}', 'Project created; press F5 in the editor to simulate')
    return destination


def choose_example():
    for index, name in enumerate(EXAMPLES, 1):
        print(f'{index}. {name}')
    try:
        choice = input('选择例程（序号或名称） / Select example (number or name): ').strip()
    except EOFError as error:
        raise ToolError('请指定例程名称，例如 --exp shape_gallery。 / Specify an example, e.g. --exp shape_gallery.') from error
    if choice.isdigit() and 1 <= int(choice) <= len(EXAMPLES):
        return EXAMPLES[int(choice) - 1]
    if choice in EXAMPLES:
        return choice
    raise ToolError('无效例程名称。 / Invalid example. ' + ', '.join(EXAMPLES))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--exp', nargs='?', const='', metavar='NAME',
                       help='打开例程，省略名称则交互选择 / Open example; omit NAME to choose interactively')
    group.add_argument('--new', metavar='PROJECT_NAME', help='创建带插件的工程 / Create a project with the addon')
    args = parser.parse_args(argv)
    try:
        supported_platform()
        if args.exp is not None and args.exp and args.exp not in EXAMPLES:
            raise ToolError('无效例程名称。 / Invalid example. ' + ', '.join(EXAMPLES))
        config = load_config(require_build=True)
        env = tool_environment(config)
        command = [env['GODOT_BIN']]
        project = None
        if args.new is not None:
            project = create_project(args.new)
        elif args.exp is not None:
            name = args.exp or choose_example()
            project = ROOT / 'examples' / name
            if not (project / 'project.godot').is_file() or not (project / 'addons/godot_mujoco').is_dir():
                raise ToolError('例程未就绪，请运行 ./boostup.sh。 / Example not ready; run ./boostup.sh.')
        if not (os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY')):
            message = '没有图形会话，请在桌面终端重试。 / No graphical session; retry from a desktop terminal.'
            if project:
                message += f'\n工程已保留 / Project retained: {project}'
            raise ToolError(message)
        if project:
            command += ['--editor', '--path', str(project), '--rendering-method', 'gl_compatibility']
        else:
            command += ['--project-manager', '--rendering-method', 'gl_compatibility']
        # Do not inherit the caller's directory as an implicit Godot project.
        os.chdir(ROOT)
        os.execve(command[0], command, env)
        return 0
    except (ToolError, OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print('\n已取消。 / Cancelled.', file=sys.stderr)
        return 130


if __name__ == '__main__':
    sys.exit(main())
