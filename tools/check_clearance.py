#!/usr/bin/env python3
"""Replay anatomy-constrained edit rejection through the CLI using synthetic planes."""
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
    with tempfile.TemporaryDirectory(prefix="guide-clearance-") as directory:
        directory = Path(directory)
        cli("hair-fixture",directory)
        input_path, base, validation, anatomy_path, edit_path, output = [directory / n for n in
            ("input.json","haircut.json","validation.json","anatomy.json","edit.json","result.json")]
        cli("hair-validate",input_path,base,validation)
        cut = json.loads(base.read_text())
        original = base.read_bytes()
        base_hash = json.loads(validation.read_text())["haircutSHA256"]
        anatomy = {"schemaVersion": 1,"scalpSHA256": cut["scalpSHA256"],"clearanceMeters": .001,
                   "surfaces": [{"region": "face","origin": "synthetic","sourceSHA256": "a"*64,
                       "vertices": [{"x": .11,"y": y,"z": z} for y,z in [(0,-.2),(.4,-.2),(.4,.4),(0,.4)]],
                       "triangles": [[0,1,2],[0,2,3]]}]}
        anatomy_path.write_text(json.dumps(anatomy))
        clear_report = directory / "clearance.json"
        cli("hair-clearance",input_path,base,anatomy_path,clear_report)
        baseline = json.loads(clear_report.read_text())
        assert baseline["surfaceChecksPassed"] and baseline["synthetic"]
        assert len(baseline["missingRegions"]) == 2 and not baseline["publishableAsValidatedDesign"]
        edit = {"baseSHA256": base_hash,"operation": "scale_lateral_volume","region": "fringe","value": 1.5}
        edit_path.write_text(json.dumps(edit))
        repository = directory / "history"
        cli("hair-edit",input_path,base,edit_path,output,repository,anatomy_path,expected=1)
        assert not output.exists() and not repository.exists()
        assert base.read_bytes() == original
        edit.update(operation="shorten_to_length",value=.07)
        edit_path.write_text(json.dumps(edit))
        cli("hair-edit",input_path,base,edit_path,output,repository,anatomy_path)
        result = json.loads(output.read_text())
        assert result["clearance"]["surfaceChecksPassed"]
        assert result["clearance"]["haircutSHA256"] == result["validation"]["haircutSHA256"]
        assert result["haircut"]["parentSHA256"] == base_hash
        assert len(list((repository / cut["id"]).glob("*.json"))) == 2
        return {"source": "synthetic_fixture","baseline_clear_of_supplied_plane": True,
                "intersecting_edit_rejected_before_repository_write": True,"safe_edit_saved_with_bound_clearance_report": True,
                "base_preserved": True,"missing_ear_regions_reported": True,"physical_feasibility_validated": False}


if __name__ == "__main__":
    print(json.dumps(run(),indent=2))
