#!/usr/bin/env python3
"""Preflight and run the pinned official HAAR example; no installs/downloads.

Outputs are research geometry in HAAR coordinates, not personal haircut assets.
Run using the Python interpreter from the prepared HAAR environment.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

REVISION = "766a29a9112d84e0b5d512f9b6d7de4f27d3e857"


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def preflight(repo, config_path, checkpoint):
    errors, assets = [], {}
    result = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"],
                            capture_output=True, text=True)
    revision = result.stdout.strip()
    if result.returncode or revision != REVISION:
        errors.append("HAAR checkout must match pinned revision " + REVISION)
    dirty = subprocess.run(["git", "-C", str(repo), "diff", "HEAD", "--"],
                           capture_output=True, text=True)
    if dirty.returncode or dirty.stdout:
        errors.append("Tracked HAAR source changes are not supported")
    config = json.loads(config_path.read_text())
    paths = {"config": config_path, "diffusion": checkpoint}
    for key in ("scalp_path", "uv_path", "enc_ckpt"):
        paths[key] = repo / config["dataset"][key]
    for name, path in paths.items():
        if not path.is_file():
            errors.append("Missing asset: " + name)
        else:
            assets[name] = {"path": str(path.resolve()), "bytes": path.stat().st_size,
                            "sha256": digest(path)}
    if not (repo / config["dataset"]["path_to_data"]).is_dir():
        errors.append("Dataset directory is required by the upstream constructor")
    submodules = subprocess.run(["git", "-C", str(repo), "submodule", "status", "--recursive"],
                               capture_output=True, text=True)
    if submodules.returncode or any(line[:1] in "-+U" for line in submodules.stdout.splitlines()):
        errors.append("Submodules must be initialized at their recorded revisions")
    for module in ("torch", "numpy", "trimesh", "accelerate", "pytorch3d", "einops", "scipy"):
        if importlib.util.find_spec(module) is None:
            errors.append("Missing Python module: " + module)
    gpu = []
    try:
        import torch
        if not torch.cuda.is_available():
            errors.append("CUDA is unavailable; upstream is not a supported CPU/Metal path")
        else:
            gpu = [{"name": torch.cuda.get_device_name(i),
                    "memoryBytes": torch.cuda.get_device_properties(i).total_memory}
                   for i in range(torch.cuda.device_count())]
    except ImportError:
        pass
    return {"schemaVersion": 1, "model": "HAAR", "revision": revision,
            "python": sys.version, "platform": platform.platform(), "gpu": gpu,
            "assets": assets, "submodules": submodules.stdout.splitlines(),
            "errors": errors, "readyForAttempt": not errors,
            "inferenceCompleted": False, "geometryValidated": False, "personalized": False}


# Execute upstream unchanged, with all RNGs seeded before model/dataset setup.
BOOTSTRAP = """
import random, runpy, sys
import numpy as np
import torch
seed = int(sys.argv.pop(1))
random.seed(seed)
np.random.seed(seed)
torch.manual_seed(seed)
torch.cuda.manual_seed_all(seed)
torch.backends.cudnn.benchmark = False
sys.path.insert(0, '.')
sys.argv[0] = 'infer.py'
runpy.run_path('infer.py', run_name='__main__')
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", type=Path)
    parser.add_argument("output", type=Path, help="New directory; existing outputs are never overwritten")
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--prompt", default="short wavy hair with a side part")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--run", action="store_true", help="Attempt real inference after preflight")
    args = parser.parse_args()
    if not 0 <= args.seed < 2**32:
        parser.error("seed must be in [0, 2^32)")
    repo, output = args.repo.resolve(), args.output.resolve()
    config = (args.config or repo / "configs/infer.json").resolve()
    checkpoint = (args.checkpoint or repo / "data/haar_diffusion.pth").resolve()
    # Fail before creating any output if the configuration cannot be inspected.
    report = preflight(repo, config, checkpoint)
    output.mkdir(parents=True, exist_ok=False)
    report.update(prompt=args.prompt, seed=args.seed, requestedRun=args.run)
    command = [sys.executable, "-c", BOOTSTRAP, str(args.seed), "--config", str(config),
               "--ckpt_path", str(checkpoint), "--save_path", str(output),
               "--exp_name", "sample", "--n_samples", "1", "--seed", str(args.seed),
               "--hairstyle_description", args.prompt, "--save_guiding_strands"]
    report["command"] = command
    report_path = output / "run.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    if args.run and report["readyForAttempt"]:
        start = time.monotonic()
        environment = dict(os.environ, PYTHONHASHSEED=str(args.seed))
        with (output / "inference.log").open("w") as log:
            result = subprocess.run(command, cwd=repo, env=environment, stdout=log, stderr=subprocess.STDOUT)
        report.update(exitCode=result.returncode, elapsedSeconds=time.monotonic() - start)
        ply = output / "sample/guiding/pc_0.ply"
        if result.returncode == 0 and ply.is_file() and ply.stat().st_size > 0:
            report["output"] = {"path": str(ply), "sha256": digest(ply), "bytes": ply.stat().st_size}
            report["inferenceCompleted"] = True
        else:
            report["errors"].append("Inference failed or did not produce the expected guiding PLY")
        report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"report": str(report_path), "errors": report["errors"],
                      "inferenceCompleted": report["inferenceCompleted"]}, indent=2))
    return 2 if report["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
