#!/usr/bin/env python3
"""Research: optimize one pretrained decoder latent against an inferred personal envelope.

Does not alter decoder weights, write a canonical haircut, or relax the import guard.
"""
import argparse
import copy
import json
import os
from pathlib import Path
import time
import root_preflight


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('texture',type=Path);parser.add_argument('source',type=Path)
    parser.add_argument('input',type=Path);parser.add_argument('mapping',type=Path);parser.add_argument('output',type=Path)
    parser.add_argument('--guide-index',type=int,default=32)
    parser.add_argument('--all-guides',action='store_true')
    parser.add_argument('--length-constraints',action='store_true',help='Include exact regional arc-length bounds in the decoder objective.')
    parser.add_argument('--face-distance-penalty',action='store_true',help='Experimental sampled unsigned surface proximity objective; single-guide probes only.')
    parser.add_argument('--root-departure',action='store_true',help='Add conservative local separating-plane penalties near the fixed root.')
    root_preflight.add_arguments(parser);args=parser.parse_args()
    if args.root_departure and not args.face_distance_penalty:raise ValueError('Root departure requires the single-guide surface-distance probe')
    if args.face_distance_penalty and args.all_guides:
        raise ValueError('Surface distance probes currently require one guide to bound autograd memory')
    if os.environ.get('PYTORCH_ENABLE_MPS_FALLBACK') not in (None,'0'):raise ValueError('Disable CPU fallback')
    preflight=root_preflight.run(args)
    import torch
    from safetensors.torch import load_file, save_file
    from haar_decode_metal import setup
    from haar_text_metal import sha256
    torch.set_num_threads(4)
    inp=json.loads(args.input.read_text());mapping=json.loads(args.mapping.read_text());source=json.loads(args.source.read_text())
    if sha256(args.source)!=mapping['sourceArtifactSHA256']:raise ValueError('Source/mapping mismatch')
    indices=list(range(len(source['strands']))) if args.all_guides else [args.guide_index]
    if any(not 0<=i<len(source['strands']) or source['strands'][i]['id']!=mapping['mappings'][i]['guideID'] for i in indices):raise ValueError('Guide mismatch')
    h=setup(Path('.research/HAAR').resolve(),Path('.research/metal-assets/scalp'),Path('.research/metal-assets/strand_ckpt.pth'),42)
    texture=load_file(str(args.texture))['texture']
    latent0=texture.permute(2,3,0,1)[h.nonzerox,h.nonzeroy].permute(1,0,2).reshape(-1,64)[indices].clone()
    for parameter in h.dec.parameters():parameter.requires_grad_(False)
    def xyz(value):return torch.tensor([value['x'],value['y'],value['z']],dtype=torch.float32)
    vertices=torch.stack([xyz(p) for p in inp['scalp']['vertices']])
    targets=[]
    for i in indices:
        binding=mapping['mappings'][i]['binding']
        targets.append(torch.tensor(binding['barycentric'])@vertices[inp['scalp']['triangles'][binding['triangleIndex']]])
        if binding['normalOffsetMeters']!=0:raise ValueError('Probe requires zero normal-offset attachment')
    target=torch.stack(targets)[:,None]
    envelope=mapping['envelopeGuard']['envelope'];center=xyz(envelope['center']);radii=xyz(envelope['radii'])
    scale=xyz(mapping['metersPerSourceUnit']);threshold=1-mapping['envelopeGuard']['permittedInsetMeters']/float(radii.max())
    rotation=h.small_R_inv[indices];origin=h.small_origins[indices]
    def decode(model,latent):
        device=latent.device;offsets=model(latent)
        local=torch.cat([torch.zeros_like(offsets[:,:1]),offsets.cumsum(1)],dim=1)
        return (rotation.to(device)@local[...,None])[...,0]+origin.to(device)
    with torch.no_grad():initial=decode(h.dec,latent0)
    source_error=float((initial-torch.tensor([source['strands'][i]['points'] for i in indices])).abs().max())
    if source_error>2e-5:raise ValueError('Latent does not reproduce the selected source guide')
    initial_mapped=(initial-initial[:,:1])*scale+target
    surface_triangles=None
    if args.face_distance_penalty:
        from face_distance import point_surface_distance_squared
        anatomy=json.loads(args.anatomy.read_text())
        triangles=[]
        for surface in anatomy['surfaces']:
            verts=torch.stack([xyz(p) for p in surface['vertices']])
            triangles.append(verts[torch.tensor(surface['triangles'],dtype=torch.long)])
        if not triangles:raise ValueError('Surface distance requires supplied anatomy')
        surface_triangles=torch.cat(triangles)
        surface_margin=float(anatomy['clearanceMeters'])+args.material_radius_meters+0.001
    if args.root_departure:
        from root_departure import departure_planes
        planes=departure_planes(target[0,0].numpy(),surface_triangles.numpy(),float(anatomy['clearanceMeters'])+args.material_radius_meters)
        origins=torch.tensor(planes['origins'],dtype=torch.float32);normals=torch.tensor(planes['normals'],dtype=torch.float32)
        margins=torch.tensor(planes['margins'],dtype=torch.float32)
        initial_arc=torch.cat([torch.zeros(1),torch.linalg.vector_norm(initial_mapped[0,1:]-initial_mapped[0,:-1],dim=1).cumsum(0)])
        departure_indices=torch.nonzero(initial_arc<=.012).flatten()
        def departure_violation(points):
            near=points[0,departure_indices.to(points.device)]
            signed=((near[:,None]-origins.to(points.device))*normals.to(points.device)).sum(2)
            return torch.relu(margins.to(points.device)-signed)
        initial_departure=departure_violation(initial_mapped)
    def proximity(points):
        samples=torch.cat([points,(points[:,1:]+points[:,:-1])/2],dim=1)
        squared=point_surface_distance_squared(samples.reshape(-1,3),surface_triangles.to(points.device))
        return squared.clamp_min(1e-16).sqrt().reshape(len(points),-1)
    limits={limit['region']:limit for limit in inp['brief']['lengthLimits']}
    lower=torch.tensor([limits[mapping['mappings'][i]['region']]['minimumMeters'] for i in indices])
    upper=torch.tensor([limits[mapping['mappings'][i]['region']]['maximumMeters'] for i in indices])
    def lengths(points):return torch.linalg.vector_norm(points[:,1:]-points[:,:-1],dim=2).sum(dim=1)
    def length_error(points):
        measured=lengths(points)
        return torch.relu(lower.to(points.device)-measured)+torch.relu(measured-upper.to(points.device))
    def evaluate(model,latent):
        device=latent.device;curve=decode(model,latent)
        mapped=(curve-curve[:,:1])*scale.to(device)+target.to(device)
        q=(mapped-center.to(device))/radii.to(device);a=q[:,:-1];d=q[:,1:]-a
        t=(-torch.sum(a*d,dim=2)/torch.sum(d*d,dim=2).clamp_min(1e-16)).clamp(0,1)
        distance=torch.linalg.vector_norm(a+t[:,:,None]*d,dim=2)
        penetration=torch.relu(threshold+0.0005-distance)
        preservation=torch.mean(((mapped-initial_mapped.to(device))/radii.to(device))**2)
        latent_change=torch.mean((latent-latent0.to(device))**2)
        loss=1000*(torch.mean(penetration**2)+torch.max(penetration**2,dim=1).values.mean())+preservation+0.01*latent_change
        if args.length_constraints:
            loss=loss+1000*torch.mean((length_error(mapped)/0.1)**2)
        if args.face_distance_penalty:
            violations=torch.relu(surface_margin-proximity(mapped))/0.01
            loss=loss+10*(violations.square().mean()+violations.square().max())
        if args.root_departure:
            departure=departure_violation(mapped)/.01
            loss=loss+100*(departure.square().mean()+departure.square().max())
        return loss,distance,mapped,curve
    cpu_latent=latent0.clone().requires_grad_(True);cpu_loss=evaluate(h.dec,cpu_latent)[0];cpu_loss.backward()
    model=copy.deepcopy(h.dec).to('mps');latent=latent0.to('mps').detach().requires_grad_(True)
    metal_loss=evaluate(model,latent)[0];metal_loss.backward()
    gradient_error=float((latent.grad.cpu()-cpu_latent.grad).abs().max())
    gradient_agreement=bool(torch.allclose(latent.grad.cpu(),cpu_latent.grad,atol=1e-4,rtol=1e-3))
    if not gradient_agreement or not bool(torch.isfinite(latent.grad).all()):raise ValueError('CPU/MPS gradient comparison failed')
    with torch.no_grad():
        original_distances=evaluate(model,latent)[1]
        initially_envelope_bad=(original_distances.min(dim=1).values<threshold)
        initial_length_error=length_error(initial_mapped)
        active=initially_envelope_bad | ((initial_length_error.to('mps')>1e-7) if args.length_constraints else False)
        if args.face_distance_penalty:
            initial_proximity=proximity(initial_mapped.to('mps'))
            active=active | (initial_proximity.min(dim=1).values<surface_margin)
    latent.grad=None;optimizer=torch.optim.Adam([latent],lr=0.005);trace=[];started=time.monotonic()
    for step in range(200):
        optimizer.zero_grad();loss,distances,mapped,curve=evaluate(model,latent)
        if not bool(torch.isfinite(loss)):raise ValueError('Nonfinite optimization')
        loss.backward();optimizer.step()
        # Fixed latent trust region; this is a new decoded curve, not a post-hoc point projection.
        with torch.no_grad():latent.copy_(torch.where(active[:,None],latent0.to('mps')+(latent-latent0.to('mps')).clamp(-0.25,0.25),latent0.to('mps')))
        if step%10==0:trace.append(dict(step=step,loss=float(loss.detach()),minimumNormalizedRadius=float(distances.min().detach())))
    with torch.no_grad():loss,distances,mapped,curve=evaluate(model,latent)
    save_file({'originalTemplate':initial,'optimizedTemplate':curve.cpu(),'originalMapped':initial_mapped,
               'optimizedMapped':mapped.cpu(),'originalLatent':latent0,'optimizedLatent':latent.detach().cpu()},str(args.output/'curves.safetensors'))
    report=dict(method='personal_inferred_envelope_decoder_latent_probe_v3',rootPreflight=preflight,guideIDs=[source['strands'][i]['id'] for i in indices],
        guideCount=len(indices),initiallyViolatingGuides=int(initially_envelope_bad.sum()),finallyViolatingGuides=int((distances.min(dim=1).values<threshold).sum()),
        initiallyValidLatentsUnchanged=bool(torch.equal(latent.detach()[~active].cpu(),latent0[~active.cpu()])),
        scriptSHA256=sha256(Path(__file__)),penalty='mean_plus_max_segment_penetration_squared',cpuFallbackEnabled=False,
        sourceSHA256=sha256(args.source),textureSHA256=sha256(args.texture),inputSHA256=sha256(args.input),mappingSHA256=sha256(args.mapping),
        decoderSHA256=sha256(Path('.research/metal-assets/strand_ckpt.pth')),sourceReplayMaximumError=source_error,
        cpuMPSGradientMaximumDifference=gradient_error,cpuMPSGradientAgreement=gradient_agreement,
        lengthConstraintsEnabled=args.length_constraints,activeGuideCount=int(active.sum()),
        initiallyLengthViolatingGuides=int((initial_length_error>1e-7).sum()),
        finallyLengthViolatingGuides=int((length_error(mapped)>1e-7).sum()),
        maximumLengthViolationMeters=float(length_error(mapped).max()),
        initialLengthsMeters=lengths(initial_mapped).tolist(),finalLengthsMeters=lengths(mapped).cpu().tolist(),
        regionalBounds=[dict(guideID=source['strands'][i]['id'],minimumMeters=float(lower[j]),maximumMeters=float(upper[j])) for j,i in enumerate(indices)],
        iterations=200,optimizerSeconds=time.monotonic()-started,trace=trace,minimumNormalizedRadius=float(distances.min()),
        requiredMinimumNormalizedRadius=threshold,analyticEnvelopePassed=bool((distances>=threshold-1e-7).all()),
        maximumPointChangeMeters=float(torch.linalg.vector_norm(mapped.cpu()-initial_mapped,dim=2).max()),
        rootChangeMeters=float(torch.linalg.vector_norm(mapped[:,:1].cpu()-target,dim=2).max()),
        personalGeometryConditioningApplied=True,pretrainedWeightsChanged=False,canonicalHaircutPublished=False,
        personalStyleVerified=False,templateSurfaceRechecked=False,
        notes=['Independent per-guide latent constraints; length feasibility, whole-style coherence and template-surface checks remain.',
               'Constraint uses an inferred personal envelope, not validated skull or measured growth direction.',
               'The existing 2 mm import correction limit is unchanged; no modified source is passed off as original HAAR output.'])
    report['surfaceDistancePenaltyEnabled']=args.face_distance_penalty
    report['rootDepartureEnabled']=args.root_departure
    if args.root_departure:
        report['rootDepartureProbe']=dict(planeCount=len(origins),sampleCount=len(departure_indices),
            initialArcWindowMeters=.012,initialMaximumViolationMeters=float(initial_departure.max()),
            finalMaximumViolationMeters=float(departure_violation(mapped).max()),
            helperSHA256=sha256(Path(__file__).with_name('root_departure.py')),
            anatomicalInsideOutsideVerified=False)
    if args.face_distance_penalty:
        with torch.no_grad():final_proximity=proximity(mapped)
        report['surfaceDistanceProbe']=dict(
            anatomySHA256=sha256(args.anatomy),helperSHA256=sha256(Path(__file__).with_name('face_distance.py')),
            sampledMarginMeters=surface_margin,triangleCount=len(surface_triangles),
            initialMinimumSampleDistanceMeters=float(initial_proximity.min()),
            finalMinimumSampleDistanceMeters=float(final_proximity.min()),
            samplesBelowMargin=int((final_proximity<surface_margin).sum()),
            includesVerticesAndMidpoints=True,provesSegmentClearance=False,provesOutsideSurface=False)
    (args.output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ('trace','guideIDs')},indent=2))


if __name__=='__main__':main()
