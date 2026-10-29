"""Guard against false performance conclusions (no GPU needed)."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("viewer_run", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class ReportingTests(unittest.TestCase):
    def test_percentile_is_frame_time_not_average_fps(self):
        self.assertAlmostEqual(runner.percentile([1] * 94 + [40] * 6, .95), 40)

    def test_present_cap_is_inconclusive_and_zero_gpu_is_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "frames.csv"
            path.write_text("frame_ms,gpu_ms\n" + "16.666666,0\n" * 100)
            result = runner.summarize(path)
            self.assertTrue(result["possible_present_cap"])
            self.assertNotIn("gpu_ms", result)

    def test_incomplete_suite_cannot_pass_acceptance(self):
        runs = []
        for backend, elapsed in (("godot", 1.05), ("native", 1.0)):
            runs.append({"workload":"gallery", "profile":"common", "mode":"physics", "backend":backend,
                         "repeat":1, "steps":10000, "elapsed_s":elapsed})
        with tempfile.TemporaryDirectory() as directory:
            result = runner.report(Path(directory), runs, {}, False)
            self.assertIsNone(result["accepted"])
            self.assertFalse(result["complete"])
            self.assertTrue(result["comparisons"][0]["passed"])
            self.assertIsNone(json.loads((Path(directory) / "results.json").read_text())["accepted"])

    def test_corrupted_timestamps_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "frames.csv"
            for value in ("nan", "-1", "0"):
                path.write_text("frame_ms,gpu_ms\n" + f"{value},1\n" * 20)
                with self.assertRaises(ValueError):
                    runner.summarize(path)

    def test_camera_gate_rejects_projection_mismatch(self):
        fixture = {"camera":{"position":[0,0,0], "forward":[0,0,-1], "up":[0,1,0], "near":1, "top":1},
                   "projected_geom_centers":[{"world":[0,0,-4], "pixel":[960,540]},
                                             {"world":[1,0,-4], "pixel":[1095,540]},
                                             {"world":[0,1,-4], "pixel":[960,405]}]}
        self.assertEqual(runner.validate_camera(fixture)["max_projection_error_px"], 0)
        fixture["projected_geom_centers"][0]["pixel"][0] += 3
        with self.assertRaises(ValueError):
            runner.validate_camera(fixture)

    def test_missing_g1_is_rejected_even_with_visible_floor(self):
        with self.assertRaises(ValueError):
            runner.validate_workload({"workload":"g1-single", "nq":0, "nv":0, "visible_geoms":[0,1,2]})
        runner.validate_workload({"workload":"g1-dual", "nq":72, "nv":70})

    def test_state_gate_checks_velocity_and_full_state_length(self):
        fixture = {"nq":1, "nv":1, "na":0, "state_size":4}
        with tempfile.TemporaryDirectory() as directory:
            godot, native = Path(directory) / "g.f64", Path(directory) / "n.f64"
            godot.write_bytes(struct.pack("<4d", 1, 2, 3, 4))
            native.write_bytes(struct.pack("<4d", 1, 2, 3, 4))
            self.assertEqual(runner.compare_states(godot, native, fixture)["max_qvel_error"], 0)
            native.write_bytes(struct.pack("<4d", 1, 2, 3.1, 4))
            with self.assertRaises(ValueError):
                runner.compare_states(godot, native, fixture)
            native.write_bytes(struct.pack("<3d", 1, 2, 3))
            with self.assertRaises(ValueError):
                runner.compare_states(godot, native, fixture)

    def test_sparse_ray_stalls_are_not_reported_as_absent(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "frames.csv"
            path.write_text("frame_ms,ray_ms,ray_count\n" + "1,0,0\n" * 96 + "240,200,8\n" * 4)
            self.assertEqual(runner.summarize(path)["ray_ms"]["p95"], 0)
            observed = runner.observe_picking(path)
            self.assertEqual(observed["queries"], 32)
            self.assertEqual(observed["query_frame_fraction"], .04)
            self.assertEqual(observed["max_ray_ms"], 200)
            self.assertGreater(observed["ray_wall_fraction"], .75)

    def test_legacy_key_normalization_requires_identical_asset_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            project = repo / "examples/g1_passive"
            asset = project / "models/robot/assets/mesh.stl"
            asset.parent.mkdir(parents=True)
            asset.write_bytes(b"pinned mesh bytes")
            path = project / "G1.tscn"
            original = '"file": "res://models/robot/assets/mesh.stl"\ndependencies = {\n"assets/mesh.stl": "' + runner.digest(asset) + '"\n}\n'
            path.write_text(original)
            changes = runner.normalize_fixture_dependencies(repo)
            self.assertEqual(changes[0]["project_key"], "res://models/robot/assets/mesh.stl")
            path.write_text(original)
            asset.write_bytes(b"modified mesh bytes")
            with self.assertRaises(ValueError):
                runner.normalize_fixture_dependencies(repo)

    def test_one_slow_scene_cannot_be_hidden_by_other_scenes(self):
        runs = []
        for workload in ("gallery", "g1-single", "g1-dual"):
            for profile, mode in (("common", "physics"), ("common", "static"), ("common", "running"), ("default", "running")):
                for backend in ("godot", "native"):
                    for repeat in (1, 2, 3):
                        row = {"workload":workload, "profile":profile, "mode":mode, "backend":backend, "repeat":repeat,
                               "execution":{"peak_rss_kb":1024}, "steps":10000, "elapsed_s":1.0, "sim_time":1.0, "sample_s":1.0}
                        frame = 10 if backend == "native" else 11
                        if (workload, profile, mode, backend) == ("g1-dual", "common", "static", "godot"):
                            frame = 13
                        row["summary"] = {"frame_ms":{"p95":frame}, "possible_present_cap":False}
                        runs.append(row)
        with tempfile.TemporaryDirectory() as directory:
            result = runner.report(Path(directory), runs, {}, False)
            self.assertTrue(result["complete"])
            self.assertFalse(result["accepted"])
            self.assertEqual(sum(row["passed"] is False for row in result["comparisons"]), 1)


if __name__ == "__main__":
    unittest.main()
