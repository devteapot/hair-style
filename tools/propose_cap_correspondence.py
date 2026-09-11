#!/usr/bin/env python3
"""Research correspondence preserving normalized latitude within each scalp cap.

Does not modify the personal scalp, accept attachments, or increase correction limits.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import uuid
import numpy as np
from haar_decode_metal import read_obj
from diagnose_attachment_seam import boundary
from propose_model_mapping import xyz, nearest_triangle, attachment_boundary_report


def polar(points):
    return np.arctan2(points[:,0],points[:,2]), np.arctan2(np.linalg.norm(points[:,[0,2]],axis=1),points[:,1])


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('source','template','input','mapping','output'):p.add_argument(name,type=Path)
    p.add_argument('--transfer-fraction',type=float,default=1,
        help='Bounded global interpolation from source angular latitude to normalized-cap latitude (0…1).')
    args=p.parse_args()
    if not np.isfinite(args.transfer_fraction) or not 0<=args.transfer_fraction<=1:
        raise ValueError('Transfer fraction must be finite and within 0…1')
    source=json.loads(args.source.read_text());inp=json.loads(args.input.read_text());mapping=json.loads(args.mapping.read_text())
    if hashlib.sha256(args.source.read_bytes()).hexdigest()!=mapping['sourceArtifactSHA256']:
        raise ValueError('Source hash mismatch')
    if [g['id'] for g in source['strands']] != [b['guideID'] for b in mapping['mappings']]:
        raise ValueError('Guide ordering mismatch')
    env=mapping['envelopeGuard']['envelope'];center=xyz(env['center']);radii=xyz(env['radii'])
    source_center=xyz(mapping['sourceCenter']);scale=xyz(mapping['metersPerSourceUnit']);source_radii=radii/scale
    v,f=read_obj(args.template);edges=boundary(f);ids=np.unique(edges)
    if not len(edges) or np.any(np.bincount(edges.ravel())[ids]!=2):raise ValueError('Expected a simple cap boundary')
    phi,theta=polar((v[ids]-source_center)/source_radii);order=np.argsort(phi)
    # Angular interpolation is only meaningful for a boundary traversing azimuth once.
    lookup={int(vertex):float(angle) for vertex,angle in zip(ids,phi)}
    total=sum(abs((lookup[int(a)]-lookup[int(b)]+np.pi)%(2*np.pi)-np.pi) for a,b in edges)
    if abs(total-2*np.pi)>1e-5:raise ValueError('Source boundary is not azimuth-monotonic')
    roots=np.array([g['points'][0] for g in source['strands']])
    angle,latitude=polar((roots-source_center)/source_radii)
    extent=np.interp(angle,phi[order],theta[order],period=2*np.pi)
    fraction=latitude/extent
    if not np.isfinite(fraction).all() or np.any((fraction<0)|(fraction>1)):
        raise ValueError('Source roots exceed parameterized cap; no clipping is permitted')
    cosine=np.cos(angle)
    boundary_y=env['sideBoundaryY']+np.maximum(0,cosine)*(env['frontBoundaryY']-env['sideBoundaryY'])+np.maximum(0,-cosine)*(env['backBoundaryY']-env['sideBoundaryY'])
    normalized_latitude=fraction*np.arccos((boundary_y-center[1])/radii[1])
    target_latitude=(1-args.transfer_fraction)*latitude+args.transfer_fraction*normalized_latitude
    target=center+radii*np.c_[np.sin(target_latitude)*np.sin(angle),np.cos(target_latitude),np.sin(target_latitude)*np.cos(angle)]
    sv=np.array([xyz(v) for v in inp['scalp']['vertices']]);st=np.array(inp['scalp']['triangles'])
    proposed=copy.deepcopy(mapping);proposed['id']=str(uuid.uuid4())
    proposed['method']=f'Research cap-latitude correspondence with global transfer fraction {args.transfer_fraction:g}; preserves source azimuth. Existing coarse region labels retained. Hairline and anatomical fit unreviewed.'
    changes=[]
    for i,b in enumerate(proposed['mappings']):
        old=mapping['mappings'][i]['binding']
        if old['normalOffsetMeters']!=0:raise ValueError('Expected zero-offset bindings')
        old_root=np.array(old['barycentric'])@sv[st[old['triangleIndex']]]
        index,weights,error=nearest_triangle(target[i],sv[st]);root=weights@sv[st[index]]
        b['binding']=dict(triangleIndex=index,barycentric=weights.tolist(),normalOffsetMeters=0)
        transformed=xyz(mapping['targetCenterMeters'])+(roots[i]-source_center)*scale
        changes.append(dict(guideID=b['guideID'],rootMovementMeters=float(np.linalg.norm(root-old_root)),
            sourceToAttachmentCorrectionMeters=float(np.linalg.norm(root-transformed)),
            capDiscretizationMeters=error,normalizedSourceLatitude=float(fraction[i])))
    report=dict(method='normalized_cap_correspondence_probe_v1',
        transferFraction=args.transfer_fraction,
        inputFileSHA256={n:hashlib.sha256(getattr(args,n).read_bytes()).hexdigest() for n in ('source','template','input','mapping')},
        guideCount=len(changes),decisions=changes,attachmentBoundary=attachment_boundary_report(inp['scalp'],proposed['mappings']),
        maximumRootMovementMeters=max(c['rootMovementMeters'] for c in changes),
        maximumSourceCorrectionMeters=max(c['sourceToAttachmentCorrectionMeters'] for c in changes),
        guidesExceedingUnchangedCorrectionLimit=sum(c['sourceToAttachmentCorrectionMeters']>mapping['maximumRootCorrectionMeters'] for c in changes),
        acceptedForPersonalHaircut=False,requiresAnatomicalReview=True)
    args.output.mkdir(parents=True,exist_ok=False)
    (args.output/'mapping.json').write_text(json.dumps(proposed,indent=2)+'\n')
    (args.output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ('decisions','inputFileSHA256')},indent=2))


if __name__=='__main__':main()
