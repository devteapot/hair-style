#!/usr/bin/env python3
"""Replay the partial-surface CLI on explicitly synthetic capture evidence."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run():
    def cli(*args, expected=0):
        result = subprocess.run([str(ROOT / "tools/dev.sh"), "swift", "run", "capture-inspect", *map(str, args)],
                                cwd=ROOT, capture_output=True, text=True, timeout=120)
        if result.returncode != expected:
            raise RuntimeError(f"Unexpected exit {result.returncode}: {result.stderr}")
        return result.stdout.strip()

    with tempfile.TemporaryDirectory(prefix="hair-surface-") as directory:
        directory = Path(directory)
        root = directory / "captures"
        bundles = [Path(cli("fixture", root, kind)) for kind in ("front", "rear")]
        manifests = [json.loads((b / "manifest.json").read_text()) for b in bundles]
        frames = [{"captureID": m["id"], "frameID": m["frames"][0]["metadata"]["id"],
                   "mask": {"size": {"width": 64, "height": 48}, "provenance": "synthetic_fixture",
                            "method": "fixture geometry mask", "includedRuns": [{"start": 0, "count": 3072}]}}
                  for m in manifests]

        def pair(x, y, label):
            return {"id": label, "source": {"x": x, "y": y}, "target": {"x": x, "y": y}}

        frames[1]["registrationToReference"] = {
            "schemaVersion": 1, "sourceFrameID": frames[1]["frameID"], "targetFrameID": frames[0]["frameID"],
            "fitPairs": [pair(10, 10, "a"), pair(40, 10, "b"), pair(10, 35, "c"), pair(40, 35, "d")],
            "validationPairs": [pair(15, 12, "e"), pair(50, 12, "f"), pair(30, 40, "g")]}
        request = {"schemaVersion": 1, "frames": frames, "samplingStride": 1,
                   "minimumConfidence": 1, "maximumEdgeMeters": 0.02, "fusionRadiusMeters": 0.0015}
        request_path, output, ply = [directory / name for name in ("request.json", "surface.json", "surface.ply")]
        request_path.write_text(json.dumps(request))
        cli("surface", root, request_path, output, ply)
        surface = json.loads(output.read_text())
        assert surface["source"] == "synthetic_fixture"
        assert not surface["completeHead"] and not surface["includesInferredAnatomy"]
        assert surface["frames"][1]["registration"]["registration"]["accepted"]
        vertices, faces = surface["vertices"], surface["triangles"]
        assert len(vertices) == 63 * 48
        # 62x47 cells; 37 boundary cells lose two faces, the corner loses one.
        assert len(faces) == 2 * (62 * 47 - 17 - 20) - 1
        assert all({o["frameIndex"] for o in v["observations"]} == {0, 1} for v in vertices)
        assert len({tuple(sorted(f)) for f in faces}) == len(faces)
        for face in faces:
            assert len(set(face)) == 3 and all(0 <= i < len(vertices) for i in face)
            depths = [vertices[i]["position"]["z"] for i in face]
            assert max(depths) - min(depths) < 0.001
        assert f"element face {len(faces)}" in ply.read_text()
        bad = copy.deepcopy(request)
        bad["frames"][1]["registrationToReference"]["validationPairs"][0]["target"]["x"] += 5
        request_path.write_text(json.dumps(bad))
        rejected = directory / "rejected.json"
        cli("surface", root, request_path, rejected, directory / "rejected.ply", expected=1)
        assert not rejected.exists()
        return {"source": "synthetic_fixture", "vertices": len(vertices), "triangles": len(faces),
                "both_observations_retained": True, "depth_discontinuity_not_bridged": True,
                "failed_registration_rejected_without_output": True, "physical_accuracy_measured": False}


if __name__ == "__main__":
    print(json.dumps(run(), indent=2))
