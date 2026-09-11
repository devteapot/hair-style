#!/usr/bin/env python3
"""Replay recorded registration residuals from original native depth with NumPy.

Checks arithmetic and acceptance decisions, not anatomical correspondence or
physical accuracy. Does not refit or authorize a failed transform for fusion.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np


def sample(bundle, frame_id, pixels, minimum):
    manifest = json.loads((bundle/'manifest.json').read_text())
    assert manifest['status'] == 'completed'
    frame = next(f for f in manifest['frames'] if f['metadata']['id'] == frame_id)
    m = frame['metadata']; k = m['intrinsics']
    assert not m['mirrored'] and m['pixelOrientation'] == 'sensor_native'
    assert abs(m['imageTimestamp']-m['depthTimestamp']) <= .01
    def payload(record):
        path = (bundle/record['path']).resolve(); path.relative_to(bundle.resolve())
        data = path.read_bytes()
        assert len(data) == record['byteCount'] and hashlib.sha256(data).hexdigest() == record['sha256']
        return data
    depth = np.frombuffer(payload(frame['depth']), '<f4')
    image_size = np.array([m['imageSize'][x] for x in ('width','height')])
    depth_size = np.array([m['depthSize'][x] for x in ('width','height')])
    assert len(depth) == np.prod(depth_size)
    xy = np.array([[p['x'],p['y']] for p in pixels])
    assert np.all(np.isfinite(xy)) and np.all(xy >= 0) and np.all(xy < image_size)
    pixel = np.minimum(np.floor(xy*depth_size/image_size+.5).astype(int),depth_size-1)
    index = pixel[:,1]*depth_size[0]+pixel[:,0]
    z = depth[index].astype(float)
    assert np.all(np.isfinite(z)) and np.all((z>=.05)&(z<=2))
    if frame.get('confidence'):
        confidence = np.frombuffer(payload(frame['confidence']), np.uint8)[index]
        assert np.all((confidence>=minimum)&(confidence<=2))
    size = np.array([k['referenceSize'][x] for x in ('width','height')])
    xy = xy*size/image_size
    if m['depthRectification'] == 'not_applied':
        lens = m['lensCalibration']; center = np.array([lens['centerX'],lens['centerY']])
        table = np.array(lens['inverseLookupTable']); offset = xy-center
        radius = np.linalg.norm(offset,axis=1)
        maximum = np.linalg.norm(np.maximum(center,size-center))
        magnification = np.interp(radius/maximum*(len(table)-1),np.arange(len(table)),table)
        xy = center+offset*(1+magnification[:,None])
    else:
        assert m['depthRectification'] in ('synthetic_pinhole','arkit_aligned_scene_depth')
    return np.column_stack(((xy[:,0]-k['cx'])*z/k['fx'],(xy[:,1]-k['cy'])*z/k['fy'],z))


def check(source, target, selection_path, report_path):
    selection = json.loads(selection_path.read_text()); report = json.loads(report_path.read_text())
    r = report['registration']; matrix = np.array(r['targetFromSource']['rowMajor']).reshape(4,4)
    assert np.allclose(matrix[:3,:3].T@matrix[:3,:3],np.eye(3),atol=1e-10)
    assert abs(np.linalg.det(matrix[:3,:3])-1)<1e-10
    errors = {}
    for role, residual_key in [('fitPairs','fittingResiduals'),('validationPairs','validationResiduals')]:
        pairs = selection[role]
        a = sample(source,selection['sourceFrameID'],[p['source'] for p in pairs],report['minimumConfidence'])
        b = sample(target,selection['targetFrameID'],[p['target'] for p in pairs],report['minimumConfidence'])
        residual = np.linalg.norm(a@matrix[:3,:3].T+matrix[:3,3]-b,axis=1)
        declared = {x['id']:x['meters'] for x in r[residual_key]}
        assert set(declared) == {p['id'] for p in pairs}
        assert np.max(np.abs(residual-np.array([declared[p['id']] for p in pairs])))<1e-10
        errors[role] = residual
    held = errors['validationPairs']; median = float(np.median(held))
    p95 = float(np.sort(held)[int(np.ceil(.95*len(held)))-1])
    assert abs(median-r['validationMedianMeters'])<1e-10 and abs(p95-r['validationP95Meters'])<1e-10
    gates = r['thresholds']
    expected = median<=gates['validationMedianMeters'] and p95<=gates['validationP95Meters']
    assert expected == r['accepted']
    return {'residualsReplayed':sum(map(len,errors.values())), 'accepted':expected,
            'validationMedianMeters':median,'validationP95Meters':p95,
            'reportSHA256':hashlib.sha256(report_path.read_bytes()).hexdigest(),
            'physicalAccuracyVerified':False}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('source','target','selection','report','output'): p.add_argument(name,type=Path)
    a = p.parse_args(); result = check(a.source,a.target,a.selection,a.report)
    a.output.write_text(json.dumps(result,indent=2)+'\n'); print(json.dumps(result,indent=2))
