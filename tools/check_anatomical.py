#!/usr/bin/env python3
"""Independent CLI replay of a known synthetic anatomical-frame transform."""
import json
from pathlib import Path
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]


def run():
    def cli(*args, expected=0):
        process = subprocess.run([str(ROOT / "tools/dev.sh"), "swift", "run", "capture-inspect", *map(str,args)],
                                 cwd=ROOT, capture_output=True, text=True, timeout=120)
        if process.returncode != expected:
            raise RuntimeError(f"CLI exited {process.returncode}: {process.stderr}")
        return process.stdout.strip()

    canonical = [[.03,0,0],[-.03,0,0],[.008,.05,0],[0,-.015,.025]]
    vertices = [{"position": {"x": -y+.1, "y": x-.2, "z": z+.5},
                 "normal": {"x": -1,"y": 0,"z": 0}, "observations": [{"frameIndex": 0,"depthPixelIndex": i}]}
                for i,(x,y,z) in enumerate(canonical)]
    surface = {"schemaVersion": 1,"method": "synthetic_anatomical_fixture", "requestSHA256": "c"*64,
               "coordinateConvention": "reference_optical_x_right_y_down_z_forward_meters", "source": "synthetic_fixture",
               "vertices": vertices,"triangles": [[0,1,2],[0,3,1],[0,2,3]],
               "frames": [{"captureID": str(uuid.uuid4()),"frameID": str(uuid.uuid4()),"frameSHA256": "a"*64,
                           "maskSHA256": "b"*64,"source": "synthetic_fixture",
                           "referenceFromCamera": {"rowMajor": [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]},
                           "retainedSamples": 4,"skippedSamples": 0}],
               "includesInferredAnatomy": False,"completeHead": False,"notes": ["Synthetic landmarks, not a face scan"]}
    with tempfile.TemporaryDirectory(prefix="anatomical-frame-") as directory:
        directory = Path(directory)
        source, selection_path, output = [directory / n for n in ("surface.json","selection.json","canonical.json")]
        source.write_text(json.dumps(surface))
        digest = cli("surface-hash",source)
        assert len(digest) == 64
        selection = {"schemaVersion": 1,"surfaceSHA256": digest,"anatomicalLeftEyeVertex": 0,
                     "anatomicalRightEyeVertex": 1,"superiorVertex": 2,"anteriorVertex": 3,"method": "synthetic selections"}
        selection_path.write_text(json.dumps(selection))
        cli("canonical-surface",source,selection_path,output)
        result = json.loads(output.read_text())
        actual = result["canonicalFromReference"]["rowMajor"]
        expected = [0,1,0,.2,-1,0,0,.1,0,0,1,-.5,0,0,0,1]
        error = max(abs(a-b) for a,b in zip(actual,expected))
        assert error < 1e-12
        inverse = result["referenceFromCanonical"]["rowMajor"]
        inverse_error = 0.0
        for vertex, point, original in zip(result["vertices"],canonical,vertices):
            assert all(abs(vertex["position"][key]-value) < 1e-12 for key,value in zip(("x","y","z"),point))
            assert vertex["observations"] == original["observations"]
            assert abs(vertex["normal"]["y"]-1) < 1e-12
            back = [sum(inverse[row*4+col]*point[col] for col in range(3))+inverse[row*4+3] for row in range(3)]
            inverse_error = max(inverse_error, *(abs(back[i]-original["position"][key]) for i,key in enumerate(("x","y","z"))))
        assert inverse_error < 1e-12
        assert result["triangles"] == surface["triangles"]
        assert result["sourceFrameEvidence"] == surface["frames"]
        assert result["sourceSurfaceSHA256"] == digest and result["source"] == "synthetic_fixture"
        assert not result["completeHead"] and not result["inferredScalp"]
        selection["anatomicalLeftEyeVertex"],selection["anatomicalRightEyeVertex"] = 1,0
        selection_path.write_text(json.dumps(selection))
        rejected = directory / "rejected.json"
        cli("canonical-surface",source,selection_path,rejected,expected=1)
        assert not rejected.exists()
        return {"source": "synthetic_fixture","maximum_transform_error": error,"maximum_inverse_error": inverse_error,
                "topology_and_observations_preserved": True,"swapped_sides_rejected": True,
                "complete_head": False,"physical_anatomical_accuracy_measured": False}


if __name__ == "__main__":
    print(json.dumps(run(),indent=2))
