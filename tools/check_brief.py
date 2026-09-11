#!/usr/bin/env python3
"""Exercise JSON-to-brief CLI, including conflict rejection before output."""
import json
from pathlib import Path
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / ".build/debug/capture-inspect"


def main():
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        subprocess.run([str(CLI), "hair-fixture", str(root)], check=True, capture_output=True)
        fixture = json.loads((root / "input.json").read_text())
        for key, name in [("scalp", "scalp"), ("hairProfile", "profile")]:
            (root / (name + ".json")).write_text(json.dumps(fixture[key]))
        request = {"schemaVersion": 1, "id": str(uuid.uuid4()), "mode": "autonomous", "seed": 42, "lengthRanges": []}
        def run(name):
            (root / "request.json").write_text(json.dumps(request))
            return subprocess.run([str(CLI), "hair-brief", str(root / "scalp.json"),
                str(root / "profile.json"), str(root / "request.json"), str(root / name)], capture_output=True, text=True)
        assert run("autonomous.json").returncode == 0
        output = json.loads((root / "autonomous.json").read_text())
        assert len(output["decisions"]) == 6
        crown = next(d for d in output["decisions"] if d["region"] == "crown")
        assert crown["appliedLimit"]["maximumMeters"] == 0.2
        assert not output["input"]["brief"]["allowGrowth"]
        request.update(mode="guided", lengthRanges=[{"region": "crown", "minimumMeters": 0.25, "maximumMeters": 0.3}])
        assert run("conflict.json").returncode != 0
        assert not (root / "conflict.json").exists()
        request["allowGrowth"] = True
        assert run("growth.json").returncode == 0
        output = json.loads((root / "growth.json").read_text())
        assert next(d for d in output["decisions"] if d["region"] == "crown")["growthPossibleWithinRange"]
        print(json.dumps({"autonomousEvidenceBounds": True, "conflictRejectedBeforeOutput": True,
                          "explicitGrowthAllowed": True, "fixture": "synthetic", "generationVerified": False}, indent=2))


if __name__ == "__main__":
    main()
