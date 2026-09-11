#!/usr/bin/env python3
"""Propose (not approve) a template-to-person guide correspondence.

Fits an axis-aligned envelope to the source scalp, maps to the existing inferred
target envelope, then finds exact nearest triangle bindings. It preserves every
guide and reports all correction distances before the Swift importer runs.
"""
import argparse
import copy
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import uuid
import numpy as np
from haar_decode_metal import read_obj

REGIONS = ['fringe', 'top', 'crown', 'anatomical_left', 'anatomical_right', 'nape']


def attachment_boundary_report(scalp, mappings):
    """Separate internal mesh edges from the open construction boundary."""
    triangles=np.array(scalp['triangles'],dtype=int)
    vertices=np.array([xyz(v) for v in scalp['vertices']])
    counts=Counter(tuple(sorted((t[i],t[(i+1)%3]))) for t in triangles for i in range(3))
    if any(count>2 for count in counts.values()):raise ValueError('Nonmanifold scalp')
    edges=np.array([edge for edge,count in counts.items() if count==1],dtype=int)
    details=[]
    for mapping in mappings:
        b=mapping['binding']
        if b['normalOffsetMeters']!=0:raise ValueError('Boundary diagnostic requires zero-offset roots')
        p=np.array(b['barycentric'])@vertices[triangles[b['triangleIndex']]]
        distance=None
        if len(edges):
            a=vertices[edges[:,0]];d=vertices[edges[:,1]]-a
            t=np.clip(np.sum((p-a)*d,axis=1)/np.maximum(np.sum(d*d,axis=1),1e-30),0,1)
            distance=float(np.linalg.norm(p-a-t[:,None]*d,axis=1).min())
        if distance is not None and distance<=1e-8:
            details.append(dict(guideID=mapping['guideID'],region=mapping['region'],
                triangleIndex=b['triangleIndex'],distanceToOpenBoundaryMeters=distance))
    return dict(openBoundaryEdges=len(edges),rootsOnOpenBoundary=len(details),
        boundaryRoots=details,requiresBoundaryReview=bool(details),
        note='Construction-boundary clamping is not a measured hairline or approved attachment.')


def point(p):
    return dict(zip(('x', 'y', 'z'), map(float, p)))


def xyz(p):
    return np.array([p['x'], p['y'], p['z']], dtype=float)


def nearest_triangle(p, triangles):
    a, b, c = triangles[:, 0], triangles[:, 1], triangles[:, 2]
    ab, ac, ap = b-a, c-a, p-a
    dot = lambda u,v: np.einsum('ij,ij->i', u,v)
    d00, d01, d11 = dot(ab,ab), dot(ab,ac), dot(ac,ac)
    denominator = d00*d11-d01*d01
    if np.any(denominator <= 1e-20):
        raise ValueError('Degenerate target triangle')
    v = (d11*dot(ap,ab)-d01*dot(ap,ac))/denominator
    w = (d00*dot(ap,ac)-d01*dot(ap,ab))/denominator
    bary = np.c_[1-v-w, v, w]
    projection = np.einsum('ij,ijk->ik', bary, triangles)
    distances = np.linalg.norm(projection-p, axis=1)
    distances[np.any(bary < 0, axis=1)] = np.inf
    best_bary = bary.copy()
    for left, right in ((0,1),(1,2),(2,0)):
        start, end = triangles[:,left], triangles[:,right]
        direction = end-start
        t = np.clip(dot(p-start,direction)/dot(direction,direction),0,1)
        q = start+t[:,None]*direction
        candidate = np.linalg.norm(q-p,axis=1)
        improve = candidate < distances
        distances[improve] = candidate[improve]
        weights = np.zeros_like(bary);weights[:,left]=1-t;weights[:,right]=t
        best_bary[improve] = weights[improve]
    index = int(np.argmin(distances))
    return index, best_bary[index], float(distances[index])


def envelope(vertices):
    origin = vertices.mean(0)
    d = vertices-origin
    coefficients = np.linalg.lstsq(np.c_[d*d,d], np.ones(len(vertices)), rcond=None)[0]
    if np.any(coefficients[:3] <= 0):
        raise ValueError('Source fit is not an ellipsoid')
    center = -coefficients[3:] / (2*coefficients[:3])
    radii = np.sqrt((1+np.sum(coefficients[:3]*center*center))/coefficients[:3])
    center += origin
    if not np.isfinite(center).all() or not np.isfinite(radii).all():
        raise ValueError('Invalid source envelope')
    return center, radii


def region_for(p, center, radii):
    # Explicit coarse experiment labels; no measured hairline/part inference.
    x,y,z = (p-center)/radii
    if y > .72:
        return 'top' if z >= 0 else 'crown'
    if z > abs(x)*.75:
        return 'fringe'
    if z < -abs(x)*.75:
        return 'nape' if y < .1 else 'crown'
    return 'anatomical_left' if x >= 0 else 'anatomical_right'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path)
    parser.add_argument('scalp_result',type=Path)
    parser.add_argument('template',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--guard',action='store_true',help='Bind a continuous inferred-envelope guard into the brief and import request.')
    args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=False)
    source=json.loads(args.source.read_text())
    result=json.loads(args.scalp_result.read_text())
    if source['acceptedForPersonalHaircut'] or source['units']!='unresolved':
        raise ValueError('Expected the unresolved research artifact')
    scalp=copy.deepcopy(result['scalp'])
    if scalp['coordinateConvention']!='eye_midpoint_x_anatomical_left_y_up_z_anterior_meters':
        raise ValueError('Target must use canonical meters')
    result_hash=hashlib.sha256(args.scalp_result.read_bytes()).hexdigest()
    # Completion's review identity may be a human-readable label. Create a new
    # binding-profile UUID without changing the review document or its mesh.
    scalp['id']=str(uuid.uuid5(uuid.NAMESPACE_URL,'research-scalp:'+result_hash))
    scalp['sourceSHA256']=scalp['sourceSHA256']+[result_hash]
    scalp['method']+=' Research binding profile; shape and hairline still require review.'
    target=result['request']['envelope'];target_center=xyz(target['center']);target_radii=xyz(target['radii'])
    source_vertices,_=read_obj(args.template)
    source_center,source_radii=envelope(source_vertices.astype(float))
    scale=target_radii/source_radii
    vertices=np.array([xyz(p) for p in scalp['vertices']]);triangles=vertices[np.array(scalp['triangles'])]
    mappings=[];corrections=[];boundary=0
    for guide in source['strands']:
        p=target_center+(np.array(guide['points'][0])-source_center)*scale
        index,bary,distance=nearest_triangle(p,triangles)
        attachment=bary@triangles[index]
        mappings.append(dict(guideID=guide['id'],region=region_for(attachment,target_center,target_radii),
            binding=dict(triangleIndex=index,barycentric=bary.tolist(),normalOffsetMeters=0)))
        corrections.append(distance)
        if np.any(bary < 1e-8):boundary+=1
    profile=dict(schemaVersion=1,id=str(uuid.uuid4()),revision=1,subjectSessionID=scalp['subjectSessionID'],regions=[
        dict(region=region,origin='unknown',quality='unknown',evidenceReferences=[],method='Natural-hair length has not been measured or confirmed.') for region in REGIONS])
    brief_request=dict(schemaVersion=1,id=str(uuid.uuid4()),mode='autonomous',seed=42,lengthRanges=[])
    def write(name,value):
        (args.output/name).write_text(json.dumps(value,indent=2)+'\n')
    write('scalp.json',scalp);write('profile.json',profile);write('brief-request.json',brief_request)
    root=Path(__file__).resolve().parent.parent
    subprocess.run([str(root/'tools/dev.sh'),'swift','run','capture-inspect','hair-brief',
        str(args.output/'scalp.json'),str(args.output/'profile.json'),str(args.output/'brief-request.json'),str(args.output/'brief.json')],check=True,cwd=root)
    brief=json.loads((args.output/'brief.json').read_text())
    guard=None
    if args.guard:
        guard=dict(scalpSHA256=brief['input']['brief']['scalpSHA256'],envelope=target,
            permittedInsetMeters=.0005,maximumPointCorrectionMeters=.002)
        brief['input']['brief']['envelopeGuard']=guard
    write('input.json',brief['input'])
    request=dict(schemaVersion=1,id=str(uuid.uuid4()),sourceArtifactSHA256=hashlib.sha256(args.source.read_bytes()).hexdigest(),
        scalpSHA256=brief['input']['brief']['scalpSHA256'],sourceCenter=point(source_center),targetCenterMeters=point(target_center),
        metersPerSourceUnit=point(scale),maximumRootCorrectionMeters=.02,mappings=mappings,
        method='Axis-aligned source scalp ellipsoid fit to inferred target envelope; nearest-triangle root correction. Anatomical orientation and correspondence require review.')
    if guard:request['envelopeGuard']=guard
    write('mapping.json',request)
    report=dict(method='unreviewed_ellipsoid_template_correspondence_v1',sourceSHA256=request['sourceArtifactSHA256'],
        scalpResultSHA256=result_hash,sourceCenter=point(source_center),sourceRadii=point(source_radii),metersPerSourceUnit=point(scale),
        guideCount=len(mappings),rootCorrectionMaximumMeters=max(corrections),rootCorrectionMedianMeters=float(np.median(corrections)),
        rootCorrectionP95Meters=float(np.quantile(corrections,.95)),rootsOnTriangleEdges=boundary,
        attachmentBoundary=attachment_boundary_report(scalp,mappings),
        guidesExceedingCorrectionLimit=sum(x>.02 for x in corrections),regionCounts={r:sum(m['region']==r for m in mappings) for r in REGIONS},
        acceptedForPersonalHaircut=False,notes=['Every source guide retained; no automatic acceptance or hidden removal.',
            'Region assignments and template orientation are explicit heuristic assumptions.',
            'New binding profile retains exact target vertices and triangle provenance.',
            'Natural-hair properties remain unknown; this is fitting, not personalized style selection.'])
    write('mapping-report.json',report)
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
