#!/usr/bin/env python3
"""Compare two mesh export modes and sparse points from the same vendor session."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from geometry_alignment_experiment import nearest, summary


def compare(a,b,faces_a,faces_b):
    result=dict(defaultBounds=[a.min(axis=0).tolist(),a.max(axis=0).tolist()],
                identityBounds=[b.min(axis=0).tolist(),b.max(axis=0).tolist()],
                identicalTopology=a.shape==b.shape and faces_a==faces_b)
    if result['identicalTopology']:
        offsets=a-b;offset=np.median(offsets,axis=0)
        deviation=float(np.linalg.norm(offsets-offset,axis=1).max())
        result.update(indexedMedianTranslationMeters=offset.tolist(),maximumTranslationDeviationMeters=deviation,
                      sameCoordinates=bool(np.max(np.linalg.norm(offsets,axis=1))<1e-7),
                      differsOnlyByTranslation=bool(deviation<1e-7))
    else:
        result.update(defaultToIdentityVertices=summary(nearest(a,b)[0]),identityToDefaultVertices=summary(nearest(b,a)[0]))
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('directory',type=Path);args=parser.parse_args()
    root=args.directory;paths={n:root/n for n in ['input.json','mesh.json','identity-mesh.json','point-cloud.json','poses.json','bounds.json']}
    values={n:json.loads(p.read_bytes()) for n,p in paths.items()}
    if not values['input.json']['configuration'].get('coordinateAudit'):raise ValueError('Requires exports from a single coordinate-audit run')
    meshes=[]
    for name,asset in [('mesh.json','preview.usdz'),('identity-mesh.json','identity-preview.usdz')]:
        mesh=values[name]
        if mesh['modelSHA256']!=hashlib.sha256((root/asset).read_bytes()).hexdigest():raise ValueError('Mesh does not match its exported model')
        p=np.array(mesh['positions'],dtype=float)
        if p.ndim!=2 or p.shape[1]!=3 or not np.isfinite(p).all():raise ValueError('Invalid mesh coordinates')
        meshes.append(p)
    result=compare(*meshes,values['mesh.json']['triangles'],values['identity-mesh.json']['triangles'])
    points=np.array(values['point-cloud.json']['positions'],dtype=float)
    if points.ndim!=2 or points.shape[1]!=3 or not np.isfinite(points).all():raise ValueError('Invalid sparse points')
    result.update(method='same_session_mesh_coordinate_audit_v1',acceptedForHeadFitting=False,
                  inputFileHashes={n:hashlib.sha256(p.read_bytes()).hexdigest() for n,p in paths.items()},
                  sparsePointCount=len(points),sparseBounds=[points.min(axis=0).tolist(),points.max(axis=0).tolist()])
    regions=[]
    for p in meshes:
        inside=((points>=p.min(axis=0))&(points<=p.max(axis=0))).all(axis=1)
        selected=points[inside]
        regions.append(dict(pointsInsideMeshBounds=len(selected),pointsOutsideMeshBounds=int((~inside).sum()),
                            insideToMeshVertexDistances=summary(nearest(selected,p)[0]) if len(selected) else None))
    result['sparsePointChecks']=regions
    result['notes']=['Same-session default and explicit identity-transform exports compared without fitting scale or rotation.',
                     'A topology-matched translation comparison identifies export offsets, not sensor accuracy.',
                     'Sparse points may include material outside the head. Inside/outside counts are explicit; distances are to vertices, not surfaces.',
                     'This audit alone does not establish the camera-pose convention or head-fitting readiness.']
    target=root/'coordinate-audit.json'
    if target.exists():raise ValueError('Refusing to overwrite existing audit')
    target.write_text(json.dumps(result,indent=2)+'\n')
    print({k:v for k,v in result.items() if k not in ['inputFileHashes','notes','sparsePointChecks']})


if __name__=='__main__':main()
