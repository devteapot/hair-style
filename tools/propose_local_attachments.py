#!/usr/bin/env python3
"""Bounded surface-only attachment proposals; no scalp or curve editing.

Only roots failing canonical preflight are searched. All outcomes remain
unreviewed for hairline, root order, growth flow and missing anatomy.
"""
import argparse
import copy
import hashlib
import itertools
import json
from pathlib import Path
import subprocess
import uuid
import numpy as np
from propose_model_mapping import xyz, nearest_triangle, attachment_boundary_report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('source','input','mapping','anatomy','output'):parser.add_argument(name,type=Path)
    parser.add_argument('--maximum-movement-meters',type=float,choices=(.002,.004),default=.002,help='Explicit research search radius; does not change source-correction or anatomy limits.')
    parser.add_argument('--refine-directions',action='store_true',help='Add 256 uniformly distributed sphere directions within the selected movement bound.')
    parser.add_argument('--inspector',type=Path,default=Path('.build/debug/capture-inspect'))
    args=parser.parse_args()
    source,inp,mapping,anatomy=[json.loads(getattr(args,n).read_text()) for n in ('source','input','mapping','anatomy')]
    if hashlib.sha256(args.source.read_bytes()).hexdigest()!=mapping['sourceArtifactSHA256']:
        raise ValueError('Source artifact mismatch')
    if [g['id'] for g in source['strands']] != [g['guideID'] for g in mapping['mappings']]:
        raise ValueError('Guide ordering mismatch')
    if any(b['binding']['normalOffsetMeters']!=0 for b in mapping['mappings']):
        raise ValueError('Expected zero-offset surface roots')
    args.output.mkdir(parents=True,exist_ok=False)
    def write(name,value):(args.output/name).write_text(json.dumps(value,indent=2,allow_nan=False)+'\n')
    def preflight(path,output):
        result=subprocess.run([str(args.inspector.resolve()),'hair-root-preflight',str(args.input),str(path),str(args.anatomy),'0.00005',str(args.output/output)],capture_output=True,timeout=120)
        if result.returncode not in (0,2):raise RuntimeError(result.stderr.decode()[-2000:])
        return json.loads((args.output/output).read_text())
    original=preflight(args.mapping,'baseline.json')
    conflicts={v['guideID'] for v in original['violations']}
    scalp=np.array([xyz(p) for p in inp['scalp']['vertices']])[np.array(inp['scalp']['triangles'])]
    surfaces=[np.array([xyz(p) for p in s['vertices']])[np.array(s['triangles'])] for s in anatomy['surfaces']]
    roots=np.array([np.array(g['binding']['barycentric'])@scalp[g['binding']['triangleIndex']] for g in mapping['mappings']])
    transformed=xyz(mapping['targetCenterMeters'])+(np.array([g['points'][0] for g in source['strands']])-xyz(mapping['sourceCenter']))*xyz(mapping['metersPerSourceUnit'])
    proposal=copy.deepcopy(mapping);proposal['id']=str(uuid.uuid4())
    proposal['method']+=f' Unreviewed bounded local surface search for conflicting roots only, maximum {args.maximum_movement_meters*1000:g} mm movement. Hairline, root order and growth flow unverified.'
    directions=np.array([p for p in itertools.product((-1,0,1),repeat=3) if p!=(0,0,0)],dtype=float)
    directions/=np.linalg.norm(directions,axis=1)[:,None]
    if args.refine_directions:
        indices=np.arange(256,dtype=float)
        y=1-2*(indices+0.5)/256
        angle=indices*np.pi*(3-np.sqrt(5))
        radius=np.sqrt(1-y*y)
        directions=np.r_[directions,np.c_[radius*np.cos(angle),y,radius*np.sin(angle)]]
    required=anatomy['clearanceMeters']+original['materialRadiusMeters']
    updated=roots.copy();decisions=[]
    radii=np.arange(1,round(args.maximum_movement_meters/.0005)+1)*.0005
    for i,b in enumerate(proposal['mappings']):
        if b['guideID'] not in conflicts:continue
        candidates=[]
        # A deterministic finite search, not a proof that no feasible root exists.
        for radius in radii:
            for direction in directions:
                triangle,weights,_=nearest_triangle(roots[i]+radius*direction,scalp)
                point=weights@scalp[triangle]
                movement=float(np.linalg.norm(point-roots[i]))
                correction=float(np.linalg.norm(point-transformed[i]))
                if movement>args.maximum_movement_meters+1e-12 or correction>mapping['maximumRootCorrectionMeters']:continue
                distances=[nearest_triangle(point,s)[2] for s in surfaces]
                if min(distances)<=required+0.00001:continue
                # Do not introduce a closer near-coincidence than was already present.
                previous=float(np.linalg.norm(np.delete(roots,i,axis=0)-roots[i],axis=1).min())
                nearest=float(np.linalg.norm(np.delete(updated,i,axis=0)-point,axis=1).min())
                if nearest<min(previous,0.0001):continue
                candidates.append((movement,correction,triangle,weights,point,min(distances),nearest))
        if candidates:
            best=min(candidates,key=lambda c:(c[0],c[1],c[2]))
            b['binding']=dict(triangleIndex=best[2],barycentric=best[3].tolist(),normalOffsetMeters=0)
            updated[i]=best[4]
            decisions.append(dict(guideID=b['guideID'],feasibleSamples=len(candidates),changed=True,
                movementMeters=best[0],sourceCorrectionMeters=best[1],minimumAnatomyDistanceMeters=best[5],nearestOtherRootMeters=best[6]))
        else:
            decisions.append(dict(guideID=b['guideID'],feasibleSamples=0,changed=False))
    write('mapping.json',proposal)
    result=preflight(args.output/'mapping.json','preflight.json')
    corrections=np.linalg.norm(updated-transformed,axis=1)
    report=dict(method='bounded_local_surface_attachment_probe_v1',
        inputFileSHA256={n:hashlib.sha256(getattr(args,n).read_bytes()).hexdigest() for n in ('source','input','mapping','anatomy')},
        directionCount=len(directions),sampleRadiiMeters=radii.tolist(),maximumPermittedMovementMeters=args.maximum_movement_meters,
        guideCount=len(roots),originalRootConflicts=len(original['violations']),remainingRootConflicts=len(result['violations']),
        changedRoots=sum(d['changed'] for d in decisions),maximumRootMovementMeters=float(np.linalg.norm(updated-roots,axis=1).max()),
        guidesExceedingUnchangedCorrectionLimit=int(sum(corrections>mapping['maximumRootCorrectionMeters'])),
        decisions=decisions,missingRegions=result['missingRegions'],
        attachmentBoundary=attachment_boundary_report(inp['scalp'],proposal['mappings']),
        acceptedForPersonalHaircut=False,requiresAnatomicalReview=True,
        notes=['Scalp, observed anatomy, unaffected bindings and all existing limits remain unchanged.',
               'A supplied-face root pass does not establish hairline, neighbor order, emergence, flow or whole-curve clearance.',
               'No source curves or existing haircut were changed.'])
    write('report.json',report)
    print(json.dumps({k:v for k,v in report.items() if k not in ('attachmentBoundary','inputFileSHA256')},indent=2))


if __name__=='__main__':main()
