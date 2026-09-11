#!/usr/bin/env python3
"""Offline rigid ICP experiment. Emits candidates, never accepted fusion transforms.

Requires NumPy. Input surfaces must be single-view capture-backed outputs. A
matching captured registration supplies a coarse initializer even when its
held-out gate rejected it; that failure is retained in the experiment report.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import time
import numpy as np


def read_surface(path):
    data = path.read_bytes(); surface = json.loads(data)
    if len(surface['frames']) != 1 or surface['completeHead'] or surface['includesInferredAnatomy']:
        raise ValueError('Use single-view observed geometry without completion')
    if surface['coordinateConvention'] != 'reference_optical_x_right_y_down_z_forward_meters':
        raise ValueError('Unsupported surface coordinate frame')
    points = np.array([[v['position'][k] for k in ('x','y','z')] for v in surface['vertices']], dtype=np.float64)
    if not 100 <= len(points) <= 250_000 or not np.isfinite(points).all() or np.max(np.linalg.norm(points, axis=1)) > 10:
        raise ValueError('Invalid or unbounded point cloud')
    return surface, points, hashlib.sha256(data).hexdigest()


def nearest(source, target):
    indices = []; distances = []; target_norm = (target*target).sum(axis=1)
    for start in range(0, len(source), 64):
        block = source[start:start+64]
        squared = (block*block).sum(axis=1)[:,None] + target_norm[None,:] - 2*(block @ target.T)
        index = squared.argmin(axis=1)
        indices.extend(index.tolist())
        distances.extend(np.sqrt(np.maximum(0, squared[np.arange(len(block)),index])).tolist())
    return np.array(distances), np.array(indices, dtype=int)


def transform(points, matrix):
    return points @ matrix[:3,:3].T + matrix[:3,3]


def summary(distances):
    return dict(count=len(distances), medianMeters=float(np.median(distances)),
                p95Meters=float(np.sort(distances)[math.ceil(len(distances)*.95)-1]),
                maximumMeters=float(distances.max()), fractionWithin3mm=float(np.mean(distances <= .003)))


def solve(source, target, initial, iterations=40):
    current = initial.copy(); history = []; converged = False
    # Deterministic disjoint source samples. Neighboring depth pixels remain
    # correlated; this split is a diagnostic, not independent validation.
    fit = source[np.arange(len(source)) % 3 == 0]
    for iteration in range(iterations):
        moved = transform(fit, current); distances, index = nearest(moved, target)
        include = distances <= .020
        if include.sum() < max(100, len(fit)//2):
            return dict(stopped='insufficient_overlap', acceptedForFusion=False, iterations=history)
        p = moved[include]; q = target[index[include]]
        weights = np.minimum(1, .003/np.maximum(distances[include],1e-12)); weights /= weights.sum()
        cp = (p*weights[:,None]).sum(axis=0); cq = (q*weights[:,None]).sum(axis=0)
        u,s,vt = np.linalg.svd(((p-cp)*weights[:,None]).T @ (q-cq))
        if s[1] < 1e-10:
            return dict(stopped='degenerate_correspondences', acceptedForFusion=False, iterations=history)
        correction = np.eye(3); correction[2,2] = np.linalg.det(vt.T @ u.T)
        rotation = vt.T @ correction @ u.T
        step = np.eye(4); step[:3,:3] = rotation; step[:3,3] = cq-rotation@cp
        current = step @ current
        angle = math.acos(float(np.clip((np.trace(rotation)-1)/2,-1,1)))
        motion = float(np.linalg.norm(cq-cp))
        history.append(dict(iteration=iteration, includedSamples=int(include.sum()),
                            preStepMedianMeters=float(np.median(distances[include])),
                            centroidStepMeters=motion, rotationStepRadians=angle))
        if motion < 1e-6 and angle < 1e-5:
            converged = True; break
    moved = transform(source,current)
    all_distances,_ = nearest(moved,target); reverse,_ = nearest(target,moved)
    holdout = all_distances[np.arange(len(source)) % 3 != 0]
    center = source.mean(axis=0,keepdims=True)
    relative_rotation = current[:3,:3] @ initial[:3,:3].T
    return dict(stopped='converged' if converged else 'iteration_limit',acceptedForFusion=False,
                targetFromSourceRowMajor=current.reshape(-1).tolist(),iterations=history,
                sourceToTarget=summary(all_distances),targetToSource=summary(reverse),
                unusedSourceSamples=summary(holdout),
                centroidShiftFromInitializerMeters=float(np.linalg.norm(transform(center,current)-transform(center,initial))),
                rotationFromInitializerDegrees=math.degrees(math.acos(float(np.clip((np.trace(relative_rotation)-1)/2,-1,1)))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path); parser.add_argument('target',type=Path)
    parser.add_argument('initializer',type=Path); parser.add_argument('output',type=Path)
    args = parser.parse_args()
    source,a,ah = read_surface(args.source); target,b,bh = read_surface(args.target)
    initial_bytes = args.initializer.read_bytes(); record = json.loads(initial_bytes)
    if record['sourceFrameSHA256'] != source['frames'][0]['frameSHA256'] or record['targetFrameSHA256'] != target['frames'][0]['frameSHA256']:
        raise ValueError('Initializer does not match supplied captured surfaces')
    matrix = np.array(record['registration']['targetFromSource']['rowMajor']).reshape(4,4)
    if not np.isfinite(matrix).all() or not np.allclose(matrix[3],[0,0,0,1]) or not np.allclose(matrix[:3,:3].T@matrix[:3,:3],np.eye(3),atol=1e-6) or not np.isclose(np.linalg.det(matrix[:3,:3]),1):
        raise ValueError('Initializer must be proper rigid, without scale')
    args.output.mkdir(parents=True,exist_ok=False)
    start=time.perf_counter(); results=[]
    for offset in [[0,0,0],[.003,0,0],[-.003,0,0],[0,.003,0],[0,-.003,0]]:
        seed=matrix.copy();seed[:3,3]+=offset
        result=solve(a,b,seed);result['initializerTranslationOffsetMeters']=offset;results.append(result)
        print(offset,result['stopped'],result.get('sourceToTarget'),flush=True)
    matrices=[np.array(r['targetFromSourceRowMajor']).reshape(4,4) for r in results if 'targetFromSourceRowMajor' in r]
    centers=np.array([transform(a.mean(axis=0,keepdims=True),m)[0] for m in matrices])
    spread=float(np.linalg.norm(centers[:,None,:]-centers[None,:,:],axis=2).max()) if len(centers) else None
    baseline=transform(a,matrix)
    report=dict(method='weighted_rigid_point_to_point_icp_experiment_v1',sourceFileSHA256=ah,targetFileSHA256=bh,
        initializerFileSHA256=hashlib.sha256(initial_bytes).hexdigest(),initializerPassedLandmarkValidation=record['registration']['accepted'],
        numpyVersion=np.__version__,elapsedSeconds=time.perf_counter()-start,acceptedForFusion=False,results=results,
        initializerGeometry=dict(sourceToTarget=summary(nearest(baseline,b)[0]),targetToSource=summary(nearest(b,baseline)[0])),
        largestFinalCentroidSeparationMeters=spread,
        notes=['Coarse initializer may have failed landmark validation. No failure is overridden.',
               'ICP uses 20 mm correspondence cutoff and 3 mm robust weights; all reported evaluation distances are untrimmed.',
               'Unused source samples are spatially correlated with fitting samples and target samples; not independent ground truth.',
               'Five translational starts probe local stability only. No global convergence, full observability or anatomical accuracy claim.',
               'No scale fitting, deformation, accepted capture registration or fused surface is emitted.'])
    (args.output/'report.json').write_text(json.dumps(report,indent=2)+'\n')

if __name__ == '__main__': main()
