#!/usr/bin/env python3
"""CLI generation-to-edit replay using explicitly synthetic scalp/root inputs."""
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
        def run(*args):
            return subprocess.run([str(CLI), *map(str, args)], check=True, capture_output=True)
        def write(name, value):
            path = root / name
            path.write_text(json.dumps(value))
            return path
        run("hair-fixture", root)
        fixture = json.loads((root / "haircut.json").read_text())
        request = {"schemaVersion": 1, "id": str(uuid.uuid4()), "preferredLengthMeters": 0.12,
                   "roots": [{"region": g["region"], "binding": g["root"]} for g in fixture["guides"]]}
        request_path = write("request.json", request)
        run("hair-baseline", root / "input.json", request_path, root / "result.json")
        result = json.loads((root / "result.json").read_text())
        assert result["haircut"]["generation"]["origin"] == "procedural_baseline"
        assert not result["validation"]["publishableAsValidatedDesign"]
        cut = write("generated.json", result["haircut"])
        edit = write("edit.json", {"baseSHA256": result["validation"]["haircutSHA256"],
            "operation": "shorten_to_length", "region": "fringe", "value": 0.07})
        run("hair-edit", root / "input.json", cut, edit, root / "edited.json", root / "history")
        edited = json.loads((root / "edited.json").read_text())
        assert edited["haircut"]["revision"] == 2
        assert edited["haircut"]["guides"][1] == result["haircut"]["guides"][1]
        assert abs(edited["validation"]["minimumLengthMeters"] - 0.07) < 1e-8
        print(json.dumps({"baselineGenerated": True, "existingEditorAndRepositoryUsed": True,
            "unmodifiedRegionPreserved": True, "fixture": "synthetic", "AIStylingVerified": False}, indent=2))


if __name__ == "__main__":
    main()
