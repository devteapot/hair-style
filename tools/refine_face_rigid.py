#!/usr/bin/env python3
"""Bounded research rigid ICP. Never emits an accepted fusion artifact.

Uses original measured surface samples, excludes held-out landmark neighborhoods
from both fitting sets, and checks those landmarks only after optimization.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from check_captured_registration import sample


def nearest(query, target):
    ids, distances = [], []
    for start in range(0, len(query), 128):
        q = query[start:start+128]
        squared = np.maximum(0, np.sum(q*q,axis=1)[:,None]+np.sum(target*target,axis=1)[None,:]-2*q@target.T)
        index = squared.argmin(axis=1)
        ids.extend(index); distances.extend(np.sqrt(squared[np.arange(len(q)),index]))
    return np.array(ids),np.array(distances)


def transform(points, matrix):
    return points@matrix[:3,:3].T+matrix[:3,3]


def rigid(a,b):
    ac=a.mean(axis=0);bc=b.mean(axis=0)
    u,s,vt=np.linalg.svd((a-ac).T@(b-bc))
    if s[1]<1e-8: raise ValueError('Degenerate geometric correspondence')
    parity=np.eye(3);parity[2,2]=np.linalg.det(vt.T@u.T)
    r=vt.T@parity@u.T;m=np.eye(4);m[:3,:3]=r;m[:3,3]=bc-r@ac
    return m


def rotation_degrees(matrix):
    return float(np.degrees(np.arccos(np.clip((np.trace(matrix[:3,:3])-1)/2,-1,1))))


def optimize(source,target,initial,iterations=30):
    """No held-out samples or metrics enter this optimizer."""
    if min(len(source),len(target))<100: raise ValueError('Insufficient fitting samples')
    source=source[np.linspace(0,len(source)-1,min(2000,len(source)),dtype=int)]
    matrix=initial.copy();history=[]
    for iteration in range(iterations):
        moved=transform(source,matrix);indices,distance=nearest(moved,target)
        eligible=np.flatnonzero(distance<=.012)
        if len(eligible)<max(100,len(source)//3): raise ValueError('Insufficient 12 mm fitting overlap')
        # Keep 80% of eligible matches. Trimming affects only fitting, never validation.
        keep=eligible[np.argsort(distance[eligible],kind='stable')[:max(100,int(.8*len(eligible)))]]
        delta=rigid(moved[keep],target[indices[keep]])
        candidate=delta@matrix
        correction=candidate@np.linalg.inv(initial)
        center=source.mean(axis=0,keepdims=True)
        shift=float(np.linalg.norm(transform(center,candidate)-transform(center,initial)))
        if rotation_degrees(correction)>8 or shift>.015:
            raise ValueError('Refinement exceeds 8 degree / 15 mm centroid movement bound')
        fixed_before=float(np.mean(distance[keep]**2))
        fixed_after=float(np.mean(np.sum((transform(source[keep],candidate)-target[indices[keep]])**2,axis=1)))
        if fixed_after>fixed_before+1e-12: raise ValueError('Rigid update increases fixed-match fitting error')
        movement=float(np.max(np.linalg.norm(transform(source,candidate)-moved,axis=1)))
        history.append({'iteration':iteration,'eligibleMatches':len(eligible),'fittedMatches':len(keep),
                        'fitRMSBeforeMeters':float(np.sqrt(fixed_before)),
                        'fitRMSAfterMeters':float(np.sqrt(fixed_after)),
                        'maximumStepMeters':movement,'centroidCorrectionMeters':shift,
                        'rotationCorrectionDegrees':rotation_degrees(correction)})
        matrix=candidate
        if movement<.00001:break
    return matrix,history


def read_surface(path):
    raw=path.read_bytes();s=json.loads(raw)
    assert len(s['frames'])==1 and not s['includesInferredAnatomy'] and not s['completeHead']
    assert s['coordinateConvention']=='reference_optical_x_right_y_down_z_forward_meters'
    assert s['frames'][0]['referenceFromCamera']['rowMajor']==[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    points=np.array([[v['position'][k] for k in 'xyz'] for v in s['vertices']])
    assert points.ndim==2 and points.shape[1]==3 and np.all(np.isfinite(points))
    assert all(len(v['observations'])==1 and v['observations'][0]['frameIndex']==0 for v in s['vertices'])
    # Surface observations reference the native depth raster, scaled into native RGB pixels.
    return s,points,hashlib.sha256(raw).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('bundle','source_surface','target_surface','selection','registration','output'):p.add_argument(name,type=Path)
    a=p.parse_args();manifest=json.loads((a.bundle/'manifest.json').read_text());selection=json.loads(a.selection.read_text());captured=json.loads(a.registration.read_text());reg=captured['registration']
    assert manifest['status']=='completed'
    fitting=[];surface_hashes=[];excluded_counts=[]
    for role,path,key in [('source',a.source_surface,'sourceFrameID'),('target',a.target_surface,'targetFrameID')]:
        frame=next(f for f in manifest['frames'] if f['metadata']['id']==selection[key]);meta=frame['metadata']
        surface,points,digest=read_surface(path)
        assert surface['frames'][0]['frameSHA256']==captured[role+'FrameSHA256']
        assert surface['frames'][0]['frameID']==selection[key]
        depthsize=np.array([meta['depthSize'][k] for k in ['width','height']]);imagesize=np.array([meta['imageSize'][k] for k in ['width','height']])
        pixelids=np.array([v['observations'][0]['depthPixelIndex'] for v in surface['vertices']])
        xy=np.column_stack((pixelids%depthsize[0],pixelids//depthsize[0]))*imagesize/depthsize
        held=np.array([[v[role]['x'],v[role]['y']] for v in selection['validationPairs']])
        allowed=np.all(np.linalg.norm(xy[:,None,:]-held[None,:,:],axis=2)>12,axis=1)
        fitting.append(points[allowed]);excluded_counts.append(int((~allowed).sum()));surface_hashes.append(digest)
    original=np.array(reg['targetFromSource']['rowMajor']).reshape(4,4)
    matrix,history=optimize(*fitting,original)
    held_source=sample(a.bundle,selection['sourceFrameID'],[x['source'] for x in selection['validationPairs']],captured['minimumConfidence'])
    held_target=sample(a.bundle,selection['targetFrameID'],[x['target'] for x in selection['validationPairs']],captured['minimumConfidence'])
    def validation(m):
        residual=np.linalg.norm(transform(held_source,m)-held_target,axis=1)
        med=float(np.median(residual));p95=float(np.sort(residual)[int(np.ceil(.95*len(residual)))-1])
        return {'medianMeters':med,'p95Meters':p95,'passesExistingLandmarkGate':med<=reg['thresholds']['validationMedianMeters'] and p95<=reg['thresholds']['validationP95Meters'],
                'residuals':[{'id':p['id'],'meters':float(e)} for p,e in zip(selection['validationPairs'],residual)]}
    result={'method':'bounded_point_to_point_icp_research_v1','sourceSurfaceSHA256':surface_hashes[0],'targetSurfaceSHA256':surface_hashes[1],
            'initializerRegistrationSHA256':hashlib.sha256(a.registration.read_bytes()).hexdigest(),
            'initializerAccepted':reg['accepted'],'heldOutExclusionRadiusNativePixels':12,
            'excludedSourceVertices':excluded_counts[0],'excludedTargetVertices':excluded_counts[1],
            'targetFromSource':matrix.reshape(-1).tolist(),'iterations':history,
            'initialValidation':validation(original),'refinedValidation':validation(matrix),'acceptedForFusion':False,
            'notes':['Nearest-sample matches and trimmed RMS describe the fitting objective, not anatomical correspondence.',
                     'Held-out landmark neighborhoods are excluded from both dense fitting clouds and used only after optimization.',
                     'All input surfaces must come from verified capture replay. File/hash binding does not authenticate arbitrary supplied JSON.',
                     'A failed initializer is used only as a research starting point. This tool cannot publish a fusion transform.',
                     'Correlated depth and model landmarks limit independence; no physical accuracy claim.']}
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:result[k] for k in ['initialValidation','refinedValidation','excludedSourceVertices','excludedTargetVertices']},indent=2))


if __name__=='__main__':main()
