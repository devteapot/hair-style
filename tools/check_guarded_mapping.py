#!/usr/bin/env python3
"""Independently verify bounded corrections and full-segment envelope minima."""
import argparse
import json
from pathlib import Path
import numpy as np
from propose_model_mapping import xyz


def minimum_radius(points,center,radii):
    q=(points-center)/radii
    start=q[:-1];direction=np.diff(q,axis=0)
    t=np.clip(-np.sum(start*direction,axis=1)/np.sum(direction*direction,axis=1),0,1)
    analytical=np.linalg.norm(start+t[:,None]*direction,axis=1)
    sampled=np.stack([np.linalg.norm(start+step*direction,axis=1) for step in np.linspace(0,1,9)])
    assert np.all(sampled.min(axis=0)>=analytical-1e-12)
    return float(analytical.min())


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before',type=Path)
    parser.add_argument('guarded',type=Path)
    args=parser.parse_args()
    original=json.loads((args.before/'imported.json').read_text())
    corrected=json.loads((args.guarded/'imported.json').read_text())
    input=json.loads((args.guarded/'input.json').read_text())
    request=corrected['request']['envelopeGuard'];claimed=corrected['envelopeGuard']
    assert input['brief']['envelopeGuard']==request
    assert corrected['request']['sourceArtifactSHA256']==original['request']['sourceArtifactSHA256']
    env=request['envelope'];center=xyz(env['center']);radii=xyz(env['radii'])
    minimum_allowed=1-request['permittedInsetMeters']/max(radii)
    changed=[];changed_points=0;maximum=0.;minimum=2.
    for before,after in zip(original['haircut']['guides'],corrected['haircut']['guides']):
        assert before['id']==after['id'] and before['root']==after['root'] and before['points'][0]==after['points'][0]
        a=np.array([xyz(p) for p in before['points']]);b=np.array([xyz(p) for p in after['points']])
        assert a.shape==b.shape
        distance=np.linalg.norm(a-b,axis=1);count=int(np.sum(distance>1e-12))
        changed_points+=count;maximum=max(maximum,float(distance.max()))
        if count:changed.append(after['id'])
        minimum=min(minimum,minimum_radius(b,center,radii))
    assert changed==claimed['changedGuideIDs'] and changed_points==claimed['changedPointCount']
    assert abs(maximum-claimed['maximumPointCorrectionMeters'])<1e-12
    assert maximum<=request['maximumPointCorrectionMeters']+1e-12 and minimum>=minimum_allowed-1e-12
    assert not corrected['acceptedForPersonalHaircut'] and not claimed['physicalClearanceVerified']
    edits={}
    parent=corrected['haircut']
    for filename,region in [('fringe-result.json','fringe'),('crown-result.json','crown')]:
        path=args.guarded/filename
        if not path.exists():continue
        edited=json.loads(path.read_text());curve_minimum=2.;modified=[]
        assert edited['haircut']['briefSHA256']==parent['briefSHA256']
        assert edited['haircut']['generation']==parent['generation']
        for before,after in zip(parent['guides'],edited['haircut']['guides']):
            assert before['root']==after['root'] and before['points'][0]==after['points'][0]
            if before!=after:modified.append(after['id']);assert after['region']==region
            curve_minimum=min(curve_minimum,minimum_radius(np.array([xyz(p) for p in after['points']]),center,radii))
        assert modified==edited['changedGuideIDs'] and curve_minimum>=minimum_allowed-1e-12
        edits[region]=dict(changedGuideCount=len(modified),minimumNormalizedRadius=curve_minimum)
        parent=edited['haircut']
    result=dict(method='independent_continuous_guard_checks_v1',guideCount=len(corrected['haircut']['guides']),
        changedGuideIDs=changed,changedPointCount=changed_points,maximumCorrectionMeters=maximum,
        requiredMinimumNormalizedRadius=minimum_allowed,actualMinimumNormalizedRadius=minimum,
        radialPenetrationUpperBoundMeters=max(0,1-minimum)*max(radii),edits=edits,
        rootsAndUnaffectedGuidesPreserved=True,guardRetainedInBrief=True,physicalClearanceVerified=False)
    (args.guarded/'independent-guard-checks.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
