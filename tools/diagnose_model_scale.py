#!/usr/bin/env python3
"""Frame-balanced scalar diagnostic. Never changes the reconstructed model."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics


def stats(values):
    if not values:return None
    values=sorted(values)
    return dict(count=len(values),medianMeters=statistics.median(values),p95Meters=values[math.ceil(.95*len(values))-1],maximumMeters=max(values))


def diagnose(frames):
    pairs={};ratios={};ids=set();misses={}
    for f in frames:
        i=f['sampleID']
        if not isinstance(i,int) or i in ids:raise ValueError('Unique integer sample IDs required')
        ids.add(i)
        a=f['modelDepthMeters'];b=f['observedDepthMeters']
        if len(a)!=len(b) or len(a)!=f['samples']:raise ValueError('Mismatched sample counts')
        if any(not math.isfinite(y) or not .01<y<3 for y in b):raise ValueError('Invalid observed depth')
        if any(x is not None and (not math.isfinite(x) or not .01<x<3) for x in a):raise ValueError('Invalid predicted depth')
        pairs[i]=[(x,y) for x,y in zip(a,b) if x is not None]
        misses[i]=len(a)-len(pairs[i])
        if pairs[i]:ratios[i]=statistics.median(y/x for x,y in pairs[i])
    fit=[i for i in sorted(ratios) if i%2==0];unused=[i for i in sorted(ratios) if i%2==1]
    if len(fit)<3 or len(unused)<3:raise ValueError('At least three fit and three unused frames required')
    scale=statistics.median(ratios[i] for i in fit)
    def evaluation(indices):
        return dict(frameIDs=indices,before=stats([abs(x-y) for i in indices for x,y in pairs[i]]),
                    after=stats([abs(scale*x-y) for i in indices for x,y in pairs[i]]))
    return dict(method='frame_balanced_depth_scale_diagnostic_v1',acceptedForHeadFitting=False,modelModified=False,
        candidateScale=scale,fit=evaluation(fit),unusedFrames=evaluation(unused),
        perFrameRatioMedians=[dict(sampleID=i,ratio=ratios.get(i),modelMisses=misses[i]) for i in sorted(ids)],
        notes=['Median of per-frame observed/model depth ratios; even sample IDs fit, odd sample IDs are unused by scale fitting.',
               'These frames all participated in vendor reconstruction and are correlated; not independent physical validation.',
               'Model misses remain recorded. A scale can compensate for coordinate, intrinsics or other errors; it does not establish their cause.',
               'No mesh or camera pose is modified. Scale hypothesis requires resolving vendor coordinate and calibration conventions first.'])


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('input',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
    if a.output.exists():p.error('Output must be new')
    raw=a.input.read_bytes();report=diagnose(json.loads(raw)['frames']);report['inputSHA256']=hashlib.sha256(raw).hexdigest()
    a.output.write_text(json.dumps(report,indent=2)+'\n');print('Candidate scale',report['candidateScale'],'unused-frame residuals',report['unusedFrames']['after'])


if __name__=='__main__':main()
