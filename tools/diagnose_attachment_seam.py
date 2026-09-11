#!/usr/bin/env python3
"""Locate reported root conflicts relative to open scalp/face boundaries.

Distances describe supplied geometry only; no anatomical fit is inferred.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import numpy as np


def boundary(triangles):
    counts = Counter(tuple(sorted((t[i], t[(i+1)%3]))) for t in triangles for i in range(3))
    if any(n > 2 for n in counts.values()):
        raise ValueError('Nonmanifold input')
    return np.array([edge for edge, count in counts.items() if count == 1], dtype=int)


def segment_distance(point, vertices, edges):
    if not len(edges):
        return None
    a = vertices[edges[:,0]]; d = vertices[edges[:,1]]-a
    t = np.clip(np.sum((point-a)*d, axis=1)/np.maximum(np.sum(d*d,axis=1),1e-30),0,1)
    return float(np.linalg.norm(point-a-t[:,None]*d, axis=1).min())


def xyz(point):
    return [point[k] for k in ('x','y','z')]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('input','mapping','anatomy','preflight','output'):
        p.add_argument(name,type=Path)
    p.add_argument('--inspector',type=Path,default=Path(__file__).resolve().parents[1]/'.build/debug/capture-inspect')
    args=p.parse_args()
    inp,mapping,anatomy,preflight=[json.loads(getattr(args,n).read_text()) for n in ('input','mapping','anatomy','preflight')]
    with tempfile.TemporaryDirectory() as directory:
        replay=Path(directory)/'preflight.json'
        result=subprocess.run([str(args.inspector.resolve()),'hair-root-preflight',
            str(args.input.resolve()),str(args.mapping.resolve()),str(args.anatomy.resolve()),
            str(preflight['materialRadiusMeters']),str(replay)],capture_output=True,timeout=120)
        if result.returncode not in (0,2) or json.loads(replay.read_text()) != preflight:
            raise ValueError('Preflight does not replay against supplied geometry')
    scalp=inp['scalp']; sv=np.array([xyz(v) for v in scalp['vertices']]); st=np.array(scalp['triangles'])
    se=boundary(st); boundary_vertices=set(se.flatten().tolist())
    bindings={b['guideID']:b for b in mapping['mappings']}
    surfaces={s['region']:s for s in anatomy['surfaces']}
    rows=[]
    for conflict in preflight['violations']:
        binding=bindings[conflict['guideID']]['binding']; triangle=st[binding['triangleIndex']]
        if binding['normalOffsetMeters'] != 0:
            raise ValueError('Diagnostic currently requires zero normal offset')
        root=np.array(binding['barycentric'])@sv[triangle]
        face=surfaces[conflict['region']]; fv=np.array([xyz(v) for v in face['vertices']]); ft=np.array(face['triangles'])
        fe=boundary(ft); face_boundary=set(fe.flatten().tolist())
        nearest=ft[conflict['triangleIndex']]
        rows.append(dict(guideID=conflict['guideID'],region=bindings[conflict['guideID']]['region'],
            rootMeters=root.tolist(),scalpTriangleIndex=binding['triangleIndex'],
            scalpTriangleTouchesBoundary=bool(boundary_vertices.intersection(triangle.tolist())),
            rootToScalpBoundaryMeters=segment_distance(root,sv,se),
            rootToAnatomyBoundaryMeters=segment_distance(root,fv,fe),
            anatomyTriangleTouchesBoundary=bool(face_boundary.intersection(nearest.tolist())),
            reportedSurfaceDistanceMeters=conflict['distanceMeters'],
            requiredDistanceMeters=conflict['requiredDistanceMeters']))
    report=dict(method='attachment_seam_localization_v1',
        filesSHA256={n:hashlib.sha256(getattr(args,n).read_bytes()).hexdigest() for n in ('input','mapping','anatomy','preflight')},
        scalpBoundaryEdges=len(se),conflicts=rows,physicalFitVerified=False,
        canonicalPreflightReplayed=True,
        limitations=[
            'Proximity to a construction boundary does not establish a true hairline.',
            'No registration accuracy, biological shape or correction is inferred.'])
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(rows,indent=2))


if __name__=='__main__': main()
