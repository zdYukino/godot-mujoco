#!/usr/bin/env python3
"""Compare the existing Godot path with native MuJoCo on a real Linux GPU.

Default settings are the agreed acceptance run. --quick is a harness smoke
test and is never labelled an acceptance result. Artifacts stay under --out.
"""
from __future__ import annotations

import argparse
import csv
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import struct
import subprocess
import time
import zlib

ROOT = Path(__file__).resolve().parents[2]
REPORTING_SHA256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def save_json(path: Path, value: object) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        raise ValueError("No samples")
    position = (len(ordered) - 1) * fraction
    low = math.floor(position)
    high = math.ceil(position)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def summarize(path: Path, min_samples: int = 10) -> dict:
    with path.open() as stream:
        rows = list(csv.DictReader(stream))
    if len(rows) < min_samples:
        raise ValueError(f"Too few frame samples: {path}")
    if any(not math.isfinite(float(row["frame_ms"])) or float(row["frame_ms"]) <= 0 for row in rows):
        raise ValueError(f"Invalid frame interval: {path}")
    result = {"frames": len(rows), "low_sample_count":len(rows) < 10}
    for key in rows[0]:
        values = [float(row[key]) for row in rows if math.isfinite(float(row[key])) and float(row[key]) >= 0]
        if key == "gpu_ms":
            values = [value for value in values if value > 0]
        if values:
            result[key] = {"p50": percentile(values, .5), "p95": percentile(values, .95), "mean": statistics.fmean(values)}
    intervals = [float(row["frame_ms"]) for row in rows]
    result["fps"] = 1000 / statistics.fmean(intervals)
    # A stable refresh-rate plateau makes an uncapped renderer comparison
    # inconclusive. Requested swap interval 0 is insufficient evidence alone.
    result["possible_present_cap"] = any(
        abs(statistics.median(intervals) - 1000 / hz) < .18
        and percentile(intervals, .95) - percentile(intervals, .05) < .5
        for hz in (30, 50, 60, 75, 90, 120, 144, 165, 240)
    )
    return result


def compare_states(godot: Path, native: Path, fixture: dict) -> dict:
    arrays = []
    for path in (godot, native):
        data = path.read_bytes()
        size = fixture["state_size"]
        if len(data) != size * 8:
            raise ValueError(f"Integration state length changed: {path}")
        values = struct.unpack(f"<{size}d", data)
        if not all(math.isfinite(v) for v in values):
            raise ValueError(f"Nonfinite integration state: {path}")
        arrays.append(values)
    errors = [abs(a-b) for a, b in zip(*arrays)]
    result = {"time_error":errors[0], "max_integration_error":max(errors)}
    offset = 1
    for name, size in (("qpos", fixture["nq"]), ("qvel", fixture["nv"]), ("act", fixture["na"])):
        result[f"max_{name}_error"] = max(errors[offset:offset+size], default=0)
        offset += size
    if result["time_error"] > 1e-8 or any(result[f"max_{name}_error"] > 1e-6 for name in ("qpos", "qvel", "act")):
        raise ValueError(f"Different physical trajectory: {result}")
    return result


def observe_picking(path: Path) -> dict:
    with path.open() as stream:
        rows = list(csv.DictReader(stream))
    query_frames = sum(float(row["ray_count"]) > 0 for row in rows)
    total_ms = sum(float(row["frame_ms"]) for row in rows)
    return {"frames":len(rows), "query_frames":query_frames,
            "query_frame_fraction":query_frames / len(rows),
            "query_frame_wall_fraction":sum(float(row["frame_ms"]) for row in rows if float(row["ray_count"]) > 0) / total_ms,
            "ray_wall_fraction":sum(float(row["ray_ms"]) for row in rows) / total_ms,
            "queries":round(sum(float(row["ray_count"]) for row in rows)),
            "max_frame_ms":max(float(row["frame_ms"]) for row in rows),
            "max_ray_ms":max(float(row["ray_ms"]) for row in rows)}


def audit_output(out: Path, runs: list[dict], environment: dict, quick: bool) -> dict:
    """Recheck raw evidence, including resumed data, before publishing a verdict."""
    hashes = {}
    def sha(path):
        path = Path(path)
        if path not in hashes:
            hashes[path] = digest(path)
        return hashes[path]
    checks = {"audited_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "verifier_sha256":REPORTING_SHA256, "runs":len(runs), "frames":0, "camera":{}, "physics":{}, "prepared_scripts":{}}
    repo = out / "repo"
    if sha(out / "source-files.json") != environment["source"]["frozen_files_sha256"]:
        raise ValueError("Frozen source manifest changed")
    if sha(out / "source.patch") != environment["source"]["tracked_diff_sha256"]:
        raise ValueError("Recorded workspace patch changed")
    if sha(out / "fixture-adjustments.json") != environment["source"]["fixture_adjustments_sha256"]:
        raise ValueError("Fixture adjustment record changed")
    if sha(out / "build/CMakeCache.txt") != environment["build"]["cmake_cache_sha256"]:
        raise ValueError("Build configuration changed")
    for name in ("shape_gallery", "g1_passive"):
        for alias, source in (("benchmark_runner.gd", "runner.gd"), ("benchmark_stats.gd", "stats.gd")):
            path = repo / "examples" / name / alias
            if not path.exists():
                continue
            if sha(path) != sha(repo / "tests/viewer_performance" / source):
                raise ValueError(f"Prepared script differs from canonical harness: {path}")
            checks["prepared_scripts"][str(path.relative_to(repo))] = sha(path)
    # Import caches and screenshots are mutable; executable frozen sources are not.
    manifest = json.loads((out / "source-files.json").read_text())
    for name, expected in manifest.items():
        if name == "CMakeLists.txt" or Path(name).name == "project.godot" or Path(name).suffix in (".cpp", ".h", ".hpp", ".gd", ".py", ".gdshader", ".tscn", ".tres", ".gdextension"):
            if sha(repo / name) != expected:
                raise ValueError(f"Frozen source changed during measurement: {name}")
    fixtures = {}
    for workload in {r["workload"] for r in runs}:
        directory = out / "fixtures" / workload
        fixture = json.loads((directory / "manifest.json").read_text())
        validate_workload(fixture)
        for file, field in (("model.mjb", "model_sha256"), ("state.f64", "state_sha256")):
            if sha(directory / file) != fixture[field]:
                raise ValueError(f"Fixture changed: {directory / file}")
        fixtures[workload] = fixture
        checks["camera"][workload] = validate_camera(fixture)
    physics = {}
    for run in runs:
        prefix = Path(run["prefix"])
        for suffix in (".json", ".execution.json", ".log", ".final.f64"):
            sha(str(prefix) + suffix)
        inputs = run["execution"]["inputs"]
        directory = out / "fixtures" / run["workload"]
        for name, file in (("model", "model.mjb"), ("state", "state.f64"), ("camera", "camera.txt"), ("visible", "visible.txt")):
            if inputs[name] != sha(directory / file):
                raise ValueError(f"Run used a different fixture: {prefix}: {name}")
        binary = Path(run["execution"]["command"][0]) if run["backend"] == "native" else next((repo / "addons/godot_mujoco/bin").glob("libgodot_mujoco*.so"))
        if run["backend"] == "godot" and sha(run["execution"]["command"][0]) != environment["godot_sha256"]:
            raise ValueError(f"Godot executable changed: {prefix}")
        if inputs["binary"] != sha(binary) or inputs["runner"] != sha(repo / "tests/viewer_performance/runner.gd"):
            raise ValueError(f"Run executable/script provenance changed: {prefix}")
        expected_binary = environment["native_runner_sha256" if run["backend"] == "native" else "extension_sha256"]
        if sha(binary) != expected_binary or inputs["settings"] != environment["settings"]:
            raise ValueError(f"Run configuration changed: {prefix}")
        if sha(run["mujoco_library"]) != environment["mujoco_sha256"] or run.get("warnings", 0):
            raise ValueError(f"Invalid MuJoCo library/warnings: {prefix}")
        if run["backend"] == "godot" and run.get("loaded_model_sha256") != fixtures[run["workload"]]["model_sha256"]:
            raise ValueError(f"Loaded Godot model identity missing/changed: {prefix}")
        if run["mode"] == "physics":
            physics.setdefault((run["workload"], run["repeat"]), {})[run["backend"]] = prefix
            continue
        if (run["width"], run["height"]) != (1920, 1080) or run["actual_sample_s"] < environment["settings"]["sample_s"]:
            raise ValueError(f"Invalid viewport/sample duration: {prefix}")
        summary = summarize(Path(str(prefix) + ".csv"), min_samples=1 if quick or run["profile"] == "default" or run["mode"] == "paused" else 10)
        if summary != run["summary"]:
            raise ValueError(f"Raw CSV no longer matches report: {prefix}")
        sha(str(prefix) + ".csv")
        if run["backend"] == "godot" and run["profile"] == "common" and (run["automatic_picking"] or summary["ray_count"]["mean"] != 0):
            raise ValueError(f"Common profile included automatic picking: {prefix}")
        png = Path(str(prefix) + ".png").read_bytes()
        if png[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", png[16:24]) != (1920, 1080):
            raise ValueError(f"Invalid screenshot dimensions: {prefix}")
        sha(str(prefix) + ".png")
        checks["frames"] += summary["frames"]
    for (workload, repeat), pair in sorted(physics.items()):
        if set(pair) != {"godot", "native"}:
            raise ValueError(f"Unpaired physics test: {workload}/{repeat}")
        checks["physics"][f"{workload}/{repeat}"] = compare_states(Path(str(pair["godot"]) + ".final.f64"), Path(str(pair["native"]) + ".final.f64"), fixtures[workload])
    checks["verified_files"] = {str(path.relative_to(out)) if path.is_relative_to(out) else str(path): value for path, value in sorted(hashes.items())}
    checks["valid"] = True
    save_json(out / "audit.json", checks)
    return checks


def validate_camera(fixture: dict) -> dict:
    """Check Godot's actual projection against the native GL camera contract."""
    camera = fixture["camera"]
    forward, up = camera["forward"], camera["up"]
    right = [forward[1]*up[2]-forward[2]*up[1], forward[2]*up[0]-forward[0]*up[2], forward[0]*up[1]-forward[1]*up[0]]
    length = math.sqrt(sum(v*v for v in right))
    right = [v/length for v in right]
    def dot(a, b):
        return sum(x*y for x, y in zip(a, b))
    errors = []
    for point in fixture["projected_geom_centers"]:
        relative = [p-c for p, c in zip(point["world"], camera["position"])]
        distance = dot(relative, forward)
        if distance <= camera["near"]:
            continue
        x = 960 + dot(relative, right) / distance * camera["near"] / camera["top"] * 540
        y = 540 - dot(relative, up) / distance * camera["near"] / camera["top"] * 540
        if not (0 <= x <= 1920 and 0 <= y <= 1080):
            continue
        errors.append(math.hypot(x-point["pixel"][0], y-point["pixel"][1]))
    if len(errors) < 3 or max(errors) > 2:
        raise ValueError(f"Camera/framing mismatch: {len(errors)} points, errors={errors[:10]}")
    return {"checked_points":len(errors), "max_projection_error_px":max(errors)}


def validate_workload(fixture: dict) -> None:
    workload = fixture["workload"]
    if workload.startswith("g1-"):
        count = 2 if workload == "g1-dual" else 1
        if (fixture["nq"], fixture["nv"]) != (36 * count, 35 * count):
            raise ValueError(f"Expected {count} complete passive G1 model(s), got nq={fixture['nq']}, nv={fixture['nv']}")
    elif fixture["nq"] < 1 or len(fixture["visible_geoms"]) < 8:
        raise ValueError("The dynamic shape gallery did not load completely")


def normalize_fixture_dependencies(repo: Path) -> list[dict]:
    """Correct legacy dependency keys only after verifying the same asset bytes."""
    changes = []
    for project in (repo / "examples/shape_gallery", repo / "examples/g1_passive"):
        for path in project.glob("*.tscn"):
            content = path.read_text()
            references = set(re.findall(r'"(?:file|fileleft|fileright|fileup|filedown|filefront|fileback)":\s*"(res://[^"\n]+)"', content))
            def replace(match):
                dependencies = json.loads(match.group(1))
                normalized = {}
                for key, expected in dependencies.items():
                    if key.startswith("res://"):
                        normalized[key] = expected
                        continue
                    candidates = [name for name in references if name.endswith("/" + key)]
                    if len(candidates) != 1:
                        raise ValueError(f"Ambiguous legacy dependency: {path}: {key}")
                    target = candidates[0]
                    if digest(project / target.removeprefix("res://")) != expected:
                        raise ValueError(f"Legacy dependency asset bytes differ: {path}: {key}")
                    normalized[target] = expected
                    changes.append({"scene":str(path.relative_to(repo)), "old_key":key, "project_key":target, "sha256":expected})
                return "dependencies = " + json.dumps(normalized, indent=2, ensure_ascii=False)
            normalized = re.sub(r"dependencies = (\{\n[^}]*\})", replace, content)
            if normalized != content:
                path.write_text(normalized)
    return changes


def convert_screenshot(prefix: Path) -> None:
    ppm = Path(str(prefix) + ".ppm")
    if not ppm.exists():
        return
    magic, dimensions, maximum, rgb = ppm.read_bytes().split(b"\n", 3)
    width, height = map(int, dimensions.split())
    if magic != b"P6" or maximum != b"255" or len(rgb) != width*height*3:
        raise ValueError(f"Invalid native screenshot: {ppm}")
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind+payload))
    filtered = b"".join(b"\0" + rgb[y*width*3:(y+1)*width*3] for y in range(height))
    image = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    image += chunk(b"IDAT", zlib.compress(filtered)) + chunk(b"IEND", b"")
    Path(str(prefix) + ".png").write_bytes(image)


def thermal_snapshot() -> dict:
    result = {}
    for pattern in ("/sys/class/thermal/thermal_zone*/temp", "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor", "/sys/class/power_supply/AC*/online", "/proc/loadavg"):
        import glob
        for name in glob.glob(pattern):
            try:
                result[name] = Path(name).read_text().strip()
            except OSError:
                pass
    return result


def execute(command: list[str], log: Path, env: dict, timeout: float = 240, gpu: bool = False) -> dict:
    started = time.monotonic()
    peak_rss_kb = 0
    environment = thermal_snapshot()
    with log.open("w") as stream:
        process = subprocess.Popen(command, env=env, stdout=stream, stderr=subprocess.STDOUT)
        log_size = 0
        try:
            while process.poll() is None:
                try:
                    for line in Path(f"/proc/{process.pid}/status").read_text().splitlines():
                        if line.startswith(("VmRSS:", "VmHWM:")):
                            peak_rss_kb = max(peak_rss_kb, int(line.split()[1]))
                except OSError:
                    pass
                size = log.stat().st_size
                if size != log_size:
                    log_size = size
                    tail = log.read_text(errors="replace")[-12000:]
                    if any(token in tail for token in ("SCRIPT ERROR:", "BENCHMARK ERROR:")):
                        raise RuntimeError(f"Harness failed; see {log}\n{tail}")
                if time.monotonic() - started > timeout:
                    raise TimeoutError(f"Timed out: {command}; see {log}")
                time.sleep(.2)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    content = log.read_text(errors="replace")
    if process.returncode or any(token in content for token in ("SCRIPT ERROR:", "BENCHMARK ERROR:", "ERROR:")):
        raise RuntimeError(f"Command failed ({process.returncode}); see {log}\n{content[-6000:]}")
    if gpu and any(token in content.lower() for token in ("llvmpipe", "softpipe", "software rasterizer")):
        raise RuntimeError(f"Software rendering: {log}")
    return {"command": command, "elapsed_s": time.monotonic() - started, "peak_rss_kb": peak_rss_kb,
            "environment_before": environment, "environment_after": thermal_snapshot()}


def freeze(out: Path, snapshot: Path | None = None) -> tuple[Path, dict]:
    source_root = snapshot / "repo" if snapshot else ROOT
    repo = out / "repo"
    repo.mkdir()
    for name in ("addons", "assets", "src", "cmake", "tests/viewer_performance", "examples/_shared", "examples/shape_gallery", "examples/g1_passive"):
        origin = ROOT if name == "tests/viewer_performance" else source_root
        shutil.copytree(origin / name, repo / name, symlinks=True,
                        ignore=shutil.ignore_patterns(".godot", "__pycache__", "*.pyc", "*.so*", "benchmark_runner.gd", "benchmark_stats.gd"))
    shutil.copyfile(source_root / "CMakeLists.txt", repo / "CMakeLists.txt")
    adjustments = json.loads((snapshot / "fixture-adjustments.json").read_text()) if snapshot and (snapshot / "fixture-adjustments.json").exists() else []
    adjustments += normalize_fixture_dependencies(repo)
    save_json(out / "fixture-adjustments.json", adjustments)
    # Only the frozen test copy gains script timers/common-profile override.
    author = repo / "addons/godot_mujoco/model/author_scene.gd"
    content = author.read_text()
    if "const BenchmarkStats = " not in content:
        content = content.replace('extends RefCounted\n', 'extends RefCounted\nconst BenchmarkStats = preload("res://benchmark_stats.gd")\n', 1)
        start = content.index("func update_runtime(state: Dictionary) -> void:\n")
        end = content.index("\nfunc ", start + 5)
        block = content[start:end]
        block = block.replace("-> void:\n", "-> void:\n\tvar benchmark_start := Time.get_ticks_usec()\n", 1)
        block += "\n\tBenchmarkStats.sync_us += Time.get_ticks_usec() - benchmark_start\n"
        author.write_text(content[:start] + block + content[end:])
    gallery = repo / "examples/_shared/gallery.gd"
    content = gallery.read_text()
    signature = "func apply_floor_grid() -> void:\n"
    assert content.count(signature) == 1
    if 'get_meta("benchmark_common", false)' not in content:
        gallery.write_text(content.replace(signature, signature + '\tif get_meta("benchmark_common", false): return\n'))
    manifest = {}
    for path in sorted(repo.rglob("*")):
        if path.is_file() and not path.is_symlink():
            manifest[str(path.relative_to(repo))] = digest(path)
    save_json(out / "source-files.json", manifest)
    if snapshot:
        source = json.loads((snapshot / "environment.json").read_text())["source"]
        commit = source["commit"]
        diff = (snapshot / "source.patch").read_bytes()
    else:
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        diff = subprocess.check_output(["git", "diff", "HEAD", "--binary"], cwd=ROOT)
    (out / "source.patch").write_bytes(diff)
    return repo, {"commit": commit, "tracked_diff_sha256": hashlib.sha256(diff).hexdigest(),
                  "frozen_files_sha256": digest(out / "source-files.json"), "source_root": str(source_root),
                  "parent_snapshot":str(snapshot) if snapshot else None,
                  "fixture_adjustments_sha256":digest(out / "fixture-adjustments.json")}


def build(repo: Path, out: Path, env: dict, sdk: Path, godot_cpp: Path, jobs: int) -> Path:
    directory = out / "build"
    command = ["cmake", "-S", str(repo), "-B", str(directory), "-DCMAKE_BUILD_TYPE=Release",
               "-DGMJ_VIEWER_BENCHMARK=ON", "-DFETCHCONTENT_FULLY_DISCONNECTED=ON",
               f"-DGMJ_MUJOCO_ROOT={sdk}", f"-DFETCHCONTENT_SOURCE_DIR_GODOT-CPP={godot_cpp}",
               f"-DGMJ_ADDON_BIN={repo / 'addons/godot_mujoco/bin'}"]
    execute(command, out / "configure.log", env)
    execute(["cmake", "--build", str(directory), "--parallel", str(jobs)], out / "build.log", env, timeout=1800)
    return directory / "gmj_viewer_native"


def prepare_project(repo: Path, workload: str) -> Path:
    project = repo / "examples" / ("shape_gallery" if workload == "gallery" else "g1_passive")
    harness = repo / "tests/viewer_performance"
    shutil.copyfile(harness / "runner.gd", project / "benchmark_runner.gd")
    shutil.copyfile(harness / "stats.gd", project / "benchmark_stats.gd")
    return project


def report(out: Path, runs: list[dict], environment: dict, quick: bool, audit: dict | None = None) -> dict:
    groups: dict[tuple, list[dict]] = {}
    for run in runs:
        groups.setdefault((run["workload"], run["profile"], run["mode"], run["backend"]), []).append(run)
    comparisons = []
    for workload, profile, mode, backend in sorted(groups):
        if backend != "godot":
            continue
        godot = groups[(workload, profile, mode, "godot")]
        native = groups[(workload, profile, mode, "native")]
        if mode == "physics":
            g = statistics.median(r["steps"] / r["elapsed_s"] for r in godot)
            n = statistics.median(r["steps"] / r["elapsed_s"] for r in native)
            ratio, passed = g / n, g / n >= .9
        else:
            g = statistics.median(r["summary"]["frame_ms"]["p95"] for r in godot)
            n = statistics.median(r["summary"]["frame_ms"]["p95"] for r in native)
            ratio, passed = g / n, g / n <= 1.2
        capped = any(r.get("summary", {}).get("possible_present_cap", False) for r in godot + native)
        comparisons.append({"workload": workload, "profile": profile, "mode": mode, "godot": g, "native": n,
                            "ratio": ratio, "passed": passed if profile == "common" and mode != "paused" and not capped and not quick else None,
                            "possible_present_cap": capped})
    acceptance = [row for row in comparisons if row["profile"] == "common" and row["mode"] != "paused"]
    expected = {(w, p, m, b, r) for w in ("gallery", "g1-single", "g1-dual")
                for p, m in (("common", "physics"), ("common", "static"), ("common", "running"), ("default", "running"))
                for b in ("godot", "native") for r in (1, 2, 3)}
    complete = expected <= {(r["workload"], r["profile"], r["mode"], r["backend"], r["repeat"]) for r in runs}
    accepted = None if quick or not complete or any(row["passed"] is None for row in acceptance) else all(row["passed"] for row in acceptance)
    if accepted and audit is None:
        accepted = None
    observations = []
    for run in runs:
        if run["profile"] == "default" and run["backend"] == "godot" and "prefix" in run:
            observations.append(dict(observe_picking(Path(run["prefix"] + ".csv")), workload=run["workload"], repeat=run["repeat"], frame_p95_ms=run["summary"]["frame_ms"]["p95"], ray_p95_ms=run["summary"]["ray_ms"]["p95"]))
    result = {"kind": "smoke" if quick else "acceptance", "complete": complete, "environment": environment, "comparisons": comparisons, "runs": runs, "picking_observations":observations,
              "reporting_sha256":REPORTING_SHA256,
              "accepted": accepted, "audit":{key:value for key, value in audit.items() if key != "verified_files"} if audit else None}
    save_json(out / "results.json", result)
    lines = ["# Godot / MuJoCo viewer 性能对照", "", f"类型：{'短测（不作性能验收）' if quick else '正式采样'}。完整采样：{'是' if complete else '否'}。", "",
             "| 负载 | 画面 | 测试 | Godot | 原生 | 比值 | 门槛 |", "|---|---|---|---:|---:|---:|---|"]
    for row in comparisons:
        unit = "steps/s" if row["mode"] == "physics" else "ms p95"
        verdict = "参考" if row["passed"] is None else ("通过" if row["passed"] else "未达到")
        if row["possible_present_cap"]:
            verdict = "可能受呈现限速，结论无效"
        lines.append(f"| {row['workload']} | {row['profile']} | {row['mode']} | {row['godot']:.3f} {unit} | {row['native']:.3f} {unit} | {row['ratio']:.3f} | {verdict} |")
    lines += ["", "## 测量口径", "",
              "- 共同画面关闭阴影、反射、天空、抗锯齿，采用无光照基础材质；相机、视口和可见 geom ID 相同。",
              "- 原生基线是使用官方 mjv_updateScene/mjr_render 的独立最小 viewer，不包含 simulate 面板、历史采集或独立物理线程。",
              "- 两端均隐藏 UI 绘制；Godot 保留现有示例的 UI/隐藏碰撞更新工作。默认画面的灯光、天空、材质并不等价，只作参考。",
              "- static 为纯绘制：Godot 场景运行回调冻结。paused 保留暂停状态下的现有回调，作为一次额外诊断；running 保留完整运行路径。",
              "- 共同画面关闭 Godot 自动鼠标拾取，以对应原生无点击时的行为；默认画面保留原设置，鼠标固定在视口中心，另计 ray_ms。",
              "- 物理测试使用相同初态、固定步数和零额外噪声。Godot 保留每个物理 tick 的真实后端分组、接触整理和 mj_forward，原生直接循环 mj_step。",
              "- CSV 的 frame_ms 是完整帧间墙钟时间；render_cpu_ms 只是 CPU 准备/提交时间，不能当作 GPU 完成时间。",
              "- 原生 GPU 时间使用异步 GL_TIME_ELAPSED，Godot 使用 viewport GPU timer；零或不可用值不参与 GPU 汇总。",
              "- source-files.json、source.patch、fixtures/ 和每次运行的元数据保存来源、模型、状态、环境和原始样本。",
              "- 独立原生 viewer 的成绩不能直接代表嵌入 Godot 后的性能。本报告不自动更换渲染架构。", "", "## 开销分解", "",
              "| 负载/画面/模式 | 后端 | 步进 p95 ms | 状态字典 p95 ms | 状态栏读取 p95 ms | 射线查询 p95 ms | 节点同步 p95 ms | GPU p95 ms | 峰值 RSS MiB |",
              "|---|---|---:|---:|---:|---:|---:|---:|---:|"]
    for key, values in sorted(groups.items()):
        if key[2] == "physics":
            continue
        def metric(name):
            samples = [r["summary"][name]["p95"] for r in values if name in r["summary"]]
            return f"{statistics.median(samples):.3f}" if samples else "—"
        memory = max(r["execution"]["peak_rss_kb"] for r in values) / 1024
        lines.append(f"| {'/'.join(key[:3])} | {key[3]} | {metric('step_ms')} | {metric('state_ms')} | {metric('info_ms')} | {metric('ray_ms')} | {metric('sync_ms')} | {metric('gpu_ms')} | {memory:.1f} |")
    lines += ["", "RSS 为进程峰值，包含夹具初始化、截图和样本缓存，不代表稳定渲染内存。默认画面及 paused 为参考项；少于十帧时 p95 仅供粗略诊断。"]
    if observations:
        lines += ["", "## 默认画面逐轮拾取观测", "",
                  "自动拾取开关开启，不保证窗口持续收到悬停事件。查询密集、稀疏及零查询轮次必须分开解释；上方默认画面汇总不用于验收。少数查询帧的停顿可能落在 p95 之外。不同指标的 p95 不可相加。", "",
                  "| 负载 | 轮次 | 帧 p95 ms | 最大帧 ms | 有查询帧占比 | 射线 p95 ms | 最大射线 ms | 射线占采样墙钟 | 射线次数 |", "|---|---:|---:|---:|---:|---:|---:|---:|---:|"]
        for item in observations:
            lines.append(f"| {item['workload']} | {item['repeat']} | {item['frame_p95_ms']:.3f} | {item['max_frame_ms']:.3f} | {item['query_frame_fraction']:.2%} | {item['ray_p95_ms']:.3f} | {item['max_ray_ms']:.3f} | {item['ray_wall_fraction']:.2%} | {item['queries']} |")
    if audit:
        lines += ["", f"原始数据复核通过：{audit['runs']} 次运行、{audit['frames']} 个图形帧；相机投影、模型/状态/二进制指纹及物理轨迹详见 [audit.json](audit.json)。"]
    lines += ["", "## 实时推进", "", "| 负载/画面 | 后端 | 仿真时间 / 墙钟时间 |", "|---|---|---:|"]
    for key, values in sorted(groups.items()):
        if key[2] == "running":
            ratio = statistics.median(r.get("simulated_s", r["sim_time"]) / r.get("actual_sample_s", r["sample_s"]) for r in values)
            lines.append(f"| {'/'.join(key[:2])} | {key[3]} | {ratio:.3f}× |")
    images = [r for r in runs if r["profile"] == "common" and r["mode"] == "static" and r["repeat"] == 1 and "prefix" in r]
    if images:
        lines += ["", "## 同机位截图", ""]
        for run in images:
            path = Path(run["prefix"] + ".png")
            if path.exists():
                lines.append(f"{run['workload']} / {run['backend']}：![{run['workload']} {run['backend']}]({path.relative_to(out)})")
    (out / "report.md").write_text("\n".join(lines) + "\n")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--godot", type=Path, default=ROOT / "third_party/godot/Godot_v4.7.2-stable_mono_linux.x86_64")
    parser.add_argument("--mujoco-root", type=Path, default=ROOT / "build-linux/_deps/mujoco-src")
    parser.add_argument("--godot-cpp", type=Path, default=ROOT / "build-linux/_deps/godot-cpp-src")
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--workloads", nargs="+", choices=["gallery", "g1-single", "g1-dual"], default=["gallery", "g1-single", "g1-dual"])
    parser.add_argument("--resume", action="store_true", help="Reuse this output's frozen source/build/fixtures and completed runs")
    parser.add_argument("--snapshot", type=Path, help="Use a previous output's frozen runtime source with the current test harness")
    parser.add_argument("--audit-only", action="store_true", help="Recheck existing raw evidence and regenerate the report without running a GPU test")
    args = parser.parse_args()
    out = args.out.resolve()
    if args.audit_only:
        previous = json.loads((out / "results.json").read_text())
        quick = previous["kind"] == "smoke"
        checked = audit_output(out, previous["runs"], previous["environment"], quick)
        report(out, previous["runs"], previous["environment"], quick, checked)
        print(f"AUDIT {out / 'audit.json'}; valid={checked['valid']}", flush=True)
        return
    out.mkdir(parents=True, exist_ok=args.resume)
    env = os.environ.copy()
    env.update(vblank_mode="0", __GL_SYNC_TO_VBLANK="0")
    for name in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        folder = out / name.lower()
        folder.mkdir(exist_ok=True)
        env[name] = str(folder)
    # Fail before spending time building if this session has no actual GPU.
    glx = subprocess.check_output(["glxinfo", "-B"], env=env, text=True, stderr=subprocess.STDOUT)
    if "Accelerated: yes" not in glx or "direct rendering: Yes" not in glx or any(s in glx.lower() for s in ("llvmpipe", "softpipe")):
        raise RuntimeError("A direct, accelerated GPU session is required")
    (out / "glxinfo.txt").write_text(glx)
    if args.resume:
        repo = out / "repo"
        environment = json.loads((out / "environment.json").read_text())
        native = out / "build/gmj_viewer_native"
    else:
        repo, source = freeze(out, args.snapshot.resolve() if args.snapshot else None)
        environment = {"source": source, "started_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(), "glxinfo": glx, "godot_sha256": digest(args.godot),
                       "mujoco_sha256": digest(args.mujoco_root / "lib/libmujoco.so"), "platform": os.uname()._asdict() if hasattr(os.uname(), "_asdict") else list(os.uname()),
                       "cpu": Path("/proc/cpuinfo").read_text(), "settings": {"width": 1920, "height": 1080, "warmup_s": 1 if args.quick else 10, "sample_s": 3 if args.quick else 30,
                       "repeats": 1 if args.quick else 3, "physics_steps": 10000, "vsync": False}}
        save_json(out / "environment.json", environment)
        print("BUILD isolated Release harness", flush=True)
        native = build(repo, out, env, args.mujoco_root.resolve(), args.godot_cpp.resolve(), args.jobs)
        environment["extension_sha256"] = digest(next((repo / "addons/godot_mujoco/bin").glob("libgodot_mujoco*.so")))
        environment["native_runner_sha256"] = digest(native)
        environment["build"] = {"type":"Release", "cmake_cache_sha256":digest(out / "build/CMakeCache.txt"), "compiler":subprocess.check_output(["c++", "--version"], text=True)}
        save_json(out / "environment.json", environment)
    env["LD_LIBRARY_PATH"] = str(repo / "addons/godot_mujoco/bin")
    settings = environment["settings"]
    if bool(settings["repeats"] == 1) != args.quick:
        raise ValueError("Cannot resume smoke output as acceptance or vice versa")
    projects = {}
    imported_projects = set()
    fixture_root = out / "fixtures"
    fixture_root.mkdir(exist_ok=True)
    runs_root = out / "runs"
    runs_root.mkdir(exist_ok=True)
    for workload in args.workloads:
        project = prepare_project(repo, workload)
        projects[workload] = project
        fixture_dir = fixture_root / workload
        if (fixture_dir / "manifest.json").exists():
            existing = json.loads((fixture_dir / "manifest.json").read_text())
            validate_workload(existing)
            save_json(fixture_dir / "camera-check.json", validate_camera(existing))
            continue
        fixture_dir.mkdir(exist_ok=True)
        import_log = out / f"import-{workload}.log"
        print(f"PREPARE {workload}", flush=True)
        if project not in imported_projects:
            execute([str(args.godot), "--headless", "--editor", "--path", str(project), "--import"], import_log, env, timeout=300)
            imported_projects.add(project)
        cfg = dict(settings, workload=workload, fixture=str(fixture_dir), mode="prepare", profile="common", output=str(fixture_dir / "prepare"))
        config_path = out / f"prepare-{workload}.json"
        save_json(config_path, cfg)
        execute([str(args.godot), "--display-driver", "x11", "--path", str(project), "--resolution", "1920x1080", "--position", "0,0", "--script", "res://benchmark_runner.gd", "--", str(config_path)], out / f"prepare-{workload}.log", env, gpu=True)
        prepared = json.loads((fixture_dir / "manifest.json").read_text())
        validate_workload(prepared)
        save_json(fixture_dir / "camera-check.json", validate_camera(prepared))
    runs = []
    for repeat in range(settings["repeats"]):
        for workload in args.workloads:
            fixture_dir = fixture_root / workload
            fixture = json.loads((fixture_dir / "manifest.json").read_text())
            cases = [("common", "physics"), ("common", "static"), ("common", "paused"), ("common", "running"), ("default", "running")]
            for profile, mode in cases:
                if mode == "paused" and repeat > 0:
                    continue
                backends = ("godot", "native") if repeat % 2 == 0 else ("native", "godot")
                paired = {}
                for backend in backends:
                    name = f"{workload}-{profile}-{mode}-{repeat + 1}-{backend}"
                    prefix = runs_root / name
                    meta_file = Path(str(prefix) + ".json")
                    print(f"RUN {name}", flush=True)
                    provenance = {"model":digest(fixture_dir / "model.mjb"), "state":digest(fixture_dir / "state.f64"),
                                  "camera":digest(fixture_dir / "camera.txt"), "visible":digest(fixture_dir / "visible.txt"),
                                  "runner":digest(repo / "tests/viewer_performance/runner.gd"),
                                  "binary":digest(native if backend == "native" else next((repo / "addons/godot_mujoco/bin").glob("libgodot_mujoco*.so"))),
                                  "settings":settings}
                    input_hash = hashlib.sha256(json.dumps(provenance, sort_keys=True).encode()).hexdigest()
                    execution_path = Path(str(prefix) + ".execution.json")
                    try:
                        reusable = meta_file.exists() and execution_path.exists() and json.loads(execution_path.read_text()).get("input_sha256") == input_hash
                    except (ValueError, OSError):
                        reusable = False
                    if not reusable:
                        if backend == "godot":
                            cfg = dict(settings, workload=workload, fixture=str(fixture_dir), mode=mode, profile=profile, output=str(prefix), warmup=settings["warmup_s"], sample=settings["sample_s"], steps=settings["physics_steps"])
                            config_path = Path(str(prefix) + ".config.json")
                            save_json(config_path, cfg)
                            command = [str(args.godot), "--display-driver", "x11", "--path", str(projects[workload]), "--resolution", "1920x1080", "--position", "0,0", "--script", "res://benchmark_runner.gd", "--", str(config_path)]
                        else:
                            command = [str(native), str(fixture_dir / "model.mjb"), str(fixture_dir / "state.f64"), str(fixture_dir / "camera.txt"), str(fixture_dir / "visible.txt"), str(prefix), mode, profile, str(settings["warmup_s"]), str(settings["sample_s"]), str(settings["physics_steps"]), "1920", "1080"]
                        execution = execute(command, Path(str(prefix) + ".log"), env, timeout=300, gpu=mode != "physics")
                        execution["input_sha256"] = input_hash
                        execution["inputs"] = provenance
                        save_json(execution_path, execution)
                    result = json.loads(meta_file.read_text())
                    convert_screenshot(prefix)
                    loaded_library = Path(result["mujoco_library"])
                    if digest(loaded_library) != environment["mujoco_sha256"]:
                        raise RuntimeError(f"Different loaded MuJoCo library: {name}: {loaded_library}")
                    result["mujoco_library_sha256"] = environment["mujoco_sha256"]
                    result.update(workload=workload, profile=profile, mode=mode, backend=backend, repeat=repeat + 1,
                                  execution=json.loads(Path(str(prefix) + ".execution.json").read_text()), prefix=str(prefix))
                    if result.get("warnings", 0):
                        raise RuntimeError(f"MuJoCo warning invalidates {name}: {result}")
                    if mode != "physics":
                        if (result["width"], result["height"]) != (1920, 1080):
                            raise RuntimeError(f"Wrong viewport: {name}")
                        result["summary"] = summarize(Path(str(prefix) + ".csv"), min_samples=1 if args.quick or profile == "default" or mode == "paused" else 10)
                    paired[backend] = result
                    runs.append(result)
                    report(out, runs, environment, args.quick) if len(runs) % 2 == 0 else None
                if mode == "physics":
                    checked = compare_states(Path(paired["godot"]["prefix"] + ".final.f64"), Path(paired["native"]["prefix"] + ".final.f64"), fixture)
                    save_json(runs_root / f"{workload}-physics-{repeat+1}-state-check.json", checked)
    result = report(out, runs, environment, args.quick)
    checked = audit_output(out, runs, environment, args.quick)
    result = report(out, runs, environment, args.quick, checked)
    print(f"REPORT {out / 'report.md'}; accepted={result['accepted']}", flush=True)


if __name__ == "__main__":
    main()
