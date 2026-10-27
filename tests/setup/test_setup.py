"""CLI contracts with isolated tool stubs; no downloads or native builds."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
BASH = shutil.which('bash')
STUB = f'#!{sys.executable}\n' + '''import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with open(os.environ['SETUP_TEST_LOG'], 'a') as stream:
    stream.write(json.dumps([name] + sys.argv[1:]) + '\\n')
if name == 'cmake':
    if '--version' in sys.argv:
        print('cmake version ' + os.environ.get('TEST_CMAKE_VERSION', '3.31.6'))
    else:
        sys.exit(int(os.environ.get('TEST_BUILD_EXIT' if '--build' in sys.argv else 'TEST_CONFIGURE_EXIT', '0')))
elif name.startswith('godot'):
    print(os.environ.get('TEST_GODOT_VERSION', '4.7.2.stable.mono.official.ed1daf0bf'))
elif name == 'dotnet':
    print(os.environ.get('TEST_DOTNET_VERSION', '8.0.426'))
elif name in ('cc', 'c++'):
    sys.exit(int(os.environ.get('TEST_COMPILER_EXIT', '0')))
'''


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='gmj setup test ')
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / 'source with spaces'
        for name in ('scripts/setup.py', 'scripts/setup.sh', 'scripts/cloud_setup.sh', 'scripts/ci/toolchain.json'):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        self.bin = self.base / 'tools with spaces'
        self.bin.mkdir()
        for name in ('git', 'cmake', 'make', 'cc', 'c++', 'godot', 'dotnet'):
            self.tool(name)
        for name, executable in (('python3', sys.executable), ('dirname', shutil.which('dirname')), ('bash', BASH)):
            (self.bin / name).symlink_to(executable)
        self.config = json.loads((self.root / 'scripts/ci/toolchain.json').read_text())
        self.config['godot_binary_sha256'] = hashlib.sha256(STUB.encode()).hexdigest()
        self.config['mujoco_binary_sha256'] = hashlib.sha256(b'official SDK fixture').hexdigest()
        self.write_config()
        self.env = {key: value for key, value in os.environ.items() if key not in
                    ('CC', 'CXX', 'GODOT_BIN', 'MUJOCO_SDK_DIR', 'OUT', 'CMAKE_GENERATOR')}
        self.env.update(PATH=str(self.bin), SETUP_TEST_LOG=str(self.base / 'calls.jsonl'),
                        SETUP_SMOKE_OUT=str(self.base / 'smoke-outs'))
        runner = self.root / 'tests/mjworld_smoke/run.sh'
        runner.parent.mkdir(parents=True)
        runner.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$OUT" >> "$SETUP_SMOKE_OUT"\nexit "${TEST_SMOKE_EXIT:-0}"\n')

    def tool(self, name):
        target = self.bin / name
        target.write_text(STUB)
        target.chmod(0o755)
        return target

    def write_config(self):
        (self.root / 'scripts/ci/toolchain.json').write_text(json.dumps(self.config))

    def invoke(self, *args, legacy=False, **env):
        return subprocess.run([BASH, str(self.root / ('scripts/cloud_setup.sh' if legacy else 'scripts/setup.sh')), *args],
                              env=dict(self.env, **env), cwd=self.base, text=True, capture_output=True, timeout=15)

    def calls(self):
        log = self.base / 'calls.jsonl'
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def cache(self, **values):
        directory = self.base / 'build cache'
        directory.mkdir(exist_ok=True)
        (directory / 'CMakeCache.txt').write_text(''.join(f'{key}:STRING={value}\n' for key, value in values.items()))
        return directory

    def sdk(self):
        directory = self.base / 'local SDK'
        (directory / 'include/mujoco').mkdir(parents=True, exist_ok=True)
        (directory / 'lib').mkdir(exist_ok=True)
        (directory / 'include/mujoco/mujoco.h').write_text('#define mjVERSION_HEADER 3016000\n')
        (directory / 'lib/libmujoco.so.3.16.0').write_bytes(b'official SDK fixture')
        (directory / 'lib/libmujoco.so').symlink_to('libmujoco.so.3.16.0')
        return directory

    def test_check_from_unrelated_directory_does_not_configure_or_create_build(self):
        result = self.invoke('check')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Environment OK', result.stdout)
        self.assertFalse((self.root / 'build-linux').exists())
        self.assertEqual([args for args in self.calls() if args[0] == 'cmake'], [['cmake', '--version']])

    def test_explicit_godot_path_with_spaces_overrides_path(self):
        explicit = self.tool('godot explicit')
        (self.bin / 'godot').write_text('broken PATH entry')
        result = self.invoke('check', GODOT_BIN=str(explicit))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(explicit), result.stdout)

    def test_missing_tools_have_actionable_errors(self):
        for name, message in (('git', 'Install git'), ('cmake', 'Install CMake'), ('cc', 'toolchain'),
                              ('make', 'Install make or ninja'), ('godot', 'GODOT_BIN'), ('dotnet', 'Install .NET SDK')):
            with self.subTest(tool=name):
                original = (self.bin / name).read_bytes()
                (self.bin / name).unlink()
                result = self.invoke('check')
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn(message, result.stderr)
                (self.bin / name).write_bytes(original)
                (self.bin / name).chmod(0o755)

    def test_wrong_versions_and_compiler_failure(self):
        for variable, value, message in (
            ('TEST_CMAKE_VERSION', '3.23.0', 'CMake >=3.24'),
            ('TEST_GODOT_VERSION', '4.7.2.stable.official.ed1daf0bf', 'Expected Godot'),
            ('TEST_DOTNET_VERSION', '9.0.100', 'Select .NET SDK'),
            ('TEST_COMPILER_EXIT', '1', 'compiler check failed'),
        ):
            with self.subTest(variable=variable):
                result = self.invoke('check', **{variable: value})
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn(message, result.stderr)

    def test_godot_launcher_is_rejected_by_hash(self):
        with (self.bin / 'godot').open('a') as stream:
            stream.write('# modified executable\n')
        result = self.invoke('check')
        self.assertEqual(result.returncode, 2)
        self.assertIn('checksum mismatch', result.stderr)

    def test_build_passes_quoted_paths_jobs_and_download_mode(self):
        build = self.base / 'fresh build'
        result = self.invoke('build', '--build-dir', str(build), '--jobs', '3')
        self.assertEqual(result.returncode, 0, result.stderr)
        configure = next(args for args in self.calls() if '-S' in args)
        self.assertEqual(configure[configure.index('-S') + 1], str(self.root))
        self.assertEqual(configure[configure.index('-B') + 1], str(build))
        self.assertIn('-DGMJ_MUJOCO_ROOT:PATH=', configure)
        self.assertIn(['cmake', '--build', str(build), '--parallel', '3'], self.calls())

    def test_local_sdk_from_argument_or_environment(self):
        sdk = self.sdk()
        for arguments, env in ((['--mujoco-root', str(sdk)], {}), ([], {'MUJOCO_SDK_DIR': str(sdk)})):
            with self.subTest(arguments=arguments):
                result = self.invoke('build', *arguments, **env)
                self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(f'-DGMJ_MUJOCO_ROOT:PATH={sdk}' in args for args in self.calls() if '-S' in args))
        result = self.invoke('check', '--mujoco-root', str(sdk), MUJOCO_SDK_DIR='/invalid/env/sdk')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_invalid_sdk_header_and_runtime_are_rejected(self):
        result = self.invoke('check', '--mujoco-root', str(self.base / 'missing SDK'))
        self.assertEqual(result.returncode, 2)
        self.assertIn('Invalid MuJoCo SDK', result.stderr)
        sdk = self.sdk()
        header = sdk / 'include/mujoco/mujoco.h'
        header.write_text('#define mjVERSION_HEADER 3015000\n')
        result = self.invoke('check', '--mujoco-root', str(sdk))
        self.assertEqual(result.returncode, 2)
        self.assertIn('headers must be version', result.stderr)
        header.write_text('#define mjVERSION_HEADER 3016000\n')
        (sdk / 'lib/libmujoco.so.3.16.0').write_bytes(b'wrong version')
        result = self.invoke('check', '--mujoco-root', str(sdk))
        self.assertEqual(result.returncode, 2)
        self.assertIn('runtime checksum mismatch', result.stderr)

    def test_cache_conflicts_preserve_original_cache(self):
        for values in ({'MUJOCO_VERSION': '3.12.0'}, {'CMAKE_HOME_DIRECTORY': '/another/checkout'},
                       {'GMJ_MUJOCO_ROOT': '/previous/sdk'}, {'GMJ_BUILD_MUJOCO_FROM_SOURCE': 'ON'},
                       {'GODOT_CPP_TAG': 'other'}, {'GMJ_ADDON_BIN': '/another/addon'},
                       {'GODOTCPP_TARGET': 'template_release'}, {'GODOTCPP_PRECISION': 'double'}):
            with self.subTest(values=values):
                build = self.cache(**values)
                original = (build / 'CMakeCache.txt').read_bytes()
                result = self.invoke('build', '--build-dir', str(build))
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn('--build-dir', result.stderr)
                self.assertEqual((build / 'CMakeCache.txt').read_bytes(), original)
                self.assertFalse(any('-S' in args for args in self.calls()))

    def test_generator_and_compiler_selection(self):
        (self.bin / 'make').unlink()
        self.tool('ninja')
        result = self.invoke('build', CC=str(self.bin / 'cc'), CXX=str(self.bin / 'c++'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Ninja', next(args for args in self.calls() if '-S' in args))
        build = self.cache(CMAKE_CXX_COMPILER='/previous/compiler')
        result = self.invoke('build', '--build-dir', str(build), CXX=str(self.bin / 'c++'))
        self.assertEqual(result.returncode, 2)
        self.assertIn('CXX differs', result.stderr)

    def test_previous_addon_cache_is_migrated_without_replacing_other_settings(self):
        build = self.cache(GMJ_ADDON_BIN=str(self.root / 'demo/addons/godot_mujoco/bin'))
        original = (build / 'CMakeCache.txt').read_bytes()
        self.assertEqual(self.invoke('check', '--build-dir', str(build)).returncode, 0)
        self.assertEqual((build / 'CMakeCache.txt').read_bytes(), original)
        result = self.invoke('build', '--build-dir', str(build))
        self.assertEqual(result.returncode, 0, result.stderr)
        configured = next(args for args in self.calls() if '-S' in args)
        self.assertIn(f'-DGMJ_ADDON_BIN:PATH={self.root / "addons/godot_mujoco/bin"}', configured)

    def test_matching_sdk_cache_is_reusable_and_mode_changes_are_rejected(self):
        sdk = self.sdk()
        build = self.cache(CMAKE_HOME_DIRECTORY=str(self.root), MUJOCO_VERSION='3.16.0',
                           GMJ_MUJOCO_ROOT=str(sdk), MUJOCO_LINK_LIB=str(sdk / 'lib/libmujoco.so'))
        result = self.invoke('build', '--build-dir', str(build), '--mujoco-root', str(sdk))
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.invoke('build', '--build-dir', str(build))
        self.assertEqual(result.returncode, 2)
        self.assertIn('different MuJoCo SDK/download mode', result.stderr)

    def test_configuration_failure_stops_before_build(self):
        result = self.invoke('build', TEST_CONFIGURE_EXIT='37')
        self.assertEqual(result.returncode, 37)
        self.assertFalse(any('--build' in args for args in self.calls()))

    def test_build_and_smoke_failures_keep_real_exit_status(self):
        self.assertEqual(self.invoke('build', TEST_BUILD_EXIT='41').returncode, 41)
        out = self.base / 'smoke results'
        self.assertEqual(self.invoke('smoke', '--out', str(out), TEST_SMOKE_EXIT='3').returncode, 3)
        self.assertEqual((self.base / 'smoke-outs').read_text().strip(), str(out))

    def test_smoke_signal_uses_shell_exit_status(self):
        runner = self.root / 'tests/mjworld_smoke/run.sh'
        runner.write_text('kill -TERM $$\n')
        result = self.invoke('smoke', '--out', str(self.base / 'signal results'))
        self.assertEqual(result.returncode, 143, result.stderr)

    def test_smoke_preserves_existing_output_and_honors_out_environment(self):
        out = self.base / 'smoke results'
        out.mkdir()
        report = out / 'results.json'
        report.write_text('original failure')
        result = self.invoke('smoke', '--out', str(out))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(report.read_text(), 'original failure')
        self.assertFalse((self.base / 'smoke-outs').exists())
        new = self.base / 'new smoke'
        self.assertEqual(self.invoke('smoke', OUT=str(new)).returncode, 0)
        self.assertEqual((self.base / 'smoke-outs').read_text().strip(), str(new))

    def test_legacy_entry_builds_then_smokes_and_stops_on_build_failure(self):
        result = self.invoke(legacy=True, TEST_CONFIGURE_EXIT='37')
        self.assertEqual(result.returncode, 37)
        self.assertFalse((self.base / 'smoke-outs').exists())
        result = self.invoke(legacy=True, TEST_SMOKE_EXIT='3')
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn('Deprecated', result.stderr)

    def test_invalid_arguments_fail_before_tools(self):
        for arguments in (('build', '--jobs', '0'), ('build', '--jobs', '-1'), ('build', '--jobs', 'two'), ('unknown',)):
            with self.subTest(arguments=arguments):
                self.assertEqual(self.invoke(*arguments).returncode, 2)
                self.assertEqual(self.calls(), [])


class PinConsistencyTests(unittest.TestCase):
    def test_unsupported_platform_is_rejected_before_tool_execution(self):
        spec = importlib.util.spec_from_file_location('portable_setup', ROOT / 'scripts/setup.py')
        setup = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(setup)
        with patch.object(setup.platform, 'system', return_value='Darwin'), patch.object(setup, 'capture') as capture:
            with self.assertRaisesRegex(setup.SetupError, 'Linux x86_64 only'):
                setup.check_environment({})
            capture.assert_not_called()

    def test_manifest_matches_cmake_dependency_pins(self):
        config = json.loads((ROOT / 'scripts/ci/toolchain.json').read_text())
        cmake = (ROOT / 'CMakeLists.txt').read_text()
        for name, key in (('MUJOCO_VERSION', 'mujoco_version'), ('GODOT_CPP_TAG', 'godot_cpp_tag')):
            self.assertIn(f'set({name} "{config[key]}"', cmake)
        self.assertIn(f'cmake_minimum_required(VERSION {config["cmake_minimum_version"]})', cmake)
        self.assertIn(config['mujoco_archive_sha256'], cmake)


if __name__ == '__main__':
    unittest.main()
