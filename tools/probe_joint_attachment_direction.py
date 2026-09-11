#!/usr/bin/env python3
"""Joint bounded attachment/rigid-direction probe for one remaining conflicting guide.

No anatomy/scalp changes, no curve reshaping, and no automatic physical acceptance.
"""
import argparse
import copy
import hashlib
import itertools
import json
from pathlib import Path
import subprocess
import time
import uuid
import numpy as np
from propose_model_mapping import xyz, nearest_triangle


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('source','input','base_mapping','haircut','anatomy','output'):parser.add_argument(name,type=Path)
    parser.add_argument('--guide-id', help='Explicitly target one conflicting guide while retaining all others.')
    args=parser.parse_args();names=('source','input','base_mapping','haircut','anatomy')
    source,inp,mapping,hair,anatomy=[json.loads(getattr(args,n).read_text()) for n in names]
    if hashlib.sha256(args.source.read_bytes()).hexdigest()!=mapping['sourceArtifactSHA256']:raise ValueError('Source mismatch')
    if [g['id'] for g in hair['guides']] != [g['guideID'] for g in mapping['mappings']]:raise ValueError('Mapping order mismatch')
    if [g['id'] for g in source['strands']] != [g['id'] for g in hair['guides']]:raise ValueError('Source order mismatch')
    args.output.mkdir(parents=True,exist_ok=False)
    cli=Path(__file__).resolve().parents[1]/'.build/debug/capture-inspect'
    def write(path,value):path.write_text(json.dumps(value,indent=2,allow_nan=False)+'\n')
    def run(*command):
        result=subprocess.run([str(cli),*map(str,command)],capture_output=True,timeout=120)
        return dict(exitCode=result.returncode,stdout=result.stdout.decode(),stderr=result.stderr.decode())
    baseline=run('hair-clearance',args.input,args.haircut,args.anatomy,args.output/'baseline.json')
    if baseline['exitCode']!=2:raise ValueError('Expected a canonical source with curve conflicts')
    check=json.loads((args.output/'baseline.json').read_text());conflicts={v['guideID'] for v in check['violations']}
    if check['rootViolations']:raise ValueError('Resolve root conflicts before joint curve search')
    if args.guide_id is None and len(conflicts)!=1:
        raise ValueError('Multiple conflicting guides require an explicit --guide-id')
    identity=args.guide_id or next(iter(conflicts))
    if identity not in conflicts:raise ValueError('Selected guide is not a baseline curve conflict')
    i=next(j for j,g in enumerate(hair['guides']) if g['id']==identity)
    guide=hair['guides'][i];binding=mapping['mappings'][i]['binding']
    if binding['normalOffsetMeters']!=0:raise ValueError('Requires surface-bound original root')
    triangles=np.array([xyz(p) for p in inp['scalp']['vertices']])[np.array(inp['scalp']['triangles'])]
    base_root=np.array(binding['barycentric'])@triangles[binding['triangleIndex']]
    source_root=xyz(mapping['targetCenterMeters'])+(np.array(source['strands'][i]['points'][0])-xyz(mapping['sourceCenter']))*xyz(mapping['metersPerSourceUnit'])
    points=np.array([xyz(p) for p in guide['points']])
    material=next(m for m in hair['materials'] if m['id']==guide['materialID'])
    required=material['radiusMeters']+anatomy['clearanceMeters']
    faces=[np.array([xyz(p) for p in f['vertices']])[np.array(f['triangles'])] for f in anatomy['surfaces']]
    directions=np.array([p for p in itertools.product((-1,0,1),repeat=3) if p!=(0,0,0)],dtype=float)
    directions/=np.linalg.norm(directions,axis=1)[:,None]
    indices=np.arange(256);y=1-2*(indices+.5)/256;angle=indices*np.pi*(3-np.sqrt(5));r=np.sqrt(1-y*y)
    directions=np.r_[directions,np.c_[r*np.cos(angle),y,r*np.sin(angle)]]
    candidates=[]
    for radius in np.arange(1,9)*.0005:
        for direction in directions:
            triangle,weights,_=nearest_triangle(base_root+radius*direction,triangles);root=weights@triangles[triangle]
            movement=float(np.linalg.norm(root-base_root));correction=float(np.linalg.norm(root-source_root))
            if movement>.004+1e-12 or correction>mapping['maximumRootCorrectionMeters']:continue
            distance=min(nearest_triangle(root,face)[2] for face in faces)
            if distance<=required+.00001:continue
            candidates.append(dict(root=root,binding=dict(triangleIndex=triangle,barycentric=weights.tolist(),normalOffsetMeters=0),movement=movement,correction=correction))
    if not candidates:raise ValueError('No feasible root samples')
    # Small deterministic spatially diverse shortlist, rather than repeated nearly
    # identical roots. Start nearest the original; then maximize spatial coverage.
    chosen=[min(candidates,key=lambda c:c['movement'])]
    while len(chosen)<16:
        scores=[min(np.linalg.norm(c['root']-x['root']) for x in chosen) for c in candidates]
        index=int(np.argmax(scores))
        if scores[index]<.00025:break
        chosen.append(candidates[index])
    decisions=[];selected=None;started=time.monotonic()
    for index,candidate in enumerate(chosen):
        directory=args.output/f'{index:02d}';directory.mkdir()
        cut=copy.deepcopy(hair);cut['id']=str(uuid.uuid4());cut['revision']=1;cut.pop('parentSHA256',None);cut.pop('edit',None)
        translated=points+(candidate['root']-points[0])
        cut['guides'][i]['points']=[dict(zip(('x','y','z'),map(float,p))) for p in translated]
        cut['guides'][i]['root']=candidate['binding']
        cut['generation']['method']='joint_attachment_direction_probe_v1:'+check['haircutSHA256']+'; source: '+hair['generation']['method']
        write(directory/'translated.json',cut)
        isolated=copy.deepcopy(cut);isolated['guides']=[cut['guides'][i]]
        write(directory/'isolated.json',isolated)
        result=run('hair-rotate-proposal',args.input,directory/'isolated.json',args.anatomy,directory/'proposal.json','--diagonal-axes')
        decision=dict(index=index,rootMovementMeters=candidate['movement'],sourceCorrectionMeters=candidate['correction'],rotationRun=result)
        if result['exitCode'] in (0,2):
            proposed=json.loads((directory/'proposal.json').read_text())
            if len(proposed['haircut']['guides'])!=1 or proposed['haircut']['guides'][0]['id']!=identity:
                raise ValueError('Isolated proposal changed guide identity')
            new=copy.deepcopy(cut);new['guides'][i]=proposed['haircut']['guides'][0]
            movement=float(np.linalg.norm(np.array([xyz(p) for p in new['guides'][i]['points']])-points,axis=1).max())
            decision.update(remainingSegmentViolations=len(proposed['clearance']['violations']),totalPointMovementMeters=movement)
            if proposed['clearance']['surfaceChecksPassed'] and movement<=.02:
                for j in range(len(hair['guides'])):
                    if j!=i and hair['guides'][j]!=new['guides'][j]:raise ValueError('Unrelated guide changed')
                write(directory/'merged.json',new)
                full=run('hair-clearance',args.input,directory/'merged.json',args.anatomy,directory/'merged-clearance.json')
                if full['exitCode'] not in (0,2):raise ValueError('Merged canonical clearance failed to execute')
                merged=json.loads((directory/'merged-clearance.json').read_text())
                if merged['rootViolations'] or identity in {v['guideID'] for v in merged['violations']}:
                    raise ValueError('Selected guide failed full-haircut replay')
                old_other=[v for v in check['violations'] if v['guideID']!=identity]
                if merged['violations']!=old_other or merged['missingRegions']!=check['missingRegions']:
                    raise ValueError('Unrelated anatomy results changed during isolated proposal')
                decision['fullRemainingSegmentViolations']=len(merged['violations'])
                selected=index;write(args.output/'haircut.json',new);write(args.output/'clearance.json',merged)
                final_mapping=copy.deepcopy(mapping);final_mapping['id']=str(uuid.uuid4())
                for b,g in zip(final_mapping['mappings'],new['guides']):b['binding']=g['root']
                final_mapping['method']+=' Joint attachment/direction research proposal; full anatomical and styling validation remain.'
                write(args.output/'mapping.json',final_mapping)
        decisions.append(decision)
        print(json.dumps({k:v for k,v in decision.items() if k!='rotationRun'}),flush=True)
        if selected is not None:break
    report=dict(method='joint_attachment_direction_probe_v1',guideID=identity,
        inputFileSHA256={n:hashlib.sha256(getattr(args,n).read_bytes()).hexdigest() for n in names},
        feasibleRootSamples=len(candidates),shortlistedRoots=len(chosen),selectedProposalIndex=selected,
        maximumRootMovementMeters=.004,maximumTotalPointMovementMeters=.02,decisions=decisions,
        seconds=time.monotonic()-started,acceptedForPersonalHaircut=False,
        notes=['Scalp and anatomy are unchanged; only one guide may translate and rigidly rotate.',
               'No change to source-correction, canonical envelope or supplied-anatomy thresholds.',
               'Missing ears, root order/flow, interpolation, physical fit and style suitability remain unverified.'])
    write(args.output/'report.json',report)
    print(json.dumps(dict(selectedProposalIndex=selected,seconds=report['seconds'])),flush=True)


if __name__=='__main__':main()
