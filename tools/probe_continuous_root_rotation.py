#!/usr/bin/env python3
"""Optimize fixed-root rigid rotations; exact canonical checks decide feasibility."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import time
import uuid
import numpy as np
import torch
from root_departure import departure_planes
from root_rotation import axis_angle_matrix


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for n in ('input','mapping','source','haircut','anatomy','output'):parser.add_argument(n,type=Path)
    args=parser.parse_args();inp,mapping,source,hair,anatomy=[json.loads(getattr(args,n).read_text()) for n in ('input','mapping','source','haircut','anatomy')]
    if hashlib.sha256(args.source.read_bytes()).hexdigest()!=mapping['sourceArtifactSHA256']:raise ValueError('Source mapping mismatch')
    ids=[g['id'] for g in hair['guides']]
    if ids!=[s['id'] for s in source['strands']] or ids!=[m['guideID'] for m in mapping['mappings']]:raise ValueError('Guide identity mismatch')
    args.output.mkdir(parents=True,exist_ok=False);cli=Path(__file__).resolve().parents[1]/'.build/debug/capture-inspect'
    def write(name,value):(args.output/name).write_text(json.dumps(value,indent=2,allow_nan=False)+'\n')
    baseline_path=args.output/'baseline-clearance.json'
    run=subprocess.run([str(cli),'hair-clearance',str(args.input),str(args.haircut),str(args.anatomy),str(baseline_path)],capture_output=True,text=True,timeout=120)
    if run.returncode!=2:raise ValueError('Expected existing curve conflicts')
    baseline=json.loads(baseline_path.read_text())
    if baseline['rootViolations']:raise ValueError('Resolve fixed root conflicts first')
    targets=sorted({v['guideID'] for v in baseline['violations']})
    if len(targets)>16:raise ValueError('At most 16 guides per research batch')
    xyz=lambda p:np.array([p[k] for k in ('x','y','z')]);triangles=np.concatenate([np.array([xyz(p) for p in s['vertices']])[s['triangles']] for s in anatomy['surfaces']])
    env=mapping['envelopeGuard']['envelope'];center=xyz(env['center']);radii=xyz(env['radii']);threshold=1-mapping['envelopeGuard']['permittedInsetMeters']/max(radii)
    scalp_triangles=np.array([xyz(p) for p in inp['scalp']['vertices']])[inp['scalp']['triangles']]
    starts=torch.cat([torch.zeros(1,3),torch.eye(3)*np.pi/18,-torch.eye(3)*np.pi/18]);torch.set_num_threads(4)
    candidates=[];decisions=[];started=time.monotonic()
    for identity in targets:
        i=ids.index(identity);guide=hair['guides'][i];points=np.array([xyz(p) for p in guide['points']]);root=points[0]
        material=next(m for m in hair['materials'] if m['id']==guide['materialID']);required=material['radiusMeters']+anatomy['clearanceMeters']
        planes=departure_planes(root,triangles,required);arc=np.r_[0,np.cumsum(np.linalg.norm(np.diff(points,axis=0),axis=1))];mask=arc<=.012
        def objective(v):
            def tensor(x):return torch.as_tensor(x,dtype=v.dtype,device=v.device)
            rotated=tensor(points-root)@axis_angle_matrix(v).transpose(-1,-2)+tensor(root)
            signed=((rotated[:,mask,None,:]-tensor(planes['origins']))*tensor(planes['normals'])).sum(-1)
            loss=torch.relu(tensor(planes['margins'])-signed).square()/.01**2
            q=(rotated-tensor(center))/tensor(radii);a=q[:,:-1];d=q[:,1:]-a
            t=(-(a*d).sum(-1)/d.square().sum(-1).clamp_min(1e-16)).clamp(0,1)
            inset=torch.relu(threshold+0.0005-torch.linalg.vector_norm(a+t[...,None]*d,dim=-1)).square()
            return (100*(loss.mean((1,2))+loss.amax((1,2)))+1000*(inset.mean(1)+inset.amax(1))+.01*v.square().sum(1)).sum()
        cpu=starts.clone().requires_grad_(True);objective(cpu).backward()
        v=starts.to('mps').detach().requires_grad_(True);objective(v).backward()
        if not torch.allclose(cpu.grad,v.grad.cpu(),atol=1e-4,rtol=1e-3):raise ValueError('Objective gradient CPU/MPS mismatch')
        v.grad=None;optimizer=torch.optim.Adam([v],lr=.01)
        for _ in range(300):
            optimizer.zero_grad();loss=objective(v)
            if not bool(torch.isfinite(loss)):raise ValueError('Nonfinite rotation loss')
            loss.backward();optimizer.step()
            with torch.no_grad():v.mul_((np.pi/9/torch.linalg.vector_norm(v,dim=1).clamp_min(1e-12)).clamp(max=1)[:,None])
        vectors=v.detach().cpu().double();rotations=axis_angle_matrix(vectors).numpy()
        binding=mapping['mappings'][i]['binding']
        if binding['normalOffsetMeters']!=0:raise ValueError('Original movement reference requires a surface-bound root')
        original_root=np.array(binding['barycentric'])@scalp_triangles[binding['triangleIndex']]
        raw=np.array(source['strands'][i]['points']);original=(raw-raw[0])*xyz(mapping['metersPerSourceUnit'])+original_root
        for start,(vector,rotation) in enumerate(zip(vectors.numpy(),rotations)):
            after=(points-root)@rotation.T+root;after[0]=root
            movement=float(np.linalg.norm(after-original,axis=1).max())
            q=(after-center)/radii;a=q[:-1];d=np.diff(q,axis=0);t=np.clip(-(a*d).sum(1)/(d*d).sum(1).clip(1e-20),0,1)
            minimum=float(np.linalg.norm(a+t[:,None]*d,axis=1).min());angle=float(np.linalg.norm(vector))
            pairwise=float(np.abs(np.linalg.norm(after[:,None]-after[None,:],axis=2)-np.linalg.norm(points[:,None]-points[None,:],axis=2)).max())
            assert pairwise<1e-12 and angle<=np.pi/9+1e-7
            eligible=movement<=.02 and minimum>=threshold
            decision=dict(guideID=identity,startIndex=start,rotationVectorRadians=vector.tolist(),angleDegrees=float(np.degrees(angle)),maximumPointMovementFromOriginalDecodeMeters=movement,envelopePassed=bool(minimum>=threshold),eligible=bool(eligible),pairwiseDistanceMaximumErrorMeters=pairwise)
            if eligible:
                cut=copy.deepcopy({k:x for k,x in hair.items() if k!='guides'});cut['id']=str(uuid.uuid4());cut['revision']=1;cut.pop('edit',None);cut.pop('parentSHA256',None);cut['generation']['method']='continuous_root_rotation_research_v1'
                cut['guides']=[copy.deepcopy(guide)];cut['guides'][0]['points']=[dict(zip(('x','y','z'),map(float,p))) for p in after]
                decision['candidateIndex']=len(candidates);candidates.append(cut)
            decisions.append(decision)
        print(json.dumps(dict(guideID=identity,optimizedStarts=7)),flush=True)
    if candidates:
        write('candidates.json',candidates);out=args.output/'candidate-clearance.json'
        run=subprocess.run([str(cli),'hair-clearance-batch',str(args.input),str(args.output/'candidates.json'),str(args.anatomy),str(out)],capture_output=True,text=True,timeout=120)
        if run.returncode not in (0,2):raise RuntimeError(run.stderr+run.stdout)
        checks=json.loads(out.read_text());assert len(checks)==len(candidates)
        for d in decisions:
            if 'candidateIndex' in d:
                r=checks[d['candidateIndex']];d.update(segmentConflicts=len(r['violations']),rootConflicts=len(r['rootViolations']))
    write('report.json',dict(method='continuous_root_rotation_research_v1',inputHashes={n:hashlib.sha256(getattr(args,n).read_bytes()).hexdigest() for n in ('input','mapping','source','haircut','anatomy')},scriptSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),cpuMPSObjectiveGradientsAgree=True,seconds=time.monotonic()-started,decisions=decisions,promoted=False,physicalFitVerified=False))


if __name__=='__main__':main()
