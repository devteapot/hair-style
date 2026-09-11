#!/usr/bin/env python3
"""Bounded regional latent interpolation for unresolved personal-envelope violations.

Research only: source latents come from the same actual generated hairstyle.
"""
import argparse
import json
import os
from pathlib import Path
import time
import root_preflight


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('optimization',type=Path)
    p.add_argument('input',type=Path);p.add_argument('mapping',type=Path);p.add_argument('output',type=Path)
    p.add_argument('--length-constraints',action='store_true')
    root_preflight.add_arguments(p);args=p.parse_args()
    if os.environ.get('PYTORCH_ENABLE_MPS_FALLBACK') not in (None,'0'):raise ValueError('Disable CPU fallback')
    preflight=root_preflight.run(args)
    import numpy as np
    import torch
    from safetensors.torch import load_file, save_file
    from haar_decode_metal import setup
    from haar_text_metal import sha256
    report=json.loads((args.optimization/'report.json').read_text())
    if report['inputSHA256']!=sha256(args.input) or report['mappingSHA256']!=sha256(args.mapping):raise ValueError('Input provenance mismatch')
    inp=json.loads(args.input.read_text());mapping=json.loads(args.mapping.read_text())
    data=load_file(str(args.optimization/'curves.safetensors'))
    count=len(mapping['mappings'])
    if data['originalLatent'].shape!=(count,64) or report['guideCount']!=count:raise ValueError('Requires full-field optimization')
    torch.set_num_threads(4)
    h=setup(Path('.research/HAAR').resolve(),Path('.research/metal-assets/scalp'),Path('.research/metal-assets/strand_ckpt.pth'),42)
    h.dec.to('mps');xyz=lambda v:np.array([v['x'],v['y'],v['z']],dtype=float)
    envelope=mapping['envelopeGuard']['envelope'];center=xyz(envelope['center']);radii=xyz(envelope['radii'])
    threshold=1-mapping['envelopeGuard']['permittedInsetMeters']/max(radii)
    def minima(points):
        q=(points-center)/radii;a=q[:,:-1];d=np.diff(q,axis=1)
        t=np.clip(-np.sum(a*d,axis=2)/np.sum(d*d,axis=2).clip(1e-20),0,1)
        return np.linalg.norm(a+t[:,:,None]*d,axis=2).min(axis=1)
    before=data['optimizedMapped'].numpy().astype(float);original=data['originalMapped'].numpy().astype(float)
    limits={v['region']:v for v in inp['brief']['lengthLimits']}
    lower=np.array([limits[v['region']]['minimumMeters'] for v in mapping['mappings']])
    upper=np.array([limits[v['region']]['maximumMeters'] for v in mapping['mappings']])
    def lengths(points):return np.linalg.norm(np.diff(points,axis=1),axis=2).sum(axis=1)
    def length_valid(points):return (lengths(points)>=lower)&(lengths(points)<=upper)
    if args.length_constraints != bool(report.get('lengthConstraintsEnabled',False)):
        raise ValueError('Regional search must retain the optimization length-constraint mode')
    valid_original=(minima(original)>=threshold)&(length_valid(original) if args.length_constraints else True)
    valid_before=(minima(before)>=threshold)&(length_valid(before) if args.length_constraints else True)
    unresolved=np.flatnonzero(~valid_before)
    output_latent=data['optimizedLatent'].clone();output_template=data['optimizedTemplate'].clone();output_mapped=data['optimizedMapped'].clone()
    original_latent=data['originalLatent'];regions=[m['region'] for m in mapping['mappings']]
    scale=torch.tensor(xyz(mapping['metersPerSourceUnit']),dtype=torch.float32,device='mps')
    decisions=[];started=time.monotonic()
    for i in unresolved:
        donors=[j for j in range(count) if valid_original[j] and regions[j]==regions[i] and j!=i]
        donors=sorted(donors,key=lambda j:float(torch.sum((original_latent[j]-original_latent[i])**2)))[:32]
        combinations=[(j,alpha) for j in donors for alpha in (0.25,0.5,0.75,1.0)]
        if not combinations:
            decisions.append(dict(guideID=mapping['mappings'][i]['guideID'],accepted=False,candidates=0));continue
        latents=torch.stack([(1-alpha)*data['optimizedLatent'][i]+alpha*original_latent[j] for j,alpha in combinations])
        with torch.inference_mode():
            offsets=h.dec(latents.to('mps'));local=torch.cat([torch.zeros_like(offsets[:,:1]),offsets.cumsum(1)],dim=1)
            curves=(h.small_R_inv[i].to('mps')@local[...,None])[...,0]+h.small_origins[i].to('mps')
            mapped=(curves-curves[:,:1])*scale+torch.tensor(before[i,:1],dtype=torch.float32,device='mps')
        curves=curves.cpu();mapped=mapped.cpu();points=mapped.numpy().astype(float)
        minimum=minima(points);displacement=np.linalg.norm(points-original[i],axis=2)
        maximum=displacement.max(axis=1);rms=np.sqrt((displacement**2).mean(axis=1))
        # Research candidate-distortion limit, independent of the unchanged import correction budget.
        in_range=(lengths(points)>=lower[i])&(lengths(points)<=upper[i])
        eligible=np.flatnonzero((minimum>=threshold+1e-6)&(maximum<=0.02)&(in_range if args.length_constraints else True))
        if len(eligible):
            choice=min(eligible,key=lambda j:(float(rms[j]),int(j)));donor,alpha=combinations[choice]
            output_latent[i]=latents[choice];output_template[i]=curves[choice];output_mapped[i]=mapped[choice]
            decisions.append(dict(guideID=mapping['mappings'][i]['guideID'],accepted=True,candidates=len(combinations),
                donorGuideID=mapping['mappings'][donor]['guideID'],alpha=alpha,minimumNormalizedRadius=float(minimum[choice]),
                maximumPointChangeMeters=float(maximum[choice]),rmsPointChangeMeters=float(rms[choice])))
        else:decisions.append(dict(guideID=mapping['mappings'][i]['guideID'],accepted=False,candidates=len(combinations),
            bestMinimumNormalizedRadius=float(minimum.max()),envelopePassingCandidates=int(np.sum(minimum>=threshold+1e-6))))
    final_minimum=minima(output_mapped.numpy().astype(float))
    save_file({'originalLatent':original_latent,'optimizedLatent':output_latent,'originalTemplate':data['originalTemplate'],
        'optimizedTemplate':output_template,'originalMapped':data['originalMapped'],'optimizedMapped':output_mapped},str(args.output/'curves.safetensors'))
    output=dict(method='regional_latent_interpolation_probe_v1',rootPreflight=preflight,scriptSHA256=sha256(Path(__file__)),
        inputSHA256=sha256(args.input),mappingSHA256=sha256(args.mapping),sourceOptimizationSHA256=sha256(args.optimization/'curves.safetensors'),
        guideCount=count,initialUnresolved=len(unresolved),finalUnresolved=int(np.sum((final_minimum<threshold)|(~length_valid(output_mapped.numpy().astype(float)) if args.length_constraints else False))),
        lengthConstraintsEnabled=args.length_constraints,finallyLengthViolatingGuides=int(np.sum(~length_valid(output_mapped.numpy().astype(float)))),
        seconds=time.monotonic()-started,maximumCandidatePointChangeMeters=0.02,neighborsPerGuide=32,
        interpolationFractions=[0.25,0.5,0.75,1.0],decisions=decisions,
        initiallyValidOptimizedLatentsUnchanged=bool(torch.equal(output_latent[valid_before],data['optimizedLatent'][valid_before])),
        rootsExactlyUnchanged=bool(torch.equal(output_mapped[:,0],data['optimizedMapped'][:,0])),
        personalStyleVerified=False,canonicalHaircutPublished=False,
        notes=['Candidate acceptance means this inferred-envelope and research distortion check only.',
               'Same-region labels are provisional. Donor latent interpolation may change curl and styling intent.',
               'Full canonical length/clearance validation, template check and visual assessment remain.'])
    (args.output/'report.json').write_text(json.dumps(output,indent=2)+'\n');print(json.dumps(output,indent=2))


if __name__=='__main__':main()
