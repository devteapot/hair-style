#!/usr/bin/env python3
"""Exercise canonical-guide validation, edits and saved revision identity via CLI."""
import json
import math
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run():
    def cli(*args, expected=0):
        completed = subprocess.run([str(ROOT / "tools/dev.sh"), "swift", "run", "capture-inspect", *map(str, args)],
                                   cwd=ROOT, capture_output=True, text=True, timeout=120)
        if completed.returncode != expected:
            raise RuntimeError(f"Exit {completed.returncode}: {completed.stderr}")
        return completed.stdout

    def distance(a, b):
        return math.sqrt(sum((a[key]-b[key])**2 for key in ("x", "y", "z")))

    with tempfile.TemporaryDirectory(prefix="hair-guide-") as directory:
        directory = Path(directory)
        cli("hair-fixture", directory)
        input_path, base_path, report_path = [directory / name for name in ("input.json", "haircut.json", "report.json")]
        cli("hair-validate", input_path, base_path, report_path)
        base_bytes = base_path.read_bytes()
        base = json.loads(base_bytes)
        report = json.loads(report_path.read_text())
        base_hash = report["haircutSHA256"]
        assert report["synthetic"] and "uncertain" in report["feasibility"]
        assert not report["publishableAsValidatedDesign"]
        repository = directory / "revisions"
        hashes = []
        for operation, region, value in [("shorten_to_length", "fringe", 0.07), ("scale_lateral_volume", "crown", 0.6)]:
            edit_path, result_path = directory / "edit.json", directory / f"{operation}.json"
            edit = {"baseSHA256": base_hash, "operation": operation, "region": region, "value": value}
            edit_path.write_text(json.dumps(edit))
            cli("hair-edit", input_path, base_path, edit_path, result_path, repository)
            result = json.loads(result_path.read_text())
            changed = result["haircut"]
            assert changed["revision"] == 2 and changed["parentSHA256"] == base_hash
            hashes.append(result["validation"]["haircutSHA256"])
            assert result["changedGuideIDs"] == [region]
            for before, after in zip(base["guides"], changed["guides"]):
                if before["region"] != region:
                    assert before == after
                else:
                    assert before["root"] == after["root"]
                    assert before["points"][0] == after["points"][0]
                    if operation == "shorten_to_length":
                        points = after["points"]
                        length = sum(distance(a, b) for a, b in zip(points, points[1:]))
                        assert abs(length-value) < 1e-10
                    else:
                        root = before["points"][0]
                        for a, b in zip(before["points"], after["points"]):
                            assert abs(a["y"]-b["y"]) < 1e-12
                            for axis in ("x", "z"):
                                assert abs((b[axis]-root[axis]) - value*(a[axis]-root[axis])) < 1e-12
            saved = repository / base["id"] / (hashes[-1] + ".json")
            assert json.loads(saved.read_text())["haircut"] == changed
        assert hashes[0] != hashes[1]
        assert base_path.read_bytes() == base_bytes
        original_record = repository / base["id"] / (base_hash + ".json")
        assert json.loads(original_record.read_text())["haircut"] == base
        edit["baseSHA256"] = "0"*64
        edit_path.write_text(json.dumps(edit))
        rejected = directory / "rejected.json"
        cli("hair-edit", input_path, base_path, edit_path, rejected, repository, expected=1)
        assert not rejected.exists()
        return {"source": "synthetic_fixture", "root_and_untouched_region_preserved": True,
                "shortened_arc_length_meters": 0.07, "volume_factor_verified": 0.6,
                "immutable_branches_with_distinct_hashes": True, "stale_edit_rejected": True,
                "publishable_as_validated_design": False, "person_conditioned_generation_tested": False}


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
