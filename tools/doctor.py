#!/usr/bin/env python3
"""Record reproducible development capabilities without device names or identifiers."""
import argparse
import datetime
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def probe(arguments, timeout=25):
    try:
        result = subprocess.run(arguments, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
        return {"return_code": result.returncode, "output": (result.stdout + result.stderr).strip()}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"return_code": None, "output": str(error)}


def inventory():
    dev = str(ROOT / "tools/dev.sh")
    result = {
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "host": {"os": platform.system(), "release": platform.release(), "architecture": platform.machine()},
        "xcode": probe([dev, "xcodebuild", "-version"]),
        "swift": probe([dev, "swift", "--version"]),
        "xcodegen": probe(["xcodegen", "--version"]),
        "python": platform.python_version(),
        "nvidia_smi_available": shutil.which("nvidia-smi") is not None,
        "physical_devices": [],
        "research_checkouts": {},
    }
    with tempfile.TemporaryDirectory(prefix="hair-device-probe-") as directory:
        output = Path(directory) / "devices.json"
        status = probe([dev, "xcrun", "devicectl", "list", "devices", "--json-output", str(output)])
        result["device_probe_return_code"] = status["return_code"]
        if status["return_code"] == 0 and output.exists():
            for device in json.loads(output.read_text()).get("result", {}).get("devices", []):
                hardware = device.get("hardwareProperties", {})
                if hardware.get("reality") != "physical":
                    continue
                connection = device.get("connectionProperties", {})
                properties = device.get("deviceProperties", {})
                result["physical_devices"].append({
                    "model": hardware.get("marketingName"),
                    "product_type": hardware.get("productType"),
                    "pairing_state": connection.get("pairingState"),
                    "tunnel_state": connection.get("tunnelState"),
                    "os_version": properties.get("osVersionNumber"),
                    "developer_mode": properties.get("developerModeStatus"),
                    "sensor_capture_validated": False,
                })
    for name in ("HAAR", "GaussianHaircut"):
        checkout = ROOT / ".research" / name
        if checkout.exists():
            result["research_checkouts"][name] = probe(["git", "-C", str(checkout), "rev-parse", "HEAD"])
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    encoded = json.dumps(inventory(), indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded)
    else:
        print(encoded, end="")
