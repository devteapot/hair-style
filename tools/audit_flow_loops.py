#!/usr/bin/env python3
"""Compare two-edge RGB/depth chains against separately matched endpoint pairs."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import struct


def compose(a, b):
    return [sum(a[r*4+k]*b[k*4+c] for k in range(4)) for r in range(4) for c in range(4)]


def discrepancy(a, b):
    cosine=(sum(a[r*4+c]*b[r*4+c] for r in range(3) for c in range(3))-1)/2
    return dict(rotationDegrees=math.degrees(math.acos(max(-1,min(1,cosine)))),
                sourceCameraOriginDisplacementMeters=math.sqrt(sum((a[r*4+3]-b[r*4+3])**2 for r in range(3))))


def surface_discrepancy(bundle, request, a, b):
    manifest=json.loads((bundle/'manifest.json').read_text())
    frame=next(f for f in manifest['frames'] if f['metadata']['id']==request['sourceFrameID'])
    metadata=frame['metadata']; size=metadata['depthSize']; mask=request['sourceMask']
    if metadata['depthRectification']!='arkit_aligned_scene_depth' or mask['size']!=size:
        raise ValueError('Expected aligned depth and matching mask')
    def payload(evidence):
        path=(bundle/evidence['path']).resolve()
        if not path.is_relative_to(bundle.resolve()): raise ValueError('Escaping payload path')
        data=path.read_bytes()
        if len(data)!=evidence['byteCount'] or hashlib.sha256(data).hexdigest()!=evidence['sha256']:
            raise ValueError('Changed capture payload')
        return data
    depth=payload(frame['depth']); confidence=payload(frame['confidence'])
    width=size['width'];height=size['height'];k=metadata['intrinsics'];ref=k['referenceSize']
    if len(depth)!=width*height*4 or len(confidence)!=width*height: raise ValueError('Invalid raster length')
    distances=[]
    for run in mask['includedRuns']:
        if run['start']<0 or run['start']+run['count']>width*height: raise ValueError('Invalid mask run')
        for i in range(run['start'],run['start']+run['count']):
            z=struct.unpack_from('<f',depth,i*4)[0]
            if not math.isfinite(z) or not .05<=z<=5 or confidence[i]<request['minimumConfidence']: continue
            p=[((i%width)*ref['width']/width-k['cx'])*z/k['fx'],
               ((i//width)*ref['height']/height-k['cy'])*z/k['fy'],z,1]
            distances.append(math.sqrt(sum(sum((a[r*4+c]-b[r*4+c])*p[c] for c in range(4))**2 for r in range(3))))
    distances.sort()
    return dict(sampleCount=len(distances),medianMeters=distances[len(distances)//2] if distances else None,
                p95Meters=distances[max(0,math.ceil(.95*len(distances))-1)] if distances else None,
                maximumMeters=max(distances) if distances else None)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle',type=Path);parser.add_argument('graph',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();summary_path=args.graph/'summary.json'
    summary=json.loads(summary_path.read_text())
    if summary['status']!='completed': raise ValueError('Wait for completed graph evaluation')
    if hashlib.sha256((args.bundle/'manifest.json').read_bytes()).hexdigest()!=summary['manifestSHA256']:
        raise ValueError('Graph belongs to different capture revision')
    args.output.mkdir(parents=True,exist_ok=False)
    cli=Path(__file__).resolve().parents[1]/'.build/debug/capture-inspect'
    edges={(e['sourceIndex'],e['targetIndex']):e for e in summary['edges'] if e['localAccepted']}
    results=[]
    for i,j in sorted(edges):
        if (j,j+1) not in edges: continue
        k=j+1
        def read_edge(a,b):
            entry=edges[(a,b)]; path=args.graph/entry['report']
            if hashlib.sha256(path.read_bytes()).hexdigest()!=entry['reportSHA256']: raise ValueError('Changed edge report')
            return json.loads(path.read_text())['registration']['registration']['targetFromSource']['rowMajor']
        chain=compose(read_edge(j,k),read_edge(i,j))
        first=json.loads((args.graph/f'{i}-{j}-request.json').read_text())
        second=json.loads((args.graph/f'{j}-{k}-request.json').read_text())
        request={**first,'targetFrameID':second['targetFrameID'],'targetMask':second['targetMask']}
        request_path=args.output/f'{i}-{k}-request.json';report_path=args.output/f'{i}-{k}-report.json'
        request_path.write_text(json.dumps(request))
        process=subprocess.run([str(cli),'flow-register',str(args.bundle),str(request_path),str(report_path)],capture_output=True,text=True)
        report=json.loads(report_path.read_text()) if process.returncode==0 and report_path.exists() else {}
        reg=report.get('registration',{}).get('registration',{})
        accepted=reg.get('accepted',False)
        result=dict(frameIndices=[i,j,k],directLocalAccepted=accepted,chainTargetFromSource=chain,
                    comparison=discrepancy(chain,reg['targetFromSource']['rowMajor']) if accepted else None,
                    failureReason=report.get('failureReason') or (process.stderr.strip() if process.returncode else None),
                    reportSHA256=hashlib.sha256(report_path.read_bytes()).hexdigest() if report else None)
        if accepted:
            result['observedSurfaceDiscrepancy']=surface_discrepancy(args.bundle,request,chain,reg['targetFromSource']['rowMajor'])
        results.append(result)
        print(f'{i}-{j}-{k}: direct {"pass" if accepted else "failed"}',flush=True)
    output=dict(schemaVersion=1,graphSHA256=hashlib.sha256(summary_path.read_bytes()).hexdigest(),loops=results,
                acceptedForFullHead=False,notes=['Direct endpoint matches are not used to fit the chain.',
                'Shared sensor and image errors remain; this is consistency, not physical accuracy.',
                'Translation discrepancy is evaluated at source camera origin, not an anatomical surface.',
                'Failed direct fits are not evidence that a chain is correct or incorrect.'])
    (args.output/'summary.json').write_text(json.dumps(output,indent=2)+'\n')


if __name__=='__main__':main()
