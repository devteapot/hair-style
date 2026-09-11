#!/usr/bin/env python3
"""Research search over same-region decoder latents with exact face clearance.

Retains canonical roots, regional lengths, inferred envelope, ±.25 latent and
20 mm original-decoder movement bounds. No studio selection or publication.
"""
import argparse
import copy
import json
import os
from pathlib import Path
import subprocess
import time
import uuid
import numpy as np
import root_preflight


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('optimization','haircut','input','mapping','output'):p.add_argument(name,type=Path)
    p.add_argument('--guide-id',required=True)
    root_preflight.add_arguments(p);args=p.parse_args()
    if os.environ.get('PYTORCH_ENABLE_MPS_FALLBACK') not in (None,'0'):raise ValueError('Disable CPU fallback')
    preflight=root_preflight.run(args)
    import torch
    from safetensors.torch import load_file,save_file
    from haar_decode_metal import setup
    from haar_text_metal import sha256
    torch.set_num_threads(4)
    report=json.loads((args.optimization/'report.json').read_text())
    if report['inputSHA256']!=sha256(args.input) or report['mappingSHA256']!=sha256(args.mapping):raise ValueError('Optimization provenance mismatch')
    data=load_file(str(args.optimization/'curves.safetensors'))
    inp=json.loads(args.input.read_text());mapping=json.loads(args.mapping.read_text());hair=json.loads(args.haircut.read_text())
    ids=[m['guideID'] for m in mapping['mappings']]
    if ids!=report['guideIDs'] or ids!=[g['id'] for g in hair['guides']]:raise ValueError('Guide order mismatch')
    if args.guide_id not in ids:raise ValueError('Unknown guide')
    i=ids.index(args.guide_id);base=hair['guides'][i]
    if data['originalLatent'].shape!=(len(ids),64):raise ValueError('Requires full decoder field')
    xyz=lambda v:np.array([v[k] for k in ('x','y','z')],dtype=float)
    root=xyz(base['points'][0]);original=data['originalMapped'][i].numpy().astype(float)
    if np.linalg.norm(root-original[0])>2e-6:raise ValueError('Probe requires the original fixed root')
    def write(path,value):path.write_text(json.dumps(value,indent=2,allow_nan=False)+'\n')
    def clearance(cut,label):
        path=args.output/(label+'.json');write(path,cut)
        target=args.output/(label+'-clearance.json')
        result=subprocess.run([str(args.inspector.resolve()),'hair-clearance',str(args.input),str(path),str(args.anatomy),str(target)],capture_output=True,text=True,timeout=120)
        if result.returncode not in (0,2):raise RuntimeError(result.stderr+result.stdout)
        return json.loads(target.read_text())
    baseline=clearance(hair,'baseline')
    if baseline['rootViolations'] or not any(v['guideID']==args.guide_id for v in baseline['violations']):raise ValueError('Expected curve conflict without root conflicts')
    material=next(m for m in hair['materials'] if m['id']==base['materialID'])
    if material['radiusMeters']!=args.material_radius_meters:raise ValueError('Preflight material radius differs from candidate')
    h=setup(Path('.research/HAAR').resolve(),Path('.research/metal-assets/scalp'),Path('.research/metal-assets/strand_ckpt.pth'),42)
    region=mapping['mappings'][i]['region'];latent0=data['originalLatent'][i]
    donors=[j for j,m in enumerate(mapping['mappings']) if j!=i and m['region']==region]
    donors=sorted(donors,key=lambda j:float((data['originalLatent'][j]-latent0).square().sum()))[:32]
    choices=[(j,a) for j in donors for a in (.25,.5,.75,1.)]
    if not choices:raise ValueError('No same-region latent donors')
    latents=torch.stack([latent0+((1-a)*data['optimizedLatent'][i]+a*data['originalLatent'][j]-latent0).clamp(-.25,.25) for j,a in choices])
    def decode(model,x):
        offsets=model(x);local=torch.cat([torch.zeros_like(offsets[:,:1]),offsets.cumsum(1)],dim=1)
        return (h.small_R_inv[i].to(x.device)@local[...,None])[...,0]+h.small_origins[i].to(x.device)
    with torch.inference_mode():
        replay=decode(h.dec,latent0[None])
        if not torch.allclose(replay[0],data['originalTemplate'][i],atol=2e-5,rtol=0):raise ValueError('Source decoder replay failed')
        cpu=decode(h.dec,latents)
        metal=decode(h.dec.to('mps'),latents.to('mps')).cpu()
    if not torch.allclose(cpu,metal,atol=2e-5,rtol=1e-4):raise ValueError('CPU/MPS decoder disagreement')
    points=(metal.numpy().astype(float)-metal[:,:1].numpy().astype(float))*xyz(mapping['metersPerSourceUnit'])+root
    points[:,0]=root
    envelope=mapping['envelopeGuard']['envelope'];center=xyz(envelope['center']);radii=xyz(envelope['radii'])
    threshold=1-mapping['envelopeGuard']['permittedInsetMeters']/max(radii)
    q=(points-center)/radii;a=q[:,:-1];d=np.diff(q,axis=1)
    t=np.clip(-(a*d).sum(2)/(d*d).sum(2).clip(1e-20),0,1)
    minimum=np.linalg.norm(a+t[:,:,None]*d,axis=2).min(1)
    lengths=np.linalg.norm(np.diff(points,axis=1),axis=2).sum(1)
    bounds=next(v for v in inp['brief']['lengthLimits'] if v['region']==region)
    displacement=np.linalg.norm(points-original,axis=2);maximum=displacement.max(1)
    eligible=np.flatnonzero((minimum>=threshold+1e-6)&(maximum<=.02)&(lengths>=bounds['minimumMeters'])&(lengths<=bounds['maximumMeters']))
    ranked=sorted(eligible,key=lambda j:(float(np.mean(displacement[j]**2)),int(j)))
    decisions=[];selected=None;started=time.monotonic();candidates=[]
    for k in ranked:
        isolated=copy.deepcopy({key:value for key,value in hair.items() if key!='guides'})
        isolated['id']=str(uuid.uuid4());isolated['revision']=1;isolated.pop('edit',None);isolated.pop('parentSHA256',None)
        isolated['generation']['method']='face_clear_regional_latent_probe_v1; base: '+hair['generation']['method']
        isolated['guides']=[copy.deepcopy(base)]
        isolated['guides'][0]['points']=[dict(zip(('x','y','z'),map(float,v))) for v in points[k]]
        candidates.append((k,isolated))
    checks=[]
    if candidates:
        batch_path=args.output/'candidate-batch.json';batch_report=args.output/'candidate-batch-clearance.json'
        write(batch_path,[entry[1] for entry in candidates])
        result=subprocess.run([str(args.inspector.resolve()),'hair-clearance-batch',str(args.input),str(batch_path),str(args.anatomy),str(batch_report)],capture_output=True,text=True,timeout=120)
        if result.returncode not in (0,2):raise RuntimeError(result.stderr+result.stdout)
        checks=json.loads(batch_report.read_text())
        if len(checks)!=len(candidates):raise ValueError('Incomplete batch reports')
    for (k,isolated),check in zip(candidates,checks):
        decisions.append(dict(index=int(k),donorGuideID=ids[choices[k][0]],alpha=choices[k][1],segmentViolations=len(check['violations']),maximumPointChangeMeters=float(maximum[k]),lengthMeters=float(lengths[k])))
        if not check['violations'] and not check['rootViolations']:
            cut=copy.deepcopy(isolated);cut['guides']=copy.deepcopy(hair['guides']);cut['guides'][i]=copy.deepcopy(isolated['guides'][0])
            full=clearance(cut,'selected')
            other=[v for v in baseline['violations'] if v['guideID']!=args.guide_id]
            if full['violations']!=other or full['rootViolations']!=baseline['rootViolations']:raise ValueError('Full replay changed unrelated clearance')
            if any(x!=y for j,(x,y) in enumerate(zip(hair['guides'],cut['guides'])) if j!=i):raise ValueError('Changed unrelated guide')
            selected=int(k)
            save_file({'latent':latents[k:k+1],'template':metal[k:k+1]},str(args.output/'selected-decoder.safetensors'))
            break
    result=dict(method='face_clear_regional_latent_probe_v1',guideID=args.guide_id,rootPreflight=preflight,
        optimizationReportSHA256=sha256(args.optimization/'report.json'),optimizationTensorsSHA256=sha256(args.optimization/'curves.safetensors'),
        sourceHaircutSHA256=baseline['haircutSHA256'],scriptSHA256=sha256(Path(__file__)),
        candidateCount=len(choices),eligibleCandidateCount=len(eligible),testedCandidateCount=len(decisions),selectedIndex=selected,
        cpuMPSDecodedCoordinatesAgree=True,maximumLatentDelta=.25,maximumOriginalPointMovementMeters=.02,
        decisions=decisions,sharedAnatomyBatch=True,clearanceSearchSeconds=time.monotonic()-started,physicalFitVerified=False,promoted=False)
    write(args.output/'report.json',result)
    print(json.dumps({k:v for k,v in result.items() if k!='decisions'},indent=2))


if __name__=='__main__':main()
