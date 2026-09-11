#!/usr/bin/env python3
"""Independent checks of an actual mapped model run and its saved edits."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from propose_model_mapping import nearest_triangle, xyz


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run',type=Path)
    parser.add_argument('source',type=Path)
    parser.add_argument('scalp_result',type=Path)
    args=parser.parse_args()
    load=lambda name:json.loads((args.run/name).read_text())
    source=json.loads(args.source.read_text());completion=json.loads(args.scalp_result.read_text())
    imported=load('imported.json');request=load('mapping.json');input=load('input.json')
    original=imported['haircut'];fringe=load('fringe-result.json');crown=load('crown-result.json')
    assert request['sourceArtifactSHA256']==hashlib.sha256(args.source.read_bytes()).hexdigest()
    assert input['scalp']['vertices']==completion['scalp']['vertices']
    assert input['scalp']['triangles']==completion['scalp']['triangles']
    assert input['scalp']['triangleOrigins']==completion['scalp']['triangleOrigins']
    assert all(r['origin']=='unknown' and r['quality']=='unknown' for r in input['hairProfile']['regions'])
    assert not imported['acceptedForPersonalHaircut'] and not imported['personalizationBeyondFittingVerified']
    vertices=np.array([xyz(v) for v in input['scalp']['vertices']]);triangles=np.array(input['scalp']['triangles'])
    center=xyz(request['sourceCenter']);target=xyz(request['targetCenterMeters']);scale=xyz(request['metersPerSourceUnit'])
    maximum_root_error=0.
    for source_guide,mapping,guide in zip(source['strands'],request['mappings'],original['guides']):
        assert source_guide['id']==mapping['guideID']==guide['id']
        binding=guide['root'];root=np.array(binding['barycentric'])@vertices[triangles[binding['triangleIndex']]]
        transformed=(np.array(source_guide['points'])-center)*scale+target
        actual=np.array([xyz(p) for p in guide['points']])
        expected=transformed+root-transformed[0]
        assert np.max(np.abs(actual-expected))<1e-12
        maximum_root_error=max(maximum_root_error,float(np.linalg.norm(actual[0]-root)))
    for parent,result,region in [(original,fringe,'fringe'),(fringe['haircut'],crown,'crown')]:
        assert result['haircut']['revision']==parent['revision']+1
        assert result['haircut']['generation']==parent['generation']
        changed=[]
        for old,new in zip(parent['guides'],result['haircut']['guides']):
            assert old['id']==new['id'] and old['root']==new['root'] and old['points'][0]==new['points'][0]
            if old!=new:
                changed.append(old['id']);assert old['region']==region
            if new['region']=='fringe' and region=='fringe':
                points=np.array([xyz(p) for p in new['points']])
                assert abs(np.linalg.norm(np.diff(points,axis=0),axis=1).sum()-.03)<1e-12
        assert changed==result['changedGuideIDs']
    assert len(list((args.run/'history').glob('*/*.json')))==3
    for name,cut in [('before-mesh.json',imported),('after-mesh.json',fringe)]:
        mesh=load(name);assert mesh['haircutSHA256']==cut['validation']['haircutSHA256']
        assert mesh['guideCount']==source['strandCount'] and len(mesh['vertices'])<=250_000
    # Known closest points exercise face interior, edge and vertex regions.
    tri=np.array([[[0.,0.,0.],[1.,0.,0.],[0.,1.,0.]]])
    for p,expected in [([.2,.3,1],[.5,.2,.3]),([.8,.8,0],[0,.5,.5]),([-1,-1,0],[1,0,0])]:
        index,bary,distance=nearest_triangle(np.array(p),tri)
        assert index==0 and np.allclose(bary,expected)
        assert np.isclose(distance,np.linalg.norm(np.array(p)-np.array(expected)@tri[0]))
    # Diagnostic only: analytic inferred cap, at sampled curve vertices.
    env=completion['request']['envelope'];center=xyz(env['center']);radii=xyz(env['radii']);violations=[]
    for guide in original['guides']:
        points=np.array([xyz(p) for p in guide['points']]);q=(points-center)/radii;n=np.linalg.norm(q,axis=1)
        cosine=q[:,2]/np.maximum(np.linalg.norm(q[:,[0,2]],axis=1),1e-12)
        boundary=env['sideBoundaryY']+np.maximum(0,cosine)*(env['frontBoundaryY']-env['sideBoundaryY'])+np.maximum(0,-cosine)*(env['backBoundaryY']-env['sideBoundaryY'])
        depth=np.linalg.norm(points-center,axis=1)*(1/np.maximum(n,1e-12)-1)
        inside=(points[:,1]>=boundary)&(depth>.001)
        if inside.any():violations.append(dict(guideID=guide['id'],maximumRadialPenetrationMeters=float(depth[inside].max()),pointCount=int(inside.sum())))
    report=dict(method='mapped_model_independent_checks_v1',guideCount=len(original['guides']),maximumRootErrorMeters=maximum_root_error,
        fringeChangedGuides=len(fringe['changedGuideIDs']),crownChangedGuides=len(crown['changedGuideIDs']),
        preservedSourceCurvesAfterDeclaredTransform=True,untouchedRegionsAndHistoryPreserved=True,
        modelAndInferredScalpProvenancePreserved=True,knownNearestTriangleCasesPassed=True,
        guidesWithSampledPointsOver1mmInsideInferredCap=len(violations),
        maximumSampledRadialPenetrationMeters=max([v['maximumRadialPenetrationMeters'] for v in violations],default=0),
        interiorViolations=violations,acceptedForPersonalHaircut=False,
        notes=['Interior diagnostic uses inferred analytic cap and existing curve samples, not exact mesh signed distance or measured anatomy.',
               'No between-sample, self-collision or missing-ear guarantee.'])
    (args.run/'independent-checks.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
