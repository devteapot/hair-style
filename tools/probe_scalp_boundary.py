#!/usr/bin/env python3
"""Bounded inferred front-boundary proposals; never anatomical acceptance.

Uses the Swift scalp builder and canonical root checks. Preserves all guide
bindings, source transform, observed anatomy, constraints and correction limits.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import uuid
import numpy as np


def xyz(point):
    return np.array([point[k] for k in ('x','y','z')],dtype=float)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('source','input','mapping','review','anatomy','output'):
        parser.add_argument(name,type=Path)
    parser.add_argument('--inspector',type=Path,default=Path('.build/debug/capture-inspect'))
    args=parser.parse_args()
    source,base,mapping,review,anatomy=[json.loads(getattr(args,n).read_text()) for n in ('source','input','mapping','review','anatomy')]
    if hashlib.sha256(args.source.read_bytes()).hexdigest()!=mapping['sourceArtifactSHA256']:
        raise ValueError('Source artifact mismatch')
    if [g['id'] for g in source['strands']] != [g['guideID'] for g in mapping['mappings']]:
        raise ValueError('Guide ordering mismatch')
    request=review['revisions'][-1]
    if request['envelope']!=mapping['envelopeGuard']['envelope']:
        raise ValueError('Review and mapping envelopes differ')
    if any(g['binding']['normalOffsetMeters']!=0 for g in mapping['mappings']):
        raise ValueError('This experiment requires zero-offset roots')
    args.output.mkdir(parents=True,exist_ok=False)
    def write(path,data):path.write_text(json.dumps(data,allow_nan=False)+'\n')
    def invoke(*params,allowed=(0,)):
        run=subprocess.run([str(args.inspector.resolve()),*map(str,params)],capture_output=True,timeout=120)
        if run.returncode not in allowed:
            raise RuntimeError(run.stderr.decode()[-2000:])
    # Replay the original binding preflight before changing any proposed geometry.
    invoke('hair-root-preflight',args.input,args.mapping,args.anatomy,0.00005,args.output/'baseline.json',allowed=(0,2))
    write(args.output/'surface.json',review['source'])
    write(args.output/'profile.json',base['hairProfile'])
    write(args.output/'hash-request.json',dict(schemaVersion=1,id=str(uuid.uuid4()),mode='autonomous',seed=base['brief']['seed'],lengthRanges=[]))
    vertices=np.array([xyz(p) for p in base['scalp']['vertices']]);triangles=np.array(base['scalp']['triangles'])
    old_roots=np.array([np.array(g['binding']['barycentric'])@vertices[triangles[g['binding']['triangleIndex']]] for g in mapping['mappings']])
    transformed=xyz(mapping['targetCenterMeters'])+(np.array([g['points'][0] for g in source['strands']])-xyz(mapping['sourceCenter']))*xyz(mapping['metersPerSourceUnit'])
    rows=[]
    for millimeters in (1,2,3,4):
        directory=args.output/str(millimeters);directory.mkdir()
        candidate=copy.deepcopy(request)
        candidate['revision']+=1
        candidate['scalpID']=str(uuid.uuid4())
        candidate['envelope']['frontBoundaryY']+=millimeters/1000
        candidate['envelope']['method']+=' Unreviewed research proposal: front boundary raised '+str(millimeters)+' mm to investigate supplied-face clearance.'
        write(directory/'request.json',candidate)
        invoke('scalp-complete',args.output/'surface.json',directory/'request.json',directory/'scalp-result.json')
        result=json.loads((directory/'scalp-result.json').read_text())
        if result['scalp']['triangles']!=base['scalp']['triangles']:
            raise ValueError('Scalp topology changed; fixed bindings cannot be transferred')
        write(directory/'scalp.json',result['scalp'])
        invoke('hair-brief',directory/'scalp.json',args.output/'profile.json',args.output/'hash-request.json',directory/'hash-brief.json')
        digest=json.loads((directory/'hash-brief.json').read_text())['input']['brief']['scalpSHA256']
        inp=copy.deepcopy(base);inp['scalp']=result['scalp'];inp['brief']['id']=str(uuid.uuid4());inp['brief']['scalpSHA256']=digest
        proposal=copy.deepcopy(mapping);proposal['id']=str(uuid.uuid4());proposal['scalpSHA256']=digest
        proposal['method']+=' Fixed barycentric attachments on a separate inferred-boundary proposal; anatomical review required.'
        for guard in (inp['brief']['envelopeGuard'],proposal['envelopeGuard']):
            guard['scalpSHA256']=digest;guard['envelope']=candidate['envelope']
        face=copy.deepcopy(anatomy);face['scalpSHA256']=digest
        write(directory/'input.json',inp);write(directory/'mapping.json',proposal);write(directory/'anatomy.json',face)
        invoke('hair-root-preflight',directory/'input.json',directory/'mapping.json',directory/'anatomy.json',0.00005,directory/'preflight.json',allowed=(0,2))
        check=json.loads((directory/'preflight.json').read_text())
        updated=np.array([xyz(p) for p in result['scalp']['vertices']])
        roots=np.array([np.array(g['binding']['barycentric'])@updated[triangles[g['binding']['triangleIndex']]] for g in mapping['mappings']])
        corrections=np.linalg.norm(roots-transformed,axis=1)
        decisions=[dict(guideID=g['guideID'],rootMovementMeters=float(np.linalg.norm(roots[i]-old_roots[i])),sourceCorrectionMeters=float(corrections[i])) for i,g in enumerate(mapping['mappings'])]
        write(directory/'root-decisions.json',decisions)
        rows.append(dict(frontBoundaryRaiseMillimeters=millimeters,rootConflicts=len(check['violations']),
            maximumRootMovementMeters=max(d['rootMovementMeters'] for d in decisions),
            maximumSourceCorrectionMeters=float(corrections.max()),
            guidesExceedingUnchangedCorrectionLimit=int(sum(corrections>mapping['maximumRootCorrectionMeters'])),
            missingRegions=check['missingRegions'],acceptedForPersonalHaircut=False))
    report=dict(method='bounded_inferred_front_boundary_probe_v1',
        inputFileSHA256={n:hashlib.sha256(getattr(args,n).read_bytes()).hexdigest() for n in ('source','input','mapping','review','anatomy')},
        proposals=rows,guideCount=len(mapping['mappings']),requiresAnatomicalReview=True,
        notes=['Observed anatomy was retained exactly; only the inferred cap changed.',
               'Passing supplied-face clearance does not verify scalp shape, hairline or missing ears.',
               'No neural generation or existing haircut modification was performed.'])
    write(args.output/'report.json',report)
    print(json.dumps(rows,indent=2))


if __name__=='__main__':main()
