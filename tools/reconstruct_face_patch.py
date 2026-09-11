#!/usr/bin/env python3
"""Experimental single-view face patch from a Vision report and captured depth.

This convex-hull/depth-band mask is not validated semantic skin segmentation.
Run after building capture-inspect. Source captures are never modified.
"""
import argparse,array,json,math,statistics,subprocess,sys
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('bundle',type=Path)
parser.add_argument('landmarks',type=Path)
parser.add_argument('output',type=Path,help='New output directory')
parser.add_argument('--stride',type=int,choices=range(1,9),default=2,
                    help='Native depth sampling stride; use 1 to retain rear sensor resolution')
args=parser.parse_args()
root=args.bundle.resolve();m=json.loads((root/'manifest.json').read_text())
r=json.loads(args.landmarks.read_text())
if r['captureID'] != m['id'] or r['status'] != 'detected':
 raise ValueError('Landmark report must identify this capture and a detected face')
frame=next(f for f in m['frames'] if f['metadata']['id']==r['frameID'])
size=frame['metadata']['depthSize'];imageSize=frame['metadata']['imageSize']
if r['nativeImageSize'] != imageSize: raise ValueError('Landmark image dimensions do not match capture')
if frame['metadata']['depthRectification'] not in ('not_applied','arkit_aligned_scene_depth','synthetic_pinhole'):
 raise ValueError('Unknown image/depth alignment convention')
if min(size['width'],size['height'],imageSize['width'],imageSize['height'])<=0:
 raise ValueError('Invalid image/depth dimensions')
args.output.mkdir(parents=True,exist_ok=False)
points=[p for p in r['points'] if 'cameraPoint' in p]
if len(points)<7: raise ValueError('Too few landmarks with depth')
median=statistics.median(p['cameraPoint']['z'] for p in points)
xy=sorted(set((p['nativePixel']['x']*size['width']/imageSize['width'],
               p['nativePixel']['y']*size['height']/imageSize['height'])
              for p in points if abs(p['cameraPoint']['z']-median)<0.07))
if any(not math.isfinite(x) or not math.isfinite(y) for x,y in xy): raise ValueError('Invalid landmark coordinates')
def cross(o,a,b):return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
lo=[];hi=[]
for p in xy:
 while len(lo)>=2 and cross(lo[-2],lo[-1],p)<=0:lo.pop()
 lo.append(p)
for p in reversed(xy):
 while len(hi)>=2 and cross(hi[-2],hi[-1],p)<=0:hi.pop()
 hi.append(p)
hull=lo[:-1]+hi[:-1]
if len(hull)<3: raise ValueError('Landmarks do not enclose a usable face region')
w=size['width'];h=size['height']
if w*h>1_000_000: raise ValueError('Depth processing limit exceeded')
depthPath=(root/frame['depth']['path']).resolve()
depthPath.relative_to(root)
if depthPath.stat().st_size != w*h*4: raise ValueError('Depth payload size mismatch')
depth=array.array('f');depth.frombytes(depthPath.read_bytes())
if sys.byteorder!='little': depth.byteswap()
if len(depth)!=w*h: raise ValueError('Depth dimensions do not match payload')
mask=[]
for y in range(h):
 for x in range(w):
  z=depth[y*w+x]
  inside=all(cross(a,b,(x,y))>=0 for a,b in zip(hull,hull[1:]+hull[:1]))
  mask.append(inside and math.isfinite(z) and abs(z-median)<0.08)
runs=[];i=0
while i<len(mask):
 if not mask[i]:i+=1;continue
 start=i
 while i<len(mask) and mask[i]:i+=1
 runs.append({'start':start,'count':i-start})
request={'schemaVersion':1,'samplingStride':args.stride,'minimumConfidence':1,'maximumEdgeMeters':0.01,'fusionRadiusMeters':0.0015,'frames':[{'captureID':m['id'],'frameID':frame['metadata']['id'],'mask':{'size':size,'provenance':'model_inferred','method':'Vision landmark convex hull mapped from native image to depth dimensions and +/-80mm depth band; provisional single-view face patch; not semantic skin segmentation','includedRuns':runs}}]}
requestPath=args.output/'request.json';requestPath.write_text(json.dumps(request,indent=2))
p=subprocess.run([str(Path(__file__).resolve().parents[1]/'.build/debug/capture-inspect'),'surface',str(root.parent),str(requestPath),str(args.output/'surface.json'),str(args.output/'surface.ply')],capture_output=True,text=True,check=True)
print(p.stdout,p.stderr);print('includedPixels',sum(mask),'medianDepthMeters',median)
