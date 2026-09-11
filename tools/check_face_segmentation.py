#!/usr/bin/env python3
"""Independent replay checks for saved face-parsing masks and measured vertices."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np


def sha(data): return hashlib.sha256(data).hexdigest()


def decode_runs(runs, count):
    result = np.zeros(count, dtype=bool)
    end = 0
    for run in runs:
        start, length = run['start'], run['count']
        assert start >= end and length > 0 and start + length <= count
        result[start:start+length] = True
        end = start+length
    return result


def check(bundle, case, original=None):
    report = json.loads((case/'report.json').read_text())
    request_bytes = (case/'request.json').read_bytes()
    request = json.loads(request_bytes)
    manifest_bytes = (bundle/'manifest.json').read_bytes()
    manifest = json.loads(manifest_bytes)
    assert report['sourceManifestSHA256'] == sha(manifest_bytes)
    assert report['surfaceRequestFileSHA256'] == sha(request_bytes)
    assert report['confidenceMode'] == 'sum_posterior_over_included_labels'
    assert report['includedLabelIDs'] == [1,2,4,5,6,7,8,9,11,12]
    assert report['acceptedForHeadFitting'] is False and report['semanticAccuracyValidated'] is False
    frame = manifest['frames'][report['frameIndex']]
    assert frame['metadata']['id'] == report['frameID'] == request['frames'][0]['frameID']
    h,w = frame['metadata']['depthSize']['height'],frame['metadata']['depthSize']['width']
    labels_data=(case/'labels.u8').read_bytes();confidence_data=(case/'confidence.f32').read_bytes()
    assert sha(labels_data)==report['labelsSHA256'] and sha(confidence_data)==report['confidenceSHA256']
    labels=np.frombuffer(labels_data,np.uint8); confidence=np.frombuffer(confidence_data,'<f4')
    assert labels.size==confidence.size==h*w and np.all(labels<19)
    assert np.all(np.isfinite(confidence)) and np.all(confidence>=0) and np.all(confidence<=1.000001)
    depth_data=(bundle/frame['depth']['path']).read_bytes()
    assert sha(depth_data)==report['depthSHA256']==frame['depth']['sha256']
    depth=np.frombuffer(depth_data,'<f4')
    semantic=confidence>=report['confidenceThreshold']
    valid=np.isfinite(depth)&(depth>=.05)&(depth<=2)
    median=float(np.median(depth[semantic&valid]));assert median==report['medianFaceDepthMeters']
    expected=semantic&valid&(np.abs(depth-median)<.08)
    if frame.get('confidence'):
        levels=np.frombuffer((bundle/frame['confidence']['path']).read_bytes(),np.uint8)
        expected&=(levels>=1)&(levels<=2)
    mask=decode_runs(request['frames'][0]['mask']['includedRuns'],w*h)
    assert np.array_equal(mask,expected) and int(mask.sum())==report['includedPixels']
    assert int(semantic.sum())==report['semanticPixels']
    surface=json.loads((case/'surface.json').read_text())
    assert len(surface['frames'])==1 and not surface['completeHead'] and not surface['includesInferredAnatomy']
    positions={}
    for vertex in surface['vertices']:
        assert len(vertex['observations'])==1
        observation=vertex['observations'][0];assert observation['frameIndex']==0
        pixel=observation['depthPixelIndex']; assert mask[pixel] and pixel not in positions
        assert vertex['position']['z']==float(depth[pixel])
        positions[pixel]=vertex['position']
    edges={}
    for triangle in surface['triangles']:
        assert len(triangle)==3 and len(set(triangle))==3 and all(0<=i<len(positions) for i in triangle)
        for a,b in zip(triangle,triangle[1:]+triangle[:1]):
            key=tuple(sorted((a,b)));edges[key]=edges.get(key,0)+1
    assert max(edges.values())<=2
    result={'frameIndex':report['frameIndex'],'retainedPixels':int(mask.sum()),'vertices':len(positions),
            'triangles':len(surface['triangles']),'boundaryEdges':sum(n==1 for n in edges.values()),
            'nonmanifoldEdges':sum(n>2 for n in edges.values()),'everyVertexHasOriginalDepth':True,
            'retainedPixelsWithHairHatGlassesNeckOrClothingArgmax':int(np.count_nonzero(mask&np.isin(labels,[0,3,13,14,15,16,17,18])))}
    if original and original.exists():
        old=json.loads(original.read_text());same=0;removed=0
        for vertex in old['vertices']:
            pixel=vertex['observations'][0]['depthPixelIndex']
            if pixel in positions:
                assert positions[pixel]==vertex['position'];same+=1
            else:removed+=1
        result.update({'oldVertices':len(old['vertices']),'unchangedSharedVertices':same,'oldVerticesExcluded':removed,
                       'newlyRetainedMeasuredVertices':len(positions)-same})
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('bundle',type=Path);p.add_argument('output_root',type=Path)
    p.add_argument('--old-root',type=Path,default=Path('outputs/component-cleanup'));a=p.parse_args()
    results=[check(a.bundle,case,a.old_root/case.name/'surface.json') for case in sorted(a.output_root.iterdir()) if case.is_dir() and (case/'report.json').exists()]
    assert results
    report={'method':'independent_face_mask_replay_v1','cases':results,'passed':True,'physicalAccuracyVerified':False}
    (a.output_root/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
