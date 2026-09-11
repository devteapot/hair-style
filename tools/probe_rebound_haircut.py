#!/usr/bin/env python3
"""Translate existing research guide curves to a separate root proposal, then validate.

No neural resampling, curve-shape fitting, scalp change or in-place revision edit.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import uuid
import numpy as np
from propose_model_mapping import xyz


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('source','input','base_mapping','mapping','haircut','anatomy','output'):p.add_argument(name,type=Path)
    args=p.parse_args()
    docs={n:json.loads(getattr(args,n).read_text()) for n in ('source','input','base_mapping','mapping','haircut','anatomy')}
    old,m=docs['base_mapping'],docs['mapping'];inp=docs['input'];hair=docs['haircut']
    for k in old:
        if k not in ('id','method','mappings') and old[k]!=m[k]:raise ValueError('Proposal changed mapping limits or source transform')
    source_hash=hashlib.sha256(args.source.read_bytes()).hexdigest()
    if m['sourceArtifactSHA256']!=source_hash:raise ValueError('Source hash mismatch')
    ids=[g['guideID'] for g in m['mappings']]
    if ids!=[g['id'] for g in docs['source']['strands']] or ids!=[g['id'] for g in hair['guides']]:raise ValueError('Guide order mismatch')
    args.output.mkdir(parents=True,exist_ok=False)
    cli=Path(__file__).resolve().parents[1]/'.build/debug/capture-inspect'
    def run(*command):
        result=subprocess.run([str(cli),*map(str,command)],capture_output=True,timeout=120)
        return dict(exitCode=result.returncode,stdout=result.stdout.decode(),stderr=result.stderr.decode())
    def write(name,value):(args.output/name).write_text(json.dumps(value,allow_nan=False,indent=2)+'\n')
    baseline=run('hair-validate',args.input,args.haircut,args.output/'base-validation.json')
    if baseline['exitCode']:raise ValueError('Base canonical haircut failed validation')
    radius=max(material['radiusMeters'] for material in hair['materials'])
    preflight=run('hair-root-preflight',args.input,args.mapping,args.anatomy,radius,args.output/'root-preflight.json')
    if preflight['exitCode']:raise ValueError('Proposed roots did not pass supplied-anatomy preflight')
    vertices=np.array([xyz(v) for v in inp['scalp']['vertices']]);triangles=np.array(inp['scalp']['triangles'])
    proposal=copy.deepcopy(hair);proposal['id']=str(uuid.uuid4());proposal['revision']=1
    proposal.pop('parentSHA256',None);proposal.pop('edit',None)
    inputs={n:hashlib.sha256(getattr(args,n).read_bytes()).hexdigest() for n in docs}
    proposal['generation']['method']='research_surface_rebinding_v1:'+inputs['mapping']+'; derived from '+hair['generation']['method']
    decisions=[]
    for i,(base,target,guide) in enumerate(zip(old['mappings'],m['mappings'],proposal['guides'])):
        if base['guideID']!=target['guideID'] or base['region']!=target['region'] or guide['root']!=base['binding']:raise ValueError('Binding lineage mismatch')
        b=target['binding']
        if b['normalOffsetMeters']!=0:raise ValueError('Requires zero-offset roots')
        root=np.array(b['barycentric'])@vertices[triangles[b['triangleIndex']]]
        source=xyz(m['targetCenterMeters'])+(np.array(docs['source']['strands'][i]['points'][0])-xyz(m['sourceCenter']))*xyz(m['metersPerSourceUnit'])
        if np.linalg.norm(root-source)>m['maximumRootCorrectionMeters']:raise ValueError('Source correction limit exceeded')
        if base==target:continue
        displacement=root-xyz(guide['points'][0])
        if np.linalg.norm(displacement)>.004+1e-8:raise ValueError('Research movement exceeds 4 mm')
        guide['points']=[dict(zip(('x','y','z'),map(float,xyz(point)+displacement))) for point in guide['points']]
        guide['root']=b
        decisions.append(dict(guideID=guide['id'],translationMeters=float(np.linalg.norm(displacement))))
    write('haircut.json',proposal)
    validation=run('hair-validate',args.input,args.output/'haircut.json',args.output/'validation.json')
    clearance=None
    if validation['exitCode']==0:
        clearance=run('hair-clearance',args.input,args.output/'haircut.json',args.anatomy,args.output/'clearance.json')
    report=dict(method='research_surface_rebinding_v1',inputFileSHA256=inputs,
        sourceCanonicalHaircutSHA256=json.loads((args.output/'base-validation.json').read_text())['haircutSHA256'],
        changedGuides=decisions,guideCount=len(ids),validation=validation,clearance=clearance,
        acceptedForPersonalHaircut=False,notes=['Only whole-guide translations at changed roots; relative curve shape retained.',
        'Separate research artifact, not an edit or replacement of the source haircut.',
        'Root clearance alone does not prove whole-curve clearance, scalp/hairline placement or physical fit.'])
    write('report.json',report);print(json.dumps(report,indent=2))


if __name__=='__main__':main()
