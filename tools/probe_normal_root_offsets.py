#!/usr/bin/env python3
"""Diagnose inferred scalp/face mismatch with bounded normal-offset attachments.

Offsets remain inferred, not measured roots or a validated scalp correction.
Exact full-surface clearance and unchanged source/movement limits are required.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import uuid
import numpy as np
from root_departure import departure_planes


def offset_curve(points, triangle, binding, additional_offset):
    points=np.asarray(points,dtype=float);triangle=np.asarray(triangle,dtype=float)
    weights=np.asarray(binding['barycentric'],dtype=float);previous=binding['normalOffsetMeters']
    if (points.ndim!=2 or points.shape[1]!=3 or len(points)<2 or triangle.shape!=(3,3)
            or weights.shape!=(3,) or not np.isfinite(points).all() or not np.isfinite(triangle).all()
            or not np.isfinite(weights).all() or np.any(weights<0) or np.any(weights>1)
            or abs(weights.sum()-1)>1e-8 or not np.isfinite([previous,additional_offset]).all()
            or not 0<=previous<=.01 or not 0<additional_offset<=.004 or previous+additional_offset>.01):
        raise ValueError('Invalid bounded normal-offset input')
    normal=np.cross(triangle[1]-triangle[0],triangle[2]-triangle[0]);norm=np.linalg.norm(normal)
    if norm<=1e-10:raise ValueError('Degenerate attachment triangle')
    normal/=norm;surface_root=weights@triangle
    if np.linalg.norm(points[0]-surface_root-previous*normal)>1e-8:raise ValueError('Curve root does not match binding')
    updated=copy.deepcopy(binding);updated['normalOffsetMeters']=previous+additional_offset
    root=surface_root+updated['normalOffsetMeters']*normal
    result=points+(root-points[0]);result[0]=root
    return result,updated,normal


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    names=('input','mapping','source','haircut','anatomy')
    for name in (*names,'output'):parser.add_argument(name,type=Path)
    args=parser.parse_args();inp,mapping,source,hair,anatomy=[json.loads(getattr(args,n).read_text()) for n in names]
    if hashlib.sha256(args.source.read_bytes()).hexdigest()!=mapping['sourceArtifactSHA256']:raise ValueError('Source hash mismatch')
    ids=[g['id'] for g in hair['guides']]
    if ids!=[s['id'] for s in source['strands']] or ids!=[m['guideID'] for m in mapping['mappings']]:raise ValueError('Guide identity mismatch')
    args.output.mkdir(parents=True,exist_ok=False)
    cli=Path(__file__).resolve().parents[1]/'.build/debug/capture-inspect'
    def write(name,value):(args.output/name).write_text(json.dumps(value,indent=2,allow_nan=False)+'\n')
    def check(command,cut_path,output):
        result=subprocess.run([str(cli),command,str(args.input),str(cut_path),str(args.anatomy),str(args.output/output)],capture_output=True,text=True,timeout=120)
        if result.returncode not in (0,2):raise RuntimeError(result.stdout+result.stderr)
        return json.loads((args.output/output).read_text())
    baseline=check('hair-clearance',args.haircut,'baseline.json')
    if baseline['rootViolations']:raise ValueError('This experiment expects clear roots with conflicting curves')
    targets=sorted({v['guideID'] for v in baseline['violations']})
    if not 1<=len(targets)<=16:raise ValueError('Expected one to sixteen conflicting guides')
    xyz=lambda ps:np.array([[p[k] for k in ('x','y','z')] for p in ps])
    scalp=xyz(inp['scalp']['vertices'])[inp['scalp']['triangles']]
    face=np.concatenate([xyz(s['vertices'])[s['triangles']] for s in anatomy['surfaces']])
    env=mapping['envelopeGuard']['envelope'];center=xyz([env['center']])[0];radii=xyz([env['radii']])[0]
    threshold=1-mapping['envelopeGuard']['permittedInsetMeters']/max(radii)
    roots=np.array([xyz(g['points'])[0] for g in hair['guides']]);candidates=[];decisions=[];diagnostics=[]
    for identity in targets:
        i=ids.index(identity);guide=hair['guides'][i];points=xyz(guide['points']);root=points[0]
        material=next(m for m in hair['materials'] if m['id']==guide['materialID'])
        planes=departure_planes(root,face,material['radiusMeters']+anatomy['clearanceMeters'])
        distances=np.linalg.norm(planes['origins']-root,axis=1);j=int(distances.argmin())
        outward=(root-center)/(radii*radii);outward/=np.linalg.norm(outward)
        diagnostics.append(dict(guideID=identity,nearestSurfaceDistanceMeters=float(distances[j]),
            inferredOutwardDotRootSide=float(outward@planes['normals'][j])))
        raw=np.array(source['strands'][i]['points']);bind=mapping['mappings'][i]['binding']
        tri=scalp[bind['triangleIndex']];n=np.cross(tri[1]-tri[0],tri[2]-tri[0]);n/=np.linalg.norm(n)
        original_root=np.array(bind['barycentric'])@tri+n*bind['normalOffsetMeters']
        original=(raw-raw[0])*xyz([mapping['metersPerSourceUnit']])[0]+original_root
        transformed_root=xyz([mapping['targetCenterMeters']])[0]+(raw[0]-xyz([mapping['sourceCenter']])[0])*xyz([mapping['metersPerSourceUnit']])[0]
        for offset in np.arange(1,17)*.00025:
            after,binding,normal=offset_curve(points,scalp[guide['root']['triangleIndex']],guide['root'],float(offset))
            if normal@outward<=0:raise ValueError('Scalp binding normal disagrees with inferred outward direction')
            movement=float(np.linalg.norm(after-original,axis=1).max())
            correction=float(np.linalg.norm(after[0]-transformed_root))
            neighbor=float(np.linalg.norm(np.delete(roots,i,axis=0)-after[0],axis=1).min())
            old_neighbor=float(np.linalg.norm(np.delete(roots,i,axis=0)-root,axis=1).min())
            q=(after-center)/radii;a=q[:-1];d=np.diff(q,axis=0);t=np.clip(-(a*d).sum(1)/(d*d).sum(1).clip(1e-20),0,1)
            envelope=bool(np.linalg.norm(a+t[:,None]*d,axis=1).min()>=threshold)
            eligible=movement<=.02 and correction<=mapping['maximumRootCorrectionMeters'] and neighbor>=min(old_neighbor,.0001) and envelope
            row=dict(guideID=identity,additionalNormalOffsetMeters=float(offset),maximumCumulativeMovementMeters=movement,
                sourceRootCorrectionMeters=correction,envelopePassed=envelope,eligible=bool(eligible))
            if eligible:
                cut=copy.deepcopy({k:v for k,v in hair.items() if k!='guides'});cut['id']=str(uuid.uuid4());cut['revision']=1
                cut.pop('parentSHA256',None);cut.pop('edit',None);cut['generation']['method']='inferred_normal_root_offset_research_v1'
                g=copy.deepcopy(guide);g['root']=binding;g['points']=[dict(zip(('x','y','z'),map(float,p))) for p in after];cut['guides']=[g]
                row['candidateIndex']=len(candidates);candidates.append(cut)
            decisions.append(row)
    selected={}
    if candidates:
        write('candidates.json',candidates)
        checks=check('hair-clearance-batch',args.output/'candidates.json','candidate-clearance.json')
        if len(checks)!=len(candidates):raise ValueError('Clearance result count mismatch')
        for d in decisions:
            if 'candidateIndex' not in d:continue
            r=checks[d['candidateIndex']];d.update(segmentConflicts=len(r['violations']),rootConflicts=len(r['rootViolations']))
            if r['surfaceChecksPassed'] and d['guideID'] not in selected:selected[d['guideID']]=d['candidateIndex']
    combined=None
    if len(selected)==len(targets):
        cut=copy.deepcopy(hair);cut['id']=str(uuid.uuid4());cut['revision']=1;cut.pop('edit',None);cut.pop('parentSHA256',None)
        cut['generation']['method']='inferred_normal_root_offset_research_v1'
        cut['guides']=[candidates[selected[g['id']]]['guides'][0] if g['id'] in selected else g for g in hair['guides']]
        final_roots=np.array([xyz(g['points'])[0] for g in cut['guides']])
        for i in range(len(roots)):
            previous=float(np.linalg.norm(np.delete(roots,i,axis=0)-roots[i],axis=1).min())
            current=float(np.linalg.norm(np.delete(final_roots,i,axis=0)-final_roots[i],axis=1).min())
            if current<min(previous,.0001)-1e-12:raise ValueError('Combined offsets introduce a closer root near-coincidence')
        write('research-haircut.json',cut);combined=check('hair-clearance',args.output/'research-haircut.json','combined-clearance.json')
    write('report.json',dict(method='inferred_normal_root_offset_research_v1',inputHashes={n:hashlib.sha256(getattr(args,n).read_bytes()).hexdigest() for n in names},
        diagnostics=diagnostics,decisions=decisions,selected=selected,combinedSurfaceChecksPassed=combined and combined['surfaceChecksPassed'],
        measuredRootPositions=False,acceptedForPersonalHaircut=False,promoted=False))
    print(json.dumps(dict(testedCandidates=len(candidates),guidesWithClearCandidate=len(selected),combinedSurfaceChecksPassed=combined and combined['surfaceChecksPassed'])))


if __name__=='__main__':main()
