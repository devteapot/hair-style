#!/usr/bin/env python3
"""Verify CLI behavior against independent synthetic Euler-transform fixtures."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run():
    with tempfile.TemporaryDirectory(prefix="hair-registration-") as directory:
        directory = Path(directory)
        results = []
        for fixture, expected_exit in [("asymmetric", 0), ("disagreeing-validation", 2)]:
            output = directory / f"{fixture}.json"
            command = [str(ROOT / "tools/dev.sh"), "swift", "run", "capture-inspect", "register",
                       str(ROOT / "fixtures/registration" / f"{fixture}.json"), str(output)]
            completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
            if completed.returncode != expected_exit:
                raise RuntimeError(f"Unexpected CLI result {completed.returncode}: {completed.stderr}")
            results.append(json.loads(output.read_text()))
        accepted, rejected = results
        expected = json.loads((ROOT / "fixtures/registration/asymmetric.expected.json").read_text())
        actual_matrix = accepted["targetFromSource"]["rowMajor"]
        assert len(actual_matrix) == 16
        maximum_error = max(abs(a-b) for a, b in zip(actual_matrix, expected["targetFromSourceRowMajor"]))
        assert accepted["accepted"] and maximum_error < 1e-9
        assert accepted["outlierIDs"] == expected["outlierIDs"]
        assert not rejected["accepted"] and rejected["validationP95Meters"] > 0.02
        assert rejected["targetFromSource"] == accepted["targetFromSource"]
        bundles = []
        for kind in ("front", "rear"):
            created = subprocess.run([str(ROOT / "tools/dev.sh"), "swift", "run", "capture-inspect", "fixture", str(directory / kind), kind],
                                     cwd=ROOT, capture_output=True, text=True, timeout=120, check=True)
            bundles.append(Path(created.stdout.strip()))
        frames = [json.loads((bundle / "manifest.json").read_text())["frames"][0]["metadata"]["id"] for bundle in bundles]
        def pixel_pair(x, y, label):
            return {"id": label, "source": {"x": x, "y": y}, "target": {"x": x, "y": y}}
        selection = {"schemaVersion": 1, "sourceFrameID": frames[0], "targetFrameID": frames[1],
                     "fitPairs": [pixel_pair(10,10,"a"), pixel_pair(40,10,"b"), pixel_pair(10,35,"c"), pixel_pair(40,35,"d")],
                     "validationPairs": [pixel_pair(15,12,"e"), pixel_pair(50,12,"f"), pixel_pair(30,40,"g")]}
        selection_path = directory / "selection.json"
        selection_path.write_text(json.dumps(selection))
        capture_output = directory / "captured-registration.json"
        subprocess.run([str(ROOT / "tools/dev.sh"), "swift", "run", "capture-inspect", "register-captures",
                        *map(str, bundles), str(selection_path), str(capture_output)],
                       cwd=ROOT, capture_output=True, text=True, timeout=120, check=True)
        captured = json.loads(capture_output.read_text())
        assert captured["registration"]["accepted"] and captured["registration"]["evidenceSource"] == "synthetic_fixture"
        assert captured["sourceFrameSHA256"] != captured["targetFrameSHA256"]
        return {"source": "synthetic_fixture", "accepted_exit": 0, "rejected_exit": 2,
                "maximum_matrix_error": maximum_error,
                "validation_does_not_influence_fitting": True,
                "capture_bundle_registration_accepted": True,
                "capture_source_and_target_bound_to_distinct_frame_hashes": True}


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
