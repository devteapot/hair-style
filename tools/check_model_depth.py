#!/usr/bin/env python3
"""Compare native depth against first-hit model triangles at returned camera poses.

This measures consistency with reconstruction inputs, not independent accuracy.
Requires NumPy. No registration fitting, scale adjustment or residual trimming.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
import numpy as np
from geometry_alignment_experiment import summary


def first_hit(origin, directions, vertices, triangles):
    """Two-sided Moller-Trumbore. Direction has optical z=1, so t is optical depth."""
    a=vertices[triangles[:,0]];e1=vertices[triangles[:,1]]-a;e2=vertices[triangles[:,2]]-a
    s=origin-a;q=np.cross(s,e1);numerator=(e2*q).sum(axis=1)
    output=[]
    for start in range(0,len(directions),64):
        d=directions[start:start+64]
        h=np.cross(d[:,None,:],e2[None,:,:]);det=(e1[None,:,:]*h).sum(axis=2)
        good=abs(det)>1e-10
        inverse=np.divide(1,det,out=np.zeros_like(det),where=good)
        u=(s[None,:,:]*h).sum(axis=2)*inverse
        v=(d@q.T)*inverse;t=numerator[None,:]*inverse
        good &= (u>=-1e-8)&(v>=-1e-8)&(u+v<=1+1e-8)&(t>.01)&(t<3)
        output.extend(np.where(good,t,np.inf).min(axis=1).tolist())
    return np.array(output)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle',type=Path);parser.add_argument('reconstruction',type=Path)
    parser.add_argument('mesh',type=Path);parser.add_argument('output',type=Path)
    parser.add_argument('--stride',type=int,default=4)
    parser.add_argument('--intrinsics',choices=['captured','vendor'],default='captured')
    args=parser.parse_args()
    if not 1<=args.stride<=8: parser.error('Stride must be 1..8')
    if args.output.exists(): parser.error('Output must be new')
    subprocess.run(['.build/debug/capture-inspect','inspect',str(args.bundle)],stdout=subprocess.DEVNULL,check=True)
    files={'mesh':args.mesh,'poses':args.reconstruction/'poses.json','masks':args.reconstruction/'masks.json','input':args.reconstruction/'input.json'}
    records={k:json.loads(p.read_bytes()) for k,p in files.items()}
    manifest=json.loads((args.bundle/'manifest.json').read_bytes())
    if records['input']['captureID']!=manifest['id']: raise ValueError('Capture mismatch')
    if hashlib.sha256((args.reconstruction/'preview.usdz').read_bytes()).hexdigest()!=records['mesh']['modelSHA256']: raise ValueError('Mesh model hash mismatch')
    vertices=np.array(records['mesh']['positions'],dtype=float);triangles=np.array(records['mesh']['triangles'],dtype=int)
    if vertices.ndim!=2 or vertices.shape[1]!=3 or not np.isfinite(vertices).all() or triangles.ndim!=2 or triangles.shape[1]!=3 or triangles.min()<0 or triangles.max()>=len(vertices): raise ValueError('Invalid mesh')
    masks={f['frameID']:f for f in records['masks']['frames']};mapping={s['sampleID']:s for s in records['input']['samples']}
    reports=[];start=time.perf_counter()
    for pose in records['poses']['poses']:
        sample=pose['sampleID'];frame=manifest['frames'][sample];m=frame['metadata'];mask_record=masks[m['id']]
        if mapping[sample]['frameID']!=m['id'] or mapping[sample]['frameSHA256']!=mask_record['frameSHA256']: raise ValueError('Sample/frame binding mismatch')
        size=m['depthSize'];width=size['width'];height=size['height'];mask=np.zeros(width*height,dtype=bool)
        for run in mask_record['mask']['includedRuns']:mask[run['start']:run['start']+run['count']]=True
        pixel=np.arange(width*height);pixel=pixel[mask & (pixel%width%args.stride==0)&(pixel//width%args.stride==0)]
        path=args.bundle/frame['depth']['path'];data=path.read_bytes()
        if hashlib.sha256(data).hexdigest()!=frame['depth']['sha256']: raise ValueError('Depth changed during inspection')
        depth=np.frombuffer(data,dtype='<f4')[pixel].astype(float)
        k=m['intrinsics'];sx=width/k['referenceSize']['width'];sy=height/k['referenceSize']['height']
        if args.intrinsics=='vendor':
            matrix=np.array(pose['estimatedIntrinsicsColumnMajor'],dtype=float).reshape(3,3,order='F')
            if not np.isfinite(matrix).all() or matrix[0,0]<=0 or matrix[1,1]<=0:raise ValueError('Invalid vendor intrinsics')
            k=dict(fx=matrix[0,0],fy=matrix[1,1],cx=matrix[0,2],cy=matrix[1,2])
            sx=width/m['imageSize']['width'];sy=height/m['imageSize']['height']
        rays=np.column_stack(((pixel%width-k['cx']*sx)/(k['fx']*sx), (pixel//width-k['cy']*sy)/(k['fy']*sy),np.ones(len(pixel))))
        camera=np.array(pose['transformColumnMajor']).reshape(4,4,order='F')
        if not np.allclose(camera[3],[0,0,0,1]) or not np.allclose(camera[:3,:3].T@camera[:3,:3],np.eye(3),atol=1e-5) or not np.isclose(np.linalg.det(camera[:3,:3]),1,atol=1e-5): raise ValueError('Nonrigid camera pose')
        # Explicit optical-to-AR camera hypothesis; checked against observed data, not silently fit.
        directions=(rays*np.array([1,-1,-1]))@camera[:3,:3].T
        hits=first_hit(camera[:3,3],directions,vertices,triangles);valid=np.isfinite(hits)&np.isfinite(depth)
        signed=hits[valid]-depth[valid]
        report=dict(sampleID=sample,samples=len(pixel),modelMisses=int((~np.isfinite(hits)).sum()),compared=int(valid.sum()),
                    absoluteResiduals=summary(abs(signed)) if len(signed) else None,
                    signedMedianMeters=float(np.median(signed)) if len(signed) else None,
                    pixelIndices=pixel.tolist(),modelDepthMeters=[float(t) if np.isfinite(t) else None for t in hits],observedDepthMeters=depth.tolist())
        reports.append(report)
        print('sample',sample,'hits',int(valid.sum()),'median mm',round(np.median(abs(signed))*1000,2) if len(signed) else None,flush=True)
    result=dict(method='vendor_camera_triangle_depth_consistency_v1',acceptedForHeadFitting=False,
                hashes={k:hashlib.sha256(p.read_bytes()).hexdigest() for k,p in files.items()},stride=args.stride,intrinsicsSource=args.intrinsics,frames=reports,elapsedSeconds=time.perf_counter()-start,
                notes=['Returned pose interpreted as model-from-AR-camera; optical axes mapped by diag(1,-1,-1). No transform fitting or scale correction.',
                       'Two-sided nearest forward triangle hit; all masked sampled pixels retained including model misses.',
                       'Vendor-intrinsics option is a pinhole hypothesis at input image resolution. Vendor lens distortion is not applied.',
                       'Depth data participated in reconstruction, so this is internal consistency and cannot certify metric accuracy.',
                       'Vendor-filled geometry and hair/bun remain; no per-vertex measured/inferred claim.'])
    args.output.write_text(json.dumps(result,indent=2)+'\n')


if __name__=='__main__':main()
