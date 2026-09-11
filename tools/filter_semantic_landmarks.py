#!/usr/bin/env python3
"""Research semantic compatibility filter; not a visibility or anatomy guarantee."""
import argparse,hashlib,json
from pathlib import Path
import numpy as np


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('bundle','selection','source_case','target_case','output'):p.add_argument(name,type=Path)
    a=p.parse_args();selection=json.loads(a.selection.read_text());manifest=json.loads((a.bundle/'manifest.json').read_text());labels={}
    for side,case in [('source',a.source_case),('target',a.target_case)]:
        report=json.loads((case/'report.json').read_text());raw=(case/'labels.u8').read_bytes()
        assert report['labelsSHA256']==hashlib.sha256(raw).hexdigest()
        assert report['captureID']==manifest['id'] and report['frameID']==selection[side+'FrameID']
        frame=next(f for f in manifest['frames'] if f['metadata']['id']==report['frameID']);m=frame['metadata']
        assert m['imageSize']==m['depthSize']==report['depthSize']
        assert not m['mirrored'] and m['pixelOrientation']=='sensor_native'
        labels[side]=np.frombuffer(raw,np.uint8).reshape(m['depthSize']['height'],m['depthSize']['width'])
    filtered={k:v for k,v in selection.items() if k not in ['fitPairs','validationPairs']};audit=[]
    for role in ['fitPairs','validationPairs']:
        filtered[role]=[]
        for pair in selection[role]:
            assert pair['id'].startswith(('vision_nose:','vision_left_eye:','vision_right_eye:'))
            wanted=[2] if pair['id'].startswith('vision_nose:') else [4,5]
            compatible=[]
            for side in ['source','target']:
                x,y=[int(np.floor(pair[side][k]+.5)) for k in ['x','y']];raster=labels[side];h,w=raster.shape
                assert 0<=x<w and 0<=y<h
                compatible.append(bool(np.isin(raster[max(0,y-3):min(h,y+4),max(0,x-3):min(w,x+4)],wanted).any()))
            audit.append({'id':pair['id'],'role':role,'sourceCompatible':compatible[0],'targetCompatible':compatible[1],'retained':all(compatible)})
            if all(compatible):filtered[role].append(pair)
    a.output.mkdir(parents=True,exist_ok=True)
    (a.output/'selection.json').write_text(json.dumps(filtered,indent=2)+'\n')
    (a.output/'audit.json').write_text(json.dumps({'method':'eye_nose_label_neighborhood_v1','radiusNativePixels':3,'matches':audit,
        'selectionFileSHA256':hashlib.sha256(a.selection.read_bytes()).hexdigest(),
        'notes':['Compatibility uses model labels in a 7 by 7 neighborhood; it does not prove visibility or correspondence.',
                 'Fitting and validation retain their original assignments. Excluded landmarks remain in this audit.',
                 'Only equal native RGB/depth raster sizes are supported by this research filter.']},indent=2)+'\n')


if __name__=='__main__':main()
