#!/usr/bin/env python3
"""Exercise real Vision execution on non-face evidence; not positive face validation."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run():
    def cli(*args, expected=0):
        result = subprocess.run([str(ROOT / "tools/dev.sh"), "swift", "run", "capture-inspect", *map(str,args)],
                                cwd=ROOT, capture_output=True, text=True, timeout=120)
        if result.returncode != expected:
            raise RuntimeError(f"CLI exited {result.returncode}: {result.stderr}")
        return result.stdout.strip()
    with tempfile.TemporaryDirectory(prefix="face-landmarks-") as directory:
        directory = Path(directory)
        bundle = Path(cli("fixture",directory / "captures","front"))
        reports = []
        for rotation in ("none","clockwise90","clockwise180","clockwise270"):
            output = directory / f"{rotation}.json"
            cli("face-landmarks",bundle,0,rotation,output,expected=2)
            report = json.loads(output.read_text())
            assert report["status"] == "no_face" and report["faceCount"] == 0 and report["points"] == []
            assert report["source"] == "synthetic_fixture" and report["rotationToUpright"] == rotation
            assert report["method"] == "apple_vision_face_landmarks_revision_3_constellation_76"
            reports.append(report)
        assert len({r["frameSHA256"] for r in reports}) == 1
        assert len(reports[0]["frameSHA256"]) == 64
        manifest = json.loads((bundle / "manifest.json").read_text())
        (bundle / manifest["frames"][0]["image"]["path"]).write_bytes(b"invalid")
        rejected = directory / "rejected.json"
        cli("face-landmarks",bundle,0,"none",rejected,expected=1)
        assert not rejected.exists()
        return {"source": "synthetic_fixture","vision_executed": True,"rotations_exercised": 4,
                "no_face_exit_code": 2,"tampered_image_rejected": True,
                "positive_face_detection_validated": False,"human_depth_landmarks_validated": False}


if __name__ == "__main__":
    print(json.dumps(run(),indent=2))
