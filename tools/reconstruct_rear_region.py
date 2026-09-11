#!/usr/bin/env python3
"""Replay a spatial crop into separate world-positioned depth patches.

This preserves unmerged observations. Camera poses are not head registration;
this preview must not be imported as an accepted head or scalp asset.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('bundle',type=Path); p.add_argument('request',type=Path); p.add_argument('output',type=Path)
    p.add_argument('--frames',type=int,default=12)
    p.add_argument('--inspector',type=Path,default=Path('.build/debug/capture-inspect'))
    a = p.parse_args()
    if not 2 <= a.frames <= 32: p.error('Choose 2 through 32 preview frames')
    a.output.mkdir(parents=True,exist_ok=False)
    def run(*args): subprocess.run([str(a.inspector),*map(str,args)],check=True)
    report_path = a.output/'masks.json'
    run('world-region-masks',a.bundle,a.request,report_path)
    report = json.loads(report_path.read_text()); manifest = json.loads((a.bundle/'manifest.json').read_text())
    by_id = {f['metadata']['id']:f for f in manifest['frames']}
    eligible = [f for f in report['frames'] if f['includedSamples'] >= 100]
    if len(eligible) < 2: raise ValueError('Insufficient tracked region observations')
    count = min(a.frames,len(eligible))
    selected = [eligible[round(i*(len(eligible)-1)/(count-1))] for i in range(count)]
    patches = []
    for index, f in enumerate(selected):
        root = a.output/str(index); root.mkdir()
        request = dict(schemaVersion=1,samplingStride=2,minimumConfidence=1,maximumEdgeMeters=.015,
                       fusionRadiusMeters=.0015,frames=[dict(captureID=manifest['id'],frameID=f['frameID'],mask=f['mask'])])
        # Match the mask's confidence policy when building the source patch.
        request['minimumConfidence'] = json.loads(a.request.read_text())['minimumConfidence']
        path = root/'request.json';path.write_text(json.dumps(request))
        run('surface',a.bundle.parent,path,root/'surface.json',root/'surface.ply')
        raw = (root/'surface.json').read_bytes(); surface = json.loads(raw)
        if surface['frames'][0]['frameSHA256'] != f['frameSHA256']: raise ValueError('Capture changed during replay')
        m = by_id[f['frameID']]['metadata']['worldFromOpticalCamera']['rowMajor']
        def apply(v,translate):
            q = [v[k] for k in 'xyz']
            return [sum(m[i*4+j]*q[j] for j in range(3))+(m[i*4+3] if translate else 0) for i in range(3)]
        patches.append(dict(frameID=f['frameID'],sourceSurfaceSHA256=hashlib.sha256(raw).hexdigest(),
                            positions=[apply(v['position'],True) for v in surface['vertices']],
                            normals=[apply(v['normal'],False) for v in surface['vertices']],triangles=surface['triangles']))
    result = dict(schemaVersion=1,method='unmerged_world_depth_patch_preview_v1',acceptedForFusion=False,
                  coordinateConvention='capture_arkit_world_meters',requestSHA256=report['requestSHA256'],patches=patches,
                  notes=['Unmerged views positioned by camera world poses; head movement remains uncompensated.',
                         'Spatial crop includes hair and may include neck, clips, bun or background. Not a scalp/head asset.',
                         'Preview frame subsampling does not establish coverage or physical accuracy.'])
    (a.output/'world-preview.json').write_text(json.dumps(result))
    print('Preserved',sum(len(f['positions']) for f in patches),'unmerged samples across',len(patches),'views')


if __name__ == '__main__': main()
