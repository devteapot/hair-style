#!/usr/bin/env python3
"""Evaluate a single decoder-probe curve in a research haircut copy.

Never selects or publishes the result. Full canonical validation and continuous
segment clearance are authoritative; numerical proximity loss is not acceptance.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import uuid
import numpy as np
from safetensors.numpy import load_file


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('probe','haircut','output'):parser.add_argument(name,type=Path)
    args=parser.parse_args()
    report=json.loads((args.probe/'report.json').read_text())
    if len(report['guideIDs'])!=1:raise ValueError('Requires one explicit decoder guide')
    for filename,key in [('generation-input.json','inputSHA256'),('mapping.json','mappingSHA256')]:
        if hashlib.sha256((args.probe/filename).read_bytes()).hexdigest()!=report[key]:
            raise ValueError('Probe input snapshot mismatch')
    anatomy=args.probe/'anatomy.json'
    if hashlib.sha256(anatomy.read_bytes()).hexdigest()!=report['surfaceDistanceProbe']['anatomySHA256']:
        raise ValueError('Anatomy snapshot mismatch')
    tensors=load_file(str(args.probe/'curves.safetensors'))
    before=tensors['originalMapped'].astype(np.float64)
    after=tensors['optimizedMapped'].astype(np.float64)
    if (before.shape!=after.shape or after.shape!=(1,100,3)
            or not np.isfinite(before).all() or not np.isfinite(after).all()):
        raise ValueError('Invalid probe tensor shape or values')
    if not np.array_equal(before[:,0],after[:,0]):raise ValueError('Decoder moved the root')
    if np.linalg.norm(after-before,axis=2).max()>.02:raise ValueError('Decoder exceeded 20 mm movement bound')
    hair=json.loads(args.haircut.read_text());identity=report['guideIDs'][0]
    matches=[i for i,g in enumerate(hair['guides']) if g['id']==identity]
    if len(matches)!=1:raise ValueError('Missing or ambiguous guide')
    index=matches[0];old=hair['guides'][index]
    xyz=lambda p:np.array([p['x'],p['y'],p['z']])
    old_points=np.array([xyz(p) for p in old['points']])
    root_correction=old_points[0]-after[0,0]
    # Only restore float32->canonical root precision, never move an attachment.
    if np.linalg.norm(root_correction)>2e-6:raise ValueError('Candidate root differs from probe binding')
    points=after[0]+root_correction
    movement=float(np.linalg.norm(points-old_points,axis=1).max())
    if movement>.02:raise ValueError('Candidate change exceeded 20 mm bound')
    args.output.mkdir(parents=True,exist_ok=False)
    cut=copy.deepcopy(hair);cut['id']=str(uuid.uuid4());cut['revision']=1
    cut.pop('parentSHA256',None);cut.pop('edit',None)
    cut['guides'][index]['points']=[dict(zip(('x','y','z'),map(float,p))) for p in points]
    cut['guides'][index]['points'][0]=copy.deepcopy(old['points'][0])
    cut['generation']['method']='single_decoder_surface_distance_research; base: '+hair['generation']['method']
    def write(name,data):(args.output/name).write_text(json.dumps(data,indent=2,allow_nan=False)+'\n')
    write('haircut.json',cut)
    cli=Path(__file__).resolve().parents[1]/'.build/debug/capture-inspect'
    runs={}
    for label,source in [('baseline',args.haircut),('candidate',args.output/'haircut.json')]:
        run=subprocess.run([str(cli),'hair-clearance',str(args.probe/'generation-input.json'),str(source),str(anatomy),str(args.output/(label+'-clearance.json'))],capture_output=True,text=True,timeout=120)
        if run.returncode not in (0,2):raise RuntimeError(run.stderr+run.stdout)
        runs[label]=json.loads((args.output/(label+'-clearance.json')).read_text())
    unrelated=lambda r:[v for v in r['violations'] if v['guideID']!=identity]
    if unrelated(runs['baseline'])!=unrelated(runs['candidate']):raise ValueError('Unrelated guide clearance changed')
    if runs['baseline']['rootViolations']!=runs['candidate']['rootViolations']:raise ValueError('Root clearance changed')
    result=dict(guideID=identity,maximumMovementFromCandidateMeters=movement,
        canonicalRootRestorationMeters=float(np.linalg.norm(root_correction)),
        baselineSelectedSegmentViolations=sum(v['guideID']==identity for v in runs['baseline']['violations']),
        candidateSelectedSegmentViolations=sum(v['guideID']==identity for v in runs['candidate']['violations']),
        baselineTotalSegmentViolations=len(runs['baseline']['violations']),
        candidateTotalSegmentViolations=len(runs['candidate']['violations']),
        unchangedOtherGuideCount=len(hair['guides'])-1,physicalFitVerified=False,promoted=False,
        probeReportSHA256=hashlib.sha256((args.probe/'report.json').read_bytes()).hexdigest(),
        probeTensorsSHA256=hashlib.sha256((args.probe/'curves.safetensors').read_bytes()).hexdigest(),
        baselineHaircutSHA256=runs['baseline']['haircutSHA256'],candidateHaircutSHA256=runs['candidate']['haircutSHA256'])
    write('report.json',result);print(json.dumps(result,indent=2))


if __name__=='__main__':main()
