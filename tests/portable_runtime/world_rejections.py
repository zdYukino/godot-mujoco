#!/usr/bin/env python3
"""Two isolated expected-error processes; never sanitize their retained logs."""
import argparse
import json
from pathlib import Path
import subprocess

CASES = {
    "missing_model": ("Assign a world_model resource to define all global MuJoCo options", 6),
    "ownership": ("Only one MjRuntimeWorld may own a World3D; use a separate SubViewport for another world", 8),
}
MARKER = "WORLD_REJECTION_RESULT "


def audit(text, case, returncode):
    assert returncode == 0, f"{case}: process exit {returncode}"
    expected, count = CASES[case]
    errors = [line for line in text.splitlines() if "ERROR:" in line]
    assert errors == ["ERROR: " + expected], f"{case}: unexpected/missing diagnostics: {errors}"
    assert "leak" not in text.lower() and "FAIL " not in text, f"{case}: leak/assertion failure"
    reports = [line[len(MARKER):] for line in text.splitlines() if line.startswith(MARKER)]
    assert len(reports) == 1, f"{case}: missing/duplicate result"
    result = json.loads(reports[0])
    assert result["case"] == case and result["failed"] == 0, result
    assert len(result["checks"]) == count and all(c["passed"] is True for c in result["checks"]), result
    assert len({c["name"] for c in result["checks"]}) == count, result
    return result


def run(godot, project, out):
    out.mkdir(parents=True, exist_ok=False)
    results = []
    for case in CASES:
        command = [godot, "--headless", "--path", str(project), "--script", "res://world_rejection_test.gd", "--", case]
        log = out / (case + ".log")
        with log.open("w") as stream:
            try:
                process = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=90)
                code = process.returncode
            except subprocess.TimeoutExpired:
                code = 124
        row = {"case": case, "command": command, "exit": code, "log": log.name}
        try:
            row["result"] = audit(log.read_text(), case, code)
            row["passed"] = True
        except (AssertionError, KeyError, ValueError) as error:
            row.update(passed=False, failure=str(error))
        results.append(row)
        (out / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    assert all(row["passed"] for row in results), f"Negative-case audit failed; inspect {out}/results.json"
    print("ISOLATED WORLD REJECTIONS PASS; complete logs:", out)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    run(args.godot, args.project, args.out)
