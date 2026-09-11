#!/usr/bin/env python3
"""Joint rigid pose refinement of separate rear depth patches (NumPy).

Experimental: world camera poses are the initial estimate. No deformation,
scale, remeshing, accepted head registration or semantic segmentation is emitted.
"""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import time
import numpy as np
from geometry_alignment_experiment import nearest, summary, transform


def rotation(vector):
    angle = np.linalg.norm(vector)
    if angle < 1e-14: return np.eye(3)
    axis = vector/angle
    x,y,z = axis
    k = np.array([[0,-z,y],[z,0,-x],[-y,x,0]])
    return np.eye(3)+math.sin(angle)*k+(1-math.cos(angle))*(k@k)


def matched(p, pn, q, qn, cutoff=.02):
    distances, target = nearest(p,q)
    valid = (distances <= cutoff) & ((pn*qn[target]).sum(axis=1) >= .7)
    return np.flatnonzero(valid),target[valid]


def connected(count, edges):
    reached = {0}
    while True:
        before = len(reached)
        for i,j in edges:
            if i in reached or j in reached: reached.update([i,j])
        if len(reached) == before: return len(reached) == count


def evaluate(points, normals, corrected, edges):
    results=[]
    for i,j in edges:
        directions=[]
        for a,b in [(i,j),(j,i)]:
            # Fixed initial overlap is never reselected after fitting.
            indices,_ = matched(points[a],normals[a],points[b],normals[b])
            before=nearest(points[a],points[b])[0];after=nearest(corrected[a],corrected[b])[0]
            directions.append(dict(source=a,target=b,allBefore=summary(before),allAfter=summary(after),
                fixedInitialOverlapCount=len(indices),
                fixedInitialOverlapBefore=summary(before[indices]) if len(indices) else None,
                fixedInitialOverlapAfter=summary(after[indices]) if len(indices) else None))
        results.append(dict(views=[i,j],directions=directions))
    return results


def solve(points, normals, iterations=20):
    if not 2 <= len(points) <= 32 or len(points)!=len(normals): raise ValueError('Requires 2..32 matching patches')
    for p,n in zip(points,normals):
        if p.ndim!=2 or p.shape[1]!=3 or n.shape!=p.shape or not 100 <= len(p) <= 250_000:
            raise ValueError('Invalid patch dimensions')
        if not np.isfinite(p).all() or not np.isfinite(n).all() or np.max(np.linalg.norm(p,axis=1))>20:
            raise ValueError('Nonfinite or unbounded patch')
        if not np.allclose(np.linalg.norm(n,axis=1),1,atol=.01): raise ValueError('Normals must be unit length')
    # Centering makes rotation conditioning independent of the AR world's origin.
    center = np.concatenate(points).mean(axis=0)
    local = [p-center for p in points]
    fit_indices = [np.arange(0,len(p),max(3,math.ceil(len(p)/800))) for p in points]
    edges=[]
    for i in range(len(points)):
        for j in range(i+1,len(points)):
            a,_=matched(local[i][fit_indices[i]],normals[i][fit_indices[i]],local[j],normals[j])
            b,_=matched(local[j][fit_indices[j]],normals[j][fit_indices[j]],local[i],normals[i])
            if len(a)>=max(40,.15*len(fit_indices[i])) and len(b)>=max(40,.15*len(fit_indices[j])): edges.append((i,j))
    if not connected(len(points),edges):
        return dict(stopped='disconnected_overlap_graph',acceptedForFusion=False,edges=edges),None
    poses=[np.eye(4) for _ in points];history=[];status='iteration_limit'; rejected_trial=None
    dimension=(len(points)-1)*6
    for iteration in range(iterations):
        moved=[transform(p,m) for p,m in zip(local,poses)]
        ns=[n@m[:3,:3].T for n,m in zip(normals,poses)]
        h=np.zeros((dimension,dimension));rhs=np.zeros(dimension);active=[];total=0;residuals=[]
        for i,j in edges:
            used=0
            for a,b in [(i,j),(j,i)]:
                ids=fit_indices[a]
                source_ids,target_ids=matched(moved[a][ids],ns[a][ids],moved[b],ns[b])
                if len(source_ids)<40: continue
                p=moved[a][ids[source_ids]];q=moved[b][target_ids];n=ns[b][target_ids]
                residual=((p-q)*n).sum(axis=1)
                # Rotation variables represent displacement at a 10cm lever arm.
                ja=np.column_stack((np.cross(p,n)/.1,n));jb=-np.column_stack((np.cross(q,n)/.1,n))
                weight=np.minimum(1,.003/np.maximum(abs(residual),1e-12))/len(residual)
                blocks=[]
                if a: blocks.append((slice((a-1)*6,a*6),ja))
                if b: blocks.append((slice((b-1)*6,b*6),jb))
                for sa,va in blocks:
                    rhs[sa]-=va.T@(weight*residual)
                    for sb,vb in blocks: h[sa,sb]+=va.T@(weight[:,None]*vb)
                used+=len(residual);residuals.extend(abs(residual).tolist())
            if used: active.append((i,j));total+=used
        if not connected(len(points),active): status='lost_overlap_graph';break
        eigen=np.linalg.eigvalsh(h)
        ratio=float(eigen[0]/max(eigen[-1],1e-30))
        # Reject degeneracy before adding numerical damping; planar inputs cannot earn a pose estimate.
        if ratio<1e-7: status='unobservable_geometry';break
        step=np.linalg.solve(h+np.eye(dimension)*eigen[-1]*1e-6,rhs).reshape(-1,6)
        scale=min(1, .003/max(np.linalg.norm(step[:,3:],axis=1).max(),1e-12),
                  math.radians(2)/max(np.linalg.norm(step[:,:3]/.1,axis=1).max(),1e-12))
        step*=scale
        trial=[poses[0]]
        for old,s in zip(poses[1:],step):
            increment=np.eye(4);increment[:3,:3]=rotation(s[:3]/.1);increment[:3,3]=s[3:]
            trial.append(increment@old)
        angles=[math.acos(float(np.clip((np.trace(m[:3,:3])-1)/2,-1,1))) for m in trial]
        shifts=[np.linalg.norm(transform(p.mean(axis=0,keepdims=True),m)-p.mean(axis=0,keepdims=True)) for p,m in zip(local,trial)]
        if max(angles)>math.radians(10) or max(shifts)>.03:
            rejected_trial=dict(rotationDegrees=[math.degrees(a) for a in angles],centroidShiftsMeters=[float(s) for s in shifts])
            status='exceeded_pose_correction_bounds';break
        poses=trial
        maximum_step=float(np.linalg.norm(step,axis=1).max())
        history.append(dict(iteration=iteration,correspondences=total,activeEdges=len(active),
                            preStepMedianPlaneResidualMeters=float(np.median(residuals)),
                            smallestToLargestEigenvalueRatio=ratio,maximumScaledStepMeters=maximum_step))
        if maximum_step<1e-5: status='converged';break
        print('iteration',iteration,'plane median mm',round(float(np.median(residuals))*1000,3),flush=True)
    corrected=[transform(p,m)+center for p,m in zip(local,poses)]
    # Convert local corrections back into the original AR world, preserving original frame geometry.
    world=[]
    for pose in poses:
        m=pose.copy();m[:3,3]=center+pose[:3,3]-pose[:3,:3]@center;world.append(m)
    report=dict(stopped=status,acceptedForFusion=False,anchorView=0,edges=edges,iterations=history,rejectedTrial=rejected_trial,
                worldCorrectionsRowMajor=[m.reshape(-1).tolist() for m in world],
                evaluation=evaluate(points,normals,corrected,edges),
                maximumCentroidCorrectionMeters=float(max(np.linalg.norm(a.mean(axis=0)-b.mean(axis=0)) for a,b in zip(points,corrected))))
    return report,world


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('preview',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();raw=args.preview.read_bytes();preview=json.loads(raw)
    if preview.get('method')!='unmerged_world_depth_patch_preview_v1' or preview.get('acceptedForFusion') is not False:
        raise ValueError('Use an unmerged diagnostic rear preview')
    patches=preview['patches'];points=[np.array(p['positions'],dtype=float) for p in patches]
    normals=[np.array(p['normals'],dtype=float) for p in patches]
    start=time.perf_counter();result,corrections=solve(points,normals)
    result.update(method='joint_rigid_point_to_plane_rear_experiment_v1',sourceSHA256=hashlib.sha256(raw).hexdigest(),
                  elapsedSeconds=time.perf_counter()-start,numpyVersion=np.__version__,
                  notes=['View zero fixes the coordinate gauge. Only rigid corrections; no scaling or geometry deformation.',
                         'Fits sparse source samples with 20mm distance, normal-dot 0.7, 3mm robust weighting and bounded pose steps.',
                         'All-distance and fixed-initial-overlap evaluations retain disagreement; overlap is not reselected to improve metrics.',
                         'Evaluation samples include fitted and spatially correlated pixels, not independent physical validation.',
                         'Hair, neck and other material inside the spatial crop remain; this cannot establish skull shape.',
                         'Results are experimental and never replace accepted head registration. Original samples and triangle topology remain unchanged.'])
    args.output.mkdir(parents=True,exist_ok=False)
    (args.output/'report.json').write_text(json.dumps(result,indent=2)+'\n')
    if corrections is not None:
        revised=copy.deepcopy(preview);revised['poseRefinement']=dict(method=result['method'],stopped=result['stopped'],sourceSHA256=result['sourceSHA256'])
        revised['notes']=result['notes']
        for patch,p,n,m in zip(revised['patches'],points,normals,corrections):
            patch['positions']=transform(p,m).tolist();patch['normals']=(n@m[:3,:3].T).tolist()
            patch['worldCorrectionRowMajor']=m.reshape(-1).tolist()
        (args.output/'world-preview.json').write_text(json.dumps(revised))
    print('Stopped:',result['stopped'],'edges:',len(result['edges']),'accepted for fusion: false')


if __name__=='__main__': main()
