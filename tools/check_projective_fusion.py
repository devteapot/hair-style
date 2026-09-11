#!/usr/bin/env python3
"""Independently project an experimental TSDF mesh into its original captures.

Uses vectorized Newton inversion of the supplied radial table, independently of
Swift's interval bisection. Reports every vertex, including unsupported ones.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np


def mask_from_runs(runs, count):
    result=np.zeros(count,bool)
    for run in runs: result[run['start']:run['start']+run['count']]=True
    return result


def project(points, metadata):
    k=metadata['intrinsics']; ref=k['referenceSize']; size=metadata['depthSize']
    xy=points[:,:2]/points[:,2,None]*[k['fx'],k['fy']]+[k['cx'],k['cy']]
    domain=points[:,2]>0
    if metadata['depthRectification']=='not_applied':
        lens=metadata['lensCalibration'];c=np.array([lens['centerX'],lens['centerY']]);table=np.array(lens['inverseLookupTable'])
        maximum=np.linalg.norm(np.maximum(c,np.array([ref['width'],ref['height']])-c))
        radii=np.linspace(0,maximum,len(table));step=maximum/(len(table)-1)
        offset=xy-c;target=np.linalg.norm(offset,axis=1);r=np.minimum(target,maximum)
        domain &= target<=maximum*(1+table[-1])
        for _ in range(12):
            i=np.clip(np.floor(r/step).astype(int),0,len(table)-2)
            slope=(table[i+1]-table[i])/step
            magnification=table[i]+slope*(r-radii[i])
            r=np.clip(r-(r*(1+magnification)-target)/(1+magnification+r*slope),0,maximum)
        scale=np.divide(r,target,out=np.ones_like(r),where=target>1e-12)
        xy=c+offset*scale[:,None]
    else: assert metadata['depthRectification'] in ('synthetic_pinhole','arkit_aligned_scene_depth')
    xy*=np.array([size['width']/ref['width'],size['height']/ref['height']])
    domain &= np.all(np.isfinite(xy),axis=1)&(xy[:,0]>=-1e-7)&(xy[:,1]>=-1e-7)&(xy[:,0]<size['width'])&(xy[:,1]<size['height'])
    xx=np.clip(np.floor(np.maximum(xy[:,0],0)+.5).astype(int),0,size['width']-1)
    yy=np.clip(np.floor(np.maximum(xy[:,1],0)+.5).astype(int),0,size['height']-1)
    return yy*size['width']+xx,domain


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('captures',type=Path);p.add_argument('surface',type=Path);p.add_argument('output',type=Path);args=p.parse_args()
    source_bytes=args.surface.read_bytes();s=json.loads(source_bytes)
    assert s['method'] in ('masked_projective_tsdf_marching_tetrahedra_v1','masked_projective_tsdf_marching_tetrahedra_v2','masked_denoised_projective_tsdf_v1') and not s['completeHead'] and not s['suitableForHaircutFitting']
    request=s['request'];mu=request['truncationMeters'];minimum=request['minimumNearSurfaceViews']
    positions=np.array([[v['position'][k] for k in 'xyz'] for v in s['vertices']])
    normals=np.array([[v['normal'][k] for k in 'xyz'] for v in s['vertices']]);triangles=np.array(s['triangles'])
    assert np.all(np.isfinite(positions)) and np.all(np.isfinite(normals))
    assert np.max(np.abs(np.linalg.norm(normals,axis=1)-1))<1e-5
    assert triangles.min()>=0 and triangles.max()<len(positions)
    assert all(len(set(t))==3 for t in triangles)
    assert len(set(map(tuple,np.sort(triangles,axis=1))))==len(triangles)
    edges={}
    for t in triangles:
        for a,b in zip(t,np.roll(t,-1)):
            key=tuple(sorted((a,b)));old=edges.get(key,(0,0));edges[key]=(old[0]+1,old[1]+(1 if a<b else -1))
    topology={'boundaryEdges':sum(c==1 for c,d in edges.values()),'nonManifoldEdges':sum(c>2 for c,d in edges.values()),'inconsistentWindingEdges':sum(c==2 and d!=0 for c,d in edges.values())}
    assert topology==s['topology'] and topology['nonManifoldEdges']==topology['inconsistentWindingEdges']==0
    summaries=[];deltas=[];near_votes=np.zeros(len(positions),int)
    for item,evidence in zip(request['surfaceRequest']['frames'],s['frames']):
        bundle=args.captures/item['captureID'];manifest=json.loads((bundle/'manifest.json').read_text())
        frame=next(f for f in manifest['frames'] if f['metadata']['id']==item['frameID']);meta=frame['metadata']
        depth_bytes=(bundle/frame['depth']['path']).read_bytes();assert hashlib.sha256(depth_bytes).hexdigest()==frame['depth']['sha256']
        depth=np.frombuffer(depth_bytes,'<f4').astype(float)
        mask=mask_from_runs(item['mask']['includedRuns'],len(depth))&np.isfinite(depth)&(depth>=.05)&(depth<=2)
        if frame.get('confidence'):
            raw=(bundle/frame['confidence']['path']).read_bytes();assert hashlib.sha256(raw).hexdigest()==frame['confidence']['sha256']
            confidence=np.frombuffer(raw,np.uint8);mask&=(confidence>=request['surfaceRequest']['minimumConfidence'])&(confidence<=2)
        matrix=np.array(evidence['referenceFromCamera']['rowMajor']).reshape(4,4)
        camera=(positions-matrix[:3,3])@matrix[:3,:3]
        pixels,domain=project(camera,meta);valid=domain&mask[pixels]
        delta=depth[pixels]-camera[:,2]
        near=valid&(np.abs(delta)<=mu);near_votes+=near
        visible=valid&(delta>=-mu)
        deltas.append(np.where(visible,delta,np.nan))
        errors=np.abs(delta[valid])
        summaries.append({'frameID':item['frameID'],'vertexCount':len(positions),'validProjectedVertices':int(valid.sum()),
                          'withinTruncationBand':int(near.sum()),'farFreeSpaceVertices':int((valid&(delta>mu)).sum()),
                          'behindSurfaceVertices':int((valid&(delta< -mu)).sum()),
                          'absoluteDepthErrorMedianMeters':float(np.median(errors)),'absoluteDepthErrorP95Meters':float(np.percentile(errors,95)),
                          'absoluteDepthErrorMaximumMeters':float(np.max(errors))})
    values=np.array(deltas);has=np.any(np.isfinite(values),axis=0)
    spread=np.zeros(len(positions));spread[has]=np.nanmax(values[:,has],axis=0)-np.nanmin(values[:,has],axis=0)
    unsupported=near_votes<minimum;disagree=spread>request['maximumSignedDistanceSpreadMeters']
    result={'method':'independent_native_depth_projection_newton_v1','surfaceFileSHA256':hashlib.sha256(source_bytes).hexdigest(),
            'vertices':len(positions),'triangles':len(triangles),'topology':topology,'frames':summaries,
            'nearViewHistogram':{str(i):int((near_votes==i).sum()) for i in range(len(deltas)+1)},
            'verticesBelowMinimumViews':int(unsupported.sum()),'verticesExceedingSignedDistanceSpread':int(disagree.sum()),
            'trianglesTouchingUnsupportedVertex':int(np.any(unsupported[triangles],axis=1).sum()),
            'allVerticesReprojectWithinDeclaredSupport':not bool(np.any(unsupported|disagree)),
            'physicalAccuracyVerified':False,'notes':['Raw native-depth reprojection is a consistency check on fitting inputs, not independent physical ground truth.',
                'Grid-corner support does not automatically prove support of interpolated output vertices; this report retains that distinction.']}
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ['frames','notes']},indent=2))


if __name__=='__main__':main()
