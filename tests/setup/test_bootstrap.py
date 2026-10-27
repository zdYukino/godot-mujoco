"""Bootstrap/launcher contracts using isolated tools, homes and download fixtures."""
import contextlib
import hashlib
import importlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
tools = importlib.import_module('local_tools')
bootstrap = importlib.import_module('bootstrap')
launcher = importlib.import_module('em_run')
ENSURE_CMAKE = bootstrap.ensure_cmake

GODOT = '#!/bin/sh\necho 4.7.2.stable.mono.official.ed1daf0bf\n'
DOTNET = '#!/bin/sh\necho 8.0.426\n'
CMAKE = f'#!{sys.executable}\n' + '''import os, pathlib, sys
if '--version' in sys.argv:
    print('cmake version 3.31.10')
elif '--build' in sys.argv:
    status = int(os.environ.get('TEST_BUILD_EXIT', '0'))
    if status:
        sys.exit(status)
    target = pathlib.Path(os.environ['TEST_REPO_ROOT']) / 'addons/godot_mujoco/bin'
    target.mkdir(parents=True, exist_ok=True)
    for name in ('libgodot_mujoco.linux.template_debug.x86_64.so', 'libmujoco.so.3.16.0'):
        (target / name).write_text('native fixture')
'''


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='gmj bootstrap test ')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'repo with spaces'
        for name in ('scripts', 'examples/templates'):
            shutil.copytree(ROOT / name, self.root / name, ignore=shutil.ignore_patterns('__pycache__'))
        shutil.copy2(ROOT / 'global.json', self.root / 'global.json')
        self.third = self.root / 'third_party'
        self.home = self.base / 'home'
        self.home.mkdir()
        (self.home / '.bashrc').write_text('# keep my shell settings\n')
        self.bin = self.base / 'system tools'
        self.bin.mkdir()
        for name, text in (('cmake', CMAKE), ('git', '#!/bin/sh\nexit 0\n'), ('make', '#!/bin/sh\nexit 0\n'),
                           ('cc', '#!/bin/sh\nexit 0\n'), ('c++', '#!/bin/sh\nexit 0\n')):
            path = self.bin / name
            path.write_text(text)
            path.chmod(0o755)
        self.source = self.base / 'extracted tools'
        self.godot = self.source / 'godot'
        self.godot.mkdir(parents=True)
        binary_name = Path(tools.PINS['godot_binary']).name
        executable = self.godot / binary_name
        executable.write_text(GODOT)
        executable.chmod(0o755)
        for part in ('Api/Debug', 'Tools'):
            path = self.godot / 'GodotSharp' / part
            path.mkdir(parents=True)
            (path / 'Godot.dll').write_bytes(b'managed fixture')
        self.dotnet = self.source / 'dotnet'
        (self.dotnet / 'sdk/8.0.426').mkdir(parents=True)
        (self.dotnet / 'sdk/8.0.426/dotnet.dll').write_bytes(b'sdk fixture')
        (self.dotnet / 'dotnet').write_text(DOTNET)
        (self.dotnet / 'dotnet').chmod(0o755)
        addons = self.root / 'addons'
        (addons / 'godot_mujoco').mkdir(parents=True)
        (addons / 'godot_mujoco/godot_mujoco.gdextension').write_text('[configuration]\n')
        (addons / 'mujoco_editor').mkdir()
        (addons / 'mujoco_editor/plugin.cfg').write_text('[plugin]\n')
        for name in tools.EXAMPLES:
            path = self.root / 'examples' / name
            path.mkdir(parents=True)
            (path / 'project.godot').write_text('config_version=5\n')
        self.pins = dict(tools.PINS, godot_binary_sha256=hashlib.sha256(GODOT.encode()).hexdigest())
        (self.root / 'scripts/ci/toolchain.json').write_text(json.dumps(self.pins))
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        for module in (tools, bootstrap, launcher):
            for name, value in (('ROOT', self.root), ('THIRD_PARTY', self.third), ('ADDONS', addons), ('PINS', self.pins)):
                if hasattr(module, name):
                    stack.enter_context(patch.object(module, name, value))
        stack.enter_context(patch.object(tools, 'STATE', self.third / 'environment.json'))
        stack.enter_context(patch.object(Path, 'home', return_value=self.home))
        stack.enter_context(patch.object(bootstrap, 'ensure_system_dependencies', return_value=False))
        stack.enter_context(patch.object(bootstrap, 'ensure_cmake', return_value=None))
        stack.enter_context(patch.object(bootstrap, 'external_candidates', return_value={'godot': [], 'dotnet': []}))
        stack.enter_context(patch.dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                                       TEST_REPO_ROOT=str(self.root), DISPLAY=':fixture'))
        for key in ('CC', 'CXX', 'CMAKE_GENERATOR', 'MUJOCO_SDK_DIR'):
            stack.enter_context(patch.dict(os.environ, {key: ''}))

    def run_setup(self, *extra):
        return bootstrap.main(['--yes', '--godot-dir', str(self.godot), '--dotnet-dir', str(self.dotnet), *extra])

    def test_local_import_build_and_terminal_wrappers_are_repeatable(self):
        self.assertEqual(self.run_setup(), 0)
        config = tools.load_config(require_build=True)
        self.assertTrue(config['built'])
        self.assertTrue(self.godot.exists())
        for name, expected in (('godot', self.pins['godot_version']), ('dotnet', '8.0.426')):
            wrapper = self.home / '.local/bin' / name
            self.assertEqual(subprocess.check_output([wrapper, '--version'], text=True).strip(), expected)
        self.assertEqual(self.run_setup(), 0)
        profile = (self.home / '.bashrc').read_text()
        self.assertIn('# keep my shell settings', profile)
        self.assertEqual(profile.count('# >>> godot-mujoco >>>'), 1)
        for name in tools.EXAMPLES:
            self.assertTrue((self.root / 'examples' / name / 'addons').is_symlink())

    def test_build_failure_preserves_original_tools_and_terminal(self):
        with patch.dict(os.environ, TEST_BUILD_EXIT='41'):
            self.assertEqual(self.run_setup(), 41)
        self.assertTrue(self.godot.exists())
        self.assertFalse((self.home / '.local/bin/godot').exists())
        with self.assertRaises(tools.ToolError):
            tools.load_config(require_build=True)

    def test_ready_environment_rebuilds_without_install_menus_or_downloads(self):
        self.assertEqual(self.run_setup(), 0)
        with patch('builtins.input', side_effect=AssertionError('No installation menus expected')), patch.object(bootstrap, 'download_godot') as godot_download, patch.object(bootstrap, 'download') as download:
            self.assertEqual(bootstrap.main([]), 0)
            self.assertEqual(bootstrap.main(['--rebuild']), 0)
            godot_download.assert_not_called()
            download.assert_not_called()

    def test_check_only_detects_external_tools_without_creating_state(self):
        candidates = {'godot': [self.godot], 'dotnet': [self.dotnet]}
        with patch.object(bootstrap, 'external_candidates', return_value=candidates), patch('builtins.input', side_effect=AssertionError('Check must not prompt')), patch.object(bootstrap, 'install_tool') as install:
            self.assertEqual(bootstrap.main(['--check']), 0)
            install.assert_not_called()
        self.assertFalse(self.third.exists())
        self.assertEqual((self.home / '.bashrc').read_text(), '# keep my shell settings\n')

    def test_detected_external_tools_are_imported_instead_of_downloaded(self):
        candidates = {'godot': [self.godot], 'dotnet': [self.dotnet]}
        with patch.object(bootstrap, 'external_candidates', return_value=candidates), patch.object(bootstrap, 'download_godot') as godot_download, patch.object(bootstrap, 'download') as download:
            self.assertEqual(bootstrap.main(['--yes']), 0)
            godot_download.assert_not_called()
            download.assert_not_called()
        self.assertTrue(tools.load_config(require_build=True)['built'])

    def test_rebuild_without_local_tools_fails_before_install(self):
        with patch.object(bootstrap, 'install_tool') as install:
            self.assertEqual(bootstrap.main(['--rebuild']), 2)
            install.assert_not_called()
        self.assertFalse(self.third.exists())

    def test_download_choice_gives_feedback_and_requests_replacement(self):
        stream = io.StringIO()
        with patch('builtins.input', return_value='1'), contextlib.redirect_stdout(stream):
            source, reinstall = bootstrap.choose_source('godot', None, False, {'local': self.godot, 'external': None})
        self.assertIsNone(source)
        self.assertTrue(reinstall)
        self.assertIn('完成两项工具选择后开始执行', stream.getvalue())

    def test_explicit_reinstall_replaces_valid_tool_and_keeps_original_on_failure(self):
        target = bootstrap.install_tool('godot', self.godot)
        marker = target / 'previous-install'
        marker.write_text('keep until verified')
        with patch.object(bootstrap, 'download_godot', side_effect=OSError('download failed')):
            with self.assertRaises(OSError):
                bootstrap.install_tool('godot', None, reinstall=True)
        self.assertTrue(marker.exists())
        def replacement(destination, archive_dir=None):
            extracted = destination / 'official'
            shutil.copytree(self.godot, extracted)
            (extracted / 'new-install').write_text('downloaded')
            return extracted / Path(self.pins['godot_binary']).name
        with patch.object(bootstrap, 'download_godot', side_effect=replacement) as download:
            bootstrap.install_tool('godot', None, reinstall=True)
            download.assert_called_once()
        self.assertFalse(marker.exists())
        self.assertTrue((target / 'new-install').is_file())

    def test_old_example_link_is_migrated_and_custom_addons_are_preserved(self):
        target = self.root / 'examples/shape_gallery/addons'
        target.symlink_to('../../demo/addons', target_is_directory=True)
        bootstrap.stage_examples()
        self.assertEqual(target.resolve(), self.root / 'addons')
        target.unlink()
        target.mkdir()
        marker = target / 'custom-addon'
        marker.write_text('user data')
        with self.assertRaises(tools.ToolError):
            bootstrap.stage_examples()
        self.assertEqual(marker.read_text(), 'user data')

    def test_version_and_godotsharp_fail_before_import(self):
        shutil.rmtree(self.godot / 'GodotSharp/Tools')
        self.assertEqual(self.run_setup(), 2)
        self.assertFalse((self.third / 'godot').exists())

    def test_bad_checksum_and_invalid_existing_target_are_preserved(self):
        (self.godot / Path(self.pins['godot_binary']).name).write_text('#!/bin/sh\necho wrong\n')
        self.assertEqual(self.run_setup(), 2)
        target = self.third / 'godot'
        target.mkdir(parents=True)
        marker = target / 'keep'
        marker.write_text('untouched')
        self.assertEqual(self.run_setup(), 2)
        self.assertEqual(marker.read_text(), 'untouched')

    def test_wrong_dotnet_sdk_is_rejected(self):
        (self.dotnet / 'dotnet').write_text('#!/bin/sh\necho 9.0.100\n')
        self.assertEqual(self.run_setup(), 2)
        self.assertFalse((self.third / 'dotnet').exists())

    def test_import_repairs_executable_bit_only_in_repository_copy(self):
        binary = self.godot / Path(self.pins['godot_binary']).name
        binary.chmod(0o644)
        self.assertEqual(self.run_setup(), 0)
        self.assertFalse(os.access(binary, os.X_OK))
        self.assertTrue(os.access(self.third / 'godot' / binary.name, os.X_OK))

    def test_new_project_is_independent_and_preserves_existing_directory(self):
        self.assertEqual(self.run_setup(), 0)
        project = launcher.create_project('my project')
        self.assertIn('config/name="my project"', (project / 'project.godot').read_text())
        self.assertIn('position = Vector3(0, 1.5, 0)', (project / 'Main.tscn').read_text())
        self.assertTrue((project / 'addons/godot_mujoco/bin' / tools.NATIVE).is_file())
        self.assertFalse((project / 'addons/godot_mujoco').is_symlink())
        with self.assertRaises(tools.ToolError):
            launcher.create_project('my project')
        shutil.rmtree(self.root / 'addons')
        self.assertTrue((project / 'addons/godot_mujoco/bin' / tools.NATIVE).is_file())

    def test_project_name_cannot_escape_workspace(self):
        for name in ('', '.', '..', '../escape', '/absolute', 'a/b', 'a\\b', 'line\nname'):
            with self.subTest(name=name), self.assertRaises(tools.ToolError):
                launcher.create_project(name)

    def test_launcher_modes_select_project_manager_and_example_editor(self):
        self.assertEqual(self.run_setup(), 0)
        for args, expected in (([], '--project-manager'), (['--exp', 'shape_gallery'], '--editor')):
            with self.subTest(args=args), patch.object(launcher.os, 'execve') as execute, patch.object(launcher.os, 'chdir'):
                self.assertEqual(launcher.main(args), 0)
                command = execute.call_args.args[1]
                self.assertIn(expected, command)
                self.assertTrue(command[0].startswith(str(self.third)))
        with patch('builtins.input', return_value='2'):
            self.assertEqual(launcher.choose_example(), 'g1_passive')

    def test_missing_setup_launch_never_downloads_and_headless_creation_is_retained(self):
        with patch.object(bootstrap, 'download') as download:
            self.assertEqual(launcher.main([]), 2)
            download.assert_not_called()
        self.assertEqual(self.run_setup(), 0)
        with patch.dict(os.environ, DISPLAY='', WAYLAND_DISPLAY=''):
            self.assertEqual(launcher.main(['--new', 'headless-project']), 2)
        self.assertTrue((self.root / 'projects/headless-project/project.godot').exists())

    def test_moved_repository_configuration_remains_relative(self):
        self.assertEqual(self.run_setup(), 0)
        config = json.loads((self.third / 'environment.json').read_text())
        for key in ('godot_bin', 'dotnet_root'):
            self.assertFalse(Path(config[key]).is_absolute())
        with self.assertRaises(tools.ToolError):
            tools.local_path('../outside')

    def test_cached_download_is_verified_and_partial_failure_does_not_publish(self):
        source = self.base / 'download-source'
        source.write_bytes(b'official archive fixture')
        expected = hashlib.sha512(source.read_bytes()).hexdigest()
        cache = self.third / 'cache/sdk.tar.gz'
        bootstrap.download(source.as_uri(), cache, expected, 'sha512')
        source.unlink()
        self.assertEqual(bootstrap.download(source.as_uri(), cache, expected, 'sha512'), cache)
        cache.write_bytes(b'corrupt')
        with self.assertRaises(tools.ToolError):
            bootstrap.download(source.as_uri(), cache, expected, 'sha512')
        self.assertEqual(cache.read_bytes(), b'corrupt')

    def test_dotnet_archive_install_and_cmake_fallback(self):
        cache = self.third / 'cache'
        cache.mkdir(parents=True)
        archive = cache / 'dotnet-sdk.tar.gz'
        with tarfile.open(archive, 'w:gz') as package:
            package.add(self.dotnet, arcname='.')
        self.pins['dotnet_archive_sha512'] = tools.digest(archive, 'sha512')
        self.assertEqual(bootstrap.install_tool('dotnet', None), self.third / 'dotnet')
        archive = cache / 'cmake.tar.gz'
        with tarfile.open(archive, 'w:gz') as package:
            package.add(self.bin, arcname='cmake-3.31.10-linux-x86_64/bin')
        self.pins['cmake_archive_sha256'] = tools.digest(archive)
        with patch.object(bootstrap.shutil, 'which', return_value=None):
            result = ENSURE_CMAKE(True)
        self.assertEqual(result, 'third_party/cmake/cmake-3.31.10-linux-x86_64/bin')
        self.assertTrue((self.root / result / 'cmake').is_file())

    def test_tar_rejects_traversal_and_external_symlink(self):
        for kind in ('path', 'link', 'device'):
            with self.subTest(kind=kind):
                archive = self.base / f'{kind}.tar.gz'
                with tarfile.open(archive, 'w:gz') as package:
                    entry = tarfile.TarInfo('../outside' if kind == 'path' else 'inside')
                    if kind == 'link':
                        entry.type, entry.linkname = tarfile.SYMTYPE, '../../outside'
                    if kind == 'device':
                        entry.type = tarfile.CHRTYPE
                    package.addfile(entry)
                with self.assertRaises(tools.ToolError):
                    bootstrap.extract_tar(archive, self.base / 'unpacked')
        self.assertFalse((self.base / 'outside').exists())

    def test_godot_downloader_contract_and_zip_traversal(self):
        for malicious in (False, True):
            with self.subTest(malicious=malicious):
                destination = self.base / ('unsafe godot' if malicious else 'safe godot')
                destination.mkdir()
                archive = destination / 'godot-mono.zip'
                with zipfile.ZipFile(archive, 'w') as package:
                    package.writestr(self.pins['godot_binary'], GODOT)
                    if malicious:
                        package.writestr('../escape', b'bad')
                config = dict(self.pins)
                for algorithm in ('sha256', 'sha512'):
                    config['godot_archive_' + algorithm] = hashlib.new(algorithm, archive.read_bytes()).hexdigest()
                (self.root / 'scripts/ci/toolchain.json').write_text(json.dumps(config))
                result = subprocess.run([sys.executable, self.root / 'scripts/ci/install_godot.py', destination], text=True, capture_output=True)
                self.assertEqual(result.returncode == 0, not malicious, result.stderr)
                if not malicious:
                    self.assertEqual(result.stdout.strip(), str(destination / self.pins['godot_binary']))
        self.assertFalse((self.base / 'escape').exists())


if __name__ == '__main__':
    unittest.main()
