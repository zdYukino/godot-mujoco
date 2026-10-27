import pathlib
import tempfile
import unittest
from unittest.mock import patch
import run

class RunnerTests(unittest.TestCase):
    def test_import_classification(self):
        cases = [(0,False,'','passed'),(139,False,'','blocked'),(-11,False,'','blocked'),
                 (0,False,'SCRIPT ERROR: bad','failed'),(0,False,'ObjectDB leaked','failed'),
                 (1,False,'','failed'),(-9,True,'','failed'),(137,False,'','failed')]
        for code,timeout,text,expected in cases:
            with self.subTest(code=code,text=text):
                self.assertEqual(run.classify_import(text,{'exit_code':code,'timed_out':timeout})[0],expected)

    def test_preflight_failure_records_not_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(run.platform,'system',return_value='Unsupported'):
                self.assertEqual(run.run(tmp,'missing'),1)
            import json
            report=json.loads((pathlib.Path(tmp)/'results.json').read_text())
            self.assertEqual(report['stages']['verify']['status'],'failed')
            for stage in ('import','positive','negative','audit_tests'):
                self.assertEqual(report['stages'][stage]['status'],'not_run')

    def test_timeout_records_real_signal(self):
        with tempfile.TemporaryDirectory() as tmp:
            import sys
            r=run.process([sys.executable,'-c','import time; time.sleep(10)'],pathlib.Path(tmp)/'log',.05)
            self.assertTrue(r['timed_out'])
            self.assertEqual(r['exit_code'],-9)

    def test_import_crash_stops_smoke_and_keeps_log(self):
        import json
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp)/'source'
            for directory in ('scripts/ci','examples/pendulum/scripts','examples/pendulum/models','addons/godot_mujoco/bin','tests/mjworld_smoke'):
                (root/directory).mkdir(parents=True,exist_ok=True)
            for name in ('examples/pendulum/HeadlessTest.tscn','examples/pendulum/scripts/headless_smoke_test.gd','tests/mjworld_smoke/invalid_qpos.gd'):
                (root/name).write_text('fixture')
            def fake_digest(path):
                return run.CONFIG['mujoco_binary_sha256'] if path.name=='libmujoco.so.3.16.0' else ('extension' if path.suffix=='.so' else run.CONFIG['godot_binary_sha256'])
            def fake_process(argv,log,timeout):
                log.write_text(run.CONFIG['godot_version']+'\n' if '--version' in argv else 'original crash log\n')
                return {'argv':argv,'exit_code':0 if '--version' in argv else -11,'timed_out':False}
            out=pathlib.Path(tmp)/'out'
            with patch.object(run,'ROOT',root),patch.object(run,'digest',side_effect=fake_digest),patch.object(run,'process',side_effect=fake_process) as proc:
                self.assertEqual(run.run(out,'godot'),3)
                self.assertEqual(proc.call_count,2)
            report=json.loads((out/'results.json').read_text())
            self.assertEqual(report['status'],'blocked')
            self.assertEqual(report['stages']['import']['reason'],'known_initialization_139')
            self.assertEqual(report['stages']['positive']['status'],'not_run')
            self.assertEqual(report['stages']['negative']['status'],'not_run')
            self.assertEqual((out/'import.log').read_text(),'original crash log\n')

    def verify_version_rejection(self, code, timed_out, output):
        import json
        with tempfile.TemporaryDirectory() as tmp:
            def fake_process(argv,log,timeout):
                log.write_text(output)
                return {'argv':argv,'exit_code':code,'timed_out':timed_out}
            with patch.object(run,'digest',return_value=run.CONFIG['godot_binary_sha256']),patch.object(run,'process',side_effect=fake_process) as proc:
                self.assertEqual(run.run(tmp,'godot'),1)
                self.assertEqual(proc.call_count,1)
            report=json.loads((pathlib.Path(tmp)/'results.json').read_text())
            stage=report['stages']['verify']
            self.assertEqual(stage['status'],'failed')
            self.assertEqual(stage['version_process']['exit_code'],code)
            self.assertEqual(stage['version_process']['timed_out'],timed_out)
            self.assertIn('--version',stage['version_process']['argv'])
            self.assertEqual((pathlib.Path(tmp)/'version.log').read_text(),output)
            for name in ('import','positive','negative','audit_tests'):
                self.assertEqual(report['stages'][name]['status'],'not_run')

    def test_version_failure_retains_process(self):
        self.verify_version_rejection(2,False,'version launch failed\n')

    def test_version_timeout_retains_process(self):
        self.verify_version_rejection(-9,True,'partial output\n')

    def test_version_mismatch_retains_process(self):
        self.verify_version_rejection(0,False,'different version\n')
