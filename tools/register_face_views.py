#!/usr/bin/env python3
"""Replay candidate Vision correspondences against original captured depth.

Uses fixed eye/nose region indices, even for fitting and odd for validation.
This is an experimental correspondence policy, not anatomical ground truth.
No model-estimated 3D points or filtering are used. The core capture adapter
verifies payloads, samples calibrated depth and applies unchanged rigid gates.
"""
import argparse
import json
import math
import subprocess
import time
from pathlib import Path


def candidates(path, manifest):
    report = json.loads(path.read_text())
    if report.get('captureID') != manifest['id'] or report.get('status') != 'detected':
        raise ValueError('Expected a detected landmark report for this capture')
    frame = next(f for f in manifest['frames'] if f['metadata']['id'] == report['frameID'])
    size = frame['metadata']['imageSize']
    if report['nativeImageSize'] != size:
        raise ValueError('Landmark image dimensions differ from the captured frame')
    result = {}
    for point in report['points']:
        if point['region'] not in ('vision_left_eye', 'vision_right_eye', 'vision_nose'):
            continue
        # Keep the original extractor's missing-depth exclusion. The adapter
        # independently recomputes every retained sample from original bytes.
        if 'cameraPoint' not in point:
            continue
        index = point['regionIndex']
        if type(index) is not int or index < 0 or point['id'] != f"{point['region']}:{index}":
            raise ValueError('Invalid landmark identity')
        pixel = point['nativePixel']
        if not all(math.isfinite(pixel[k]) and 0 <= pixel[k] < size[dimension]
                   for k, dimension in [('x', 'width'), ('y', 'height')]):
            raise ValueError('Invalid native landmark pixel')
        if point['id'] in result:
            raise ValueError('Duplicate landmark identity')
        result[point['id']] = point
    return report['frameID'], result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('reference', type=Path)
    parser.add_argument('output', type=Path, help='New output directory')
    parser.add_argument('sources', type=Path, nargs='+')
    parser.add_argument('--source-bundle', type=Path,
                        help='Optional second capture for repeat-pass registration; reference stays in bundle')
    parser.add_argument('--cli', type=Path,
                        help='Explicit capture-inspect executable; use a freshly built release binary for surveys')
    args = parser.parse_args()
    manifest = json.loads((args.bundle / 'manifest.json').read_text())
    target_id, target = candidates(args.reference, manifest)
    source_bundle = args.source_bundle or args.bundle
    source_manifest = json.loads((source_bundle / 'manifest.json').read_text())
    args.output.mkdir(parents=True, exist_ok=False)
    cli = args.cli.resolve() if args.cli else Path(__file__).resolve().parents[1] / '.build/debug/capture-inspect'
    summary = []
    seen = {target_id}
    for number, path in enumerate(args.sources):
        source_id, source = candidates(path, source_manifest)
        if source_id in seen:
            raise ValueError('Each source must be distinct from the reference and other sources')
        seen.add(source_id)
        selection = dict(schemaVersion=1, sourceFrameID=source_id,
                         targetFrameID=target_id, fitPairs=[], validationPairs=[])
        for key in sorted(source.keys() & target.keys()):
            role = 'fitPairs' if source[key]['regionIndex'] % 2 == 0 else 'validationPairs'
            selection[role].append(dict(id=key, source=source[key]['nativePixel'],
                                        target=target[key]['nativePixel']))
        selection_path = args.output / f'{number}-selection.json'
        report_path = args.output / f'{number}-report.json'
        selection_path.write_text(json.dumps(selection, indent=2))
        started = time.monotonic()
        process = subprocess.run([str(cli), 'register-captures', str(source_bundle),
                                  str(args.bundle), str(selection_path), str(report_path)],
                                 capture_output=True, text=True)
        report = json.loads(report_path.read_text()) if report_path.exists() else None
        registration = report['registration'] if report else None
        entry = dict(sourceFrameID=source_id, targetFrameID=target_id,
                     exitCode=process.returncode, wallSeconds=time.monotonic()-started,
                     selection=selection_path.name, report=report_path.name if report else None,
                     accepted=process.returncode == 0 and bool(registration and registration['accepted']),
                     diagnostic=(process.stdout + process.stderr).strip())
        summary.append(entry)
        print(f"{path.name}: {entry['diagnostic']}")
    (args.output / 'summary.json').write_text(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
