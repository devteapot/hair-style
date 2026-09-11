#!/usr/bin/env python3
"""Evaluate adjacent captured RGB/depth registrations and report graph connectivity.

Every edge is a candidate local fit, never a full-head registration. Original
capture payloads are validated by capture-inspect. Failed edges remain visible.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def components(nodes, edges):
    adjacency = {n: set() for n in nodes}
    for a, b in edges:
        if a not in adjacency or b not in adjacency or a == b:
            raise ValueError('Invalid graph edge')
        adjacency[a].add(b); adjacency[b].add(a)
    remaining = set(nodes)
    result = []
    while remaining:
        todo = [min(remaining)]; reached = set()
        while todo:
            node = todo.pop()
            if node in reached: continue
            reached.add(node); todo.extend(adjacency[node] - reached)
        remaining -= reached; result.append(sorted(reached))
    return sorted(result, key=lambda c: (-len(c), c[0]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('masks', type=Path)
    parser.add_argument('output', type=Path, help='New output directory')
    parser.add_argument("--cli", type=Path, help="Explicit freshly built inspector executable")
    args = parser.parse_args()
    manifest = json.loads((args.bundle/'manifest.json').read_text())
    masks = json.loads(args.masks.read_text())
    if masks['captureID'] != manifest['id'] or manifest['status'] != 'completed':
        raise ValueError('Masks must belong to this completed capture')
    by_id = {f['frameID']: f for f in masks['frames']}
    nodes = [i for i, f in enumerate(manifest['frames'])
             if by_id.get(f['metadata']['id'], {}).get('mask')]
    if len(nodes) < 2: raise ValueError('Insufficient masked frames')
    args.output.mkdir(parents=True, exist_ok=False)
    cli = args.cli.resolve() if args.cli else Path(__file__).resolve().parents[1]/'.build/debug/capture-inspect'
    summary = dict(schemaVersion=1, captureID=manifest['id'],
        manifestSHA256=hashlib.sha256((args.bundle/'manifest.json').read_bytes()).hexdigest(),
        masksSHA256=hashlib.sha256(args.masks.read_bytes()).hexdigest(),
        status='running', frameIndices=nodes, edges=[], acceptedForFullHead=False,
        notes=['Adjacent original indices only; missing masks are not silently bridged.',
               'Local fit gates do not prove loop closure, semantic correctness or anatomical accuracy.',
               'No transform composition, fusion or scale adjustment is performed.'])
    def save():
        edges = [(e['sourceIndex'], e['targetIndex']) for e in summary['edges'] if e['localAccepted']]
        summary['components'] = components(nodes, edges)
        path=args.output/'summary.json'; temp=args.output/'summary.tmp'
        temp.write_text(json.dumps(summary, indent=2)+'\n'); temp.replace(path)
    save()
    for source, target in zip(nodes, nodes[1:]):
        if target != source+1: continue
        a=manifest['frames'][source]['metadata']['id']; b=manifest['frames'][target]['metadata']['id']
        request=dict(sourceFrameID=a,targetFrameID=b,sourceMask=by_id[a]['mask'],targetMask=by_id[b]['mask'],
            depthGridStride=2,maximumRoundTripPixels=1.5,minimumConfidence=1)
        stem=f'{source}-{target}'
        request_path=args.output/f'{stem}-request.json'; report_path=args.output/f'{stem}-report.json'
        request_path.write_text(json.dumps(request))
        result=subprocess.run([str(cli),'flow-register',str(args.bundle),str(request_path),str(report_path)],
                              capture_output=True,text=True)
        report=json.loads(report_path.read_text()) if result.returncode==0 and report_path.exists() else {}
        registration=report.get('registration',{}).get('registration',{})
        entry=dict(sourceIndex=source,targetIndex=target,localAccepted=registration.get('accepted',False),
            counts=report.get('counts'),validationMedianMeters=registration.get('validationMedianMeters'),
            validationP95Meters=registration.get('validationP95Meters'),
            failureReason=report.get('failureReason') or (result.stderr.strip() if result.returncode else None),
            exitCode=result.returncode,report=report_path.name if report else None,
            reportSHA256=hashlib.sha256(report_path.read_bytes()).hexdigest() if report else None)
        summary['edges'].append(entry);save()
        print(f'{stem}: {"local pass" if entry["localAccepted"] else "failed"}',flush=True)
    summary['status']='completed';save()
    print(f'Completed: {len(summary["components"])} components; no full-head acceptance.',flush=True)


if __name__ == '__main__': main()
