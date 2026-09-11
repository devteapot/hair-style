#!/usr/bin/env python3
"""Create a review-only scalp candidate from a single-frame face patch and landmarks.

Landmark selection is inferred. No hair, bun or rear silhouette is used as skull.
"""
import argparse,json,subprocess
from pathlib import Path
import numpy as np


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('surface',type=Path);p.add_argument('landmarks',type=Path)
    p.add_argument('subject_session_id');p.add_argument('output',type=Path)
    args=p.parse_args();surface=json.loads(args.surface.read_text());landmarks=json.loads(args.landmarks.read_text())
    if len(surface['frames'])!=1 or surface['frames'][0]['frameSHA256']!=landmarks['frameSHA256']:
        raise ValueError('Landmarks and single-frame patch must share source frame')
    if surface['frames'][0]['referenceFromCamera']['rowMajor']!=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]:
        raise ValueError('Expected original camera coordinates')
    def vector(point):return [point[k] for k in ('x','y','z')]
    def region(name):
        pts=[vector(p['cameraPoint']) for p in landmarks['points'] if p['region']==name and 'cameraPoint' in p]
        if not pts: raise ValueError(f'Missing {name}')
        return np.array(pts)
    eyes=[region(name).mean(axis=0) for name in ['vision_left_pupil','vision_right_pupil']]
    midpoint=(eyes[0]+eyes[1])/2
    up=midpoint-region('vision_outer_lips').mean(axis=0);up/=np.linalg.norm(up)
    x=eyes[0]-eyes[1];x/=np.linalg.norm(x)
    anterior=np.cross(x,up);anterior/=np.linalg.norm(anterior)
    nose=region('vision_nose')
    # Choose anatomical parity with the anterior nose check, not presentation mirroring.
    if (nose.mean(axis=0)-midpoint)@anterior<0:eyes.reverse();x=-x;anterior=-anterior
    points=np.array([vector(v['position']) for v in surface['vertices']])
    used=sorted(set(i for t in surface['triangles'] for i in t));used_points=points[used]
    def nearest(point):return used[int(np.linalg.norm(used_points-point,axis=1).argmin())]
    left,right=map(nearest,eyes)
    relative=points-midpoint
    candidates=[i for i in used if abs(relative[i]@x)<.012 and .012<relative[i]@up<.12]
    if len(candidates)<10:raise ValueError('Insufficient central superior face geometry')
    candidates.sort(key=lambda i:relative[i]@up)
    superior=candidates[int(.85*(len(candidates)-1))]
    nose_point=nose[int(((nose-midpoint)@anterior).argmax())]
    args.output.mkdir(parents=True,exist_ok=False)
    cli=Path(__file__).resolve().parents[1]/'.build/debug/capture-inspect'
    digest=subprocess.check_output([str(cli),'surface-hash',str(args.surface)],text=True).strip()
    selection=dict(schemaVersion=1,surfaceSHA256=digest,anatomicalLeftEyeVertex=left,anatomicalRightEyeVertex=right,
        superiorVertex=superior,anteriorVertex=nearest(nose_point),
        method='Inferred nearest depth-backed pupil/nose vertices; upper central face selected along eye-to-mouth axis. Requires anatomical review.')
    selection_path=args.output/'selection.json';selection_path.write_text(json.dumps(selection,indent=2))
    envelope_path=args.output/'envelope.json'
    subprocess.run([str(cli),'scalp-suggest',str(args.surface),str(selection_path),str(envelope_path)],check=True)
    request=dict(schemaVersion=1,selection=selection,subjectSessionID=args.subject_session_id,scalpID='scalp-candidate',revision=1,
                 envelope=json.loads(envelope_path.read_text()))
    request_path=args.output/'request.json';request_path.write_text(json.dumps(request,indent=2))
    subprocess.run([str(cli),'scalp-complete',str(args.surface),str(request_path),str(args.output/'result.json')],check=True)
    (args.output/'scalp-review.json').write_text(json.dumps(dict(schemaVersion=1,source=surface,revisions=[request])))


if __name__=='__main__':main()
