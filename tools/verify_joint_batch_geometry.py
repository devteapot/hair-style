#!/usr/bin/env python3
"""Independent geometry checks for the combined fresh-sample attachment proposal."""
import argparse
import json
from pathlib import Path
import numpy as np
from safetensors.numpy import load_file


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['baseline','candidate','input','mapping','latent_bundle','output']:p.add_argument(name,type=Path)
    args=p.parse_args();base=json.loads(args.baseline.read_text());candidate=json.loads(args.candidate.read_text());inp=json.loads(args.input.read_text());mapping=json.loads(args.mapping.read_text())
    assert [g['id'] for g in base['guides']]==[g['id'] for g in candidate['guides']]==[m['guideID'] for m in mapping['mappings']]
    xyz=lambda p:[p[k] for k in ('x','y','z')]
    before=np.array([[xyz(p) for p in g['points']] for g in base['guides']]);after=np.array([[xyz(p) for p in g['points']] for g in candidate['guides']])
    assert before.shape==after.shape and np.isfinite(after).all()
    changes=[a['id'] for a,b in zip(base['guides'],candidate['guides']) if a!=b]
    pairwise_error=0
    for a,b in zip(before,after):
        pairwise_error=max(pairwise_error,float(np.max(np.abs(np.linalg.norm(a[:,None]-a[None,:],axis=2)-np.linalg.norm(b[:,None]-b[None,:],axis=2)))))
    root_movement=float(np.linalg.norm(after[:,0]-before[:,0],axis=1).max())
    assert root_movement<=.004+1e-12 and pairwise_error<1e-10
    lengths=np.linalg.norm(np.diff(after,axis=1),axis=2).sum(axis=1)
    limits={v['region']:v for v in inp['brief']['lengthLimits']}
    for g,length in zip(candidate['guides'],lengths):
        bound=limits[g['region']];assert bound['minimumMeters']-1e-10<=length<=bound['maximumMeters']+1e-10
    original=load_file(str(args.latent_bundle))['originalMapped'].astype(float)
    assert original.shape==after.shape
    cumulative=float(np.linalg.norm(after-original,axis=2).max())
    report=dict(changedGuideIDs=changes,unchangedGuideCount=len(before)-len(changes),maximumRootMovementMeters=root_movement,
        maximumPairwiseCurveDistanceErrorMeters=pairwise_error,allRegionalLengthsPreserved=True,
        maximumPointMovementFromExportMeters=float(np.linalg.norm(after-before,axis=2).max()),
        maximumPointMovementFromOriginalDecodeMeters=cumulative,within20mmOfOriginalDecode=cumulative<=.02,
        acceptedForPersonalHaircut=False)
    args.output.write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))

if __name__=='__main__':main()
