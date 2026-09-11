#!/usr/bin/env python3
"""Localize exact curve conflicts within surface topology without removing data."""
import argparse
from collections import defaultdict, deque
import hashlib
import json
from pathlib import Path
import subprocess
import numpy as np


def topology(triangles):
    edges=defaultdict(list)
    for i,tri in enumerate(triangles):
        if len(tri)!=3 or len(set(tri))!=3:raise ValueError('Invalid triangle')
        for a,b in zip(tri,(tri[1],tri[2],tri[0])):
            edges[tuple(sorted((a,b)))].append((i,a<b))
    neighbors=[set() for _ in triangles];boundary=set();winding=0
    for entries in edges.values():
        if len(entries)==1:boundary.add(entries[0][0])
        if len(entries)==2 and entries[0][1]==entries[1][1]:winding+=1
        for i,_ in entries:neighbors[i].update(j for j,_ in entries if j!=i)
    component=[-1]*len(triangles);sizes=[]
    for start in range(len(triangles)):
        if component[start]>=0:continue
        index=len(sizes);queue=[start];component[start]=index;size=0
        while queue:
            i=queue.pop();size+=1
            for j in neighbors[i]:
                if component[j]<0:component[j]=index;queue.append(j)
        sizes.append(size)
    hops=[None]*len(triangles);queue=deque(sorted(boundary))
    for i in boundary:hops[i]=0
    while queue:
        i=queue.popleft()
        for j in neighbors[i]:
            if hops[j] is None:hops[j]=hops[i]+1;queue.append(j)
    return dict(component=component,componentTriangleCounts=sizes,triangleHopsToOpenEdge=hops,
        boundaryEdges=sum(len(e)==1 for e in edges.values()),
        nonmanifoldEdges=sum(len(e)>2 for e in edges.values()),inconsistentWindingEdges=winding)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('input','haircut','anatomy','clearance','output'):parser.add_argument(name,type=Path)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    replay=args.output/'clearance-replay.json';cli=Path(__file__).resolve().parents[1]/'.build/debug/capture-inspect'
    result=subprocess.run([str(cli),'hair-clearance',str(args.input),str(args.haircut),str(args.anatomy),str(replay)],capture_output=True,text=True,timeout=120)
    report=json.loads(args.clearance.read_text())
    if result.returncode not in (0,2) or not replay.exists() or json.loads(replay.read_text())!=report:raise ValueError('Exact clearance replay mismatch')
    anatomy=json.loads(args.anatomy.read_text());hair=json.loads(args.haircut.read_text());guides={g['id']:g for g in hair['guides']}
    surfaces={};summary={};xyz=lambda p:[p[k] for k in ('x','y','z')]
    for surface in anatomy['surfaces']:
        info=topology(surface['triangles']);surfaces[surface['region']]=(surface,info)
        summary[surface['region']]={k:v for k,v in info.items() if k not in ('component','triangleHopsToOpenEdge')}
        summary[surface['region']]['triangleCount']=len(surface['triangles'])
    rows=[]
    for v in report['violations']:
        surface,info=surfaces[v['region']];index=v['triangleIndex'];tri=np.array([xyz(surface['vertices'][j]) for j in surface['triangles'][index]])
        points=np.array([xyz(p) for p in guides[v['guideID']]['points']]);lengths=np.linalg.norm(np.diff(points,axis=0),axis=1);segment=v['segmentIndex']
        rows.append(dict(guideID=v['guideID'],segmentIndex=segment,region=v['region'],triangleIndex=index,
            segmentStartArcLengthMeters=float(lengths[:segment].sum()),segmentEndArcLengthMeters=float(lengths[:segment+1].sum()),
            triangleAreaSquareMeters=float(np.linalg.norm(np.cross(tri[1]-tri[0],tri[2]-tri[0]))/2),
            triangleCentroidMeters=tri.mean(0).tolist(),triangleHopsToOpenEdge=info['triangleHopsToOpenEdge'][index],
            componentTriangleCount=info['componentTriangleCounts'][info['component'][index]],
            reportedDistanceMeters=v['distanceMeters'],requiredDistanceMeters=v['requiredDistanceMeters']))
    output=dict(method='curve_conflict_surface_topology_v1',filesSHA256={name:hashlib.sha256(getattr(args,name).read_bytes()).hexdigest() for name in ('input','haircut','anatomy','clearance')},
        canonicalClearanceReplayed=True,surfaces=summary,conflicts=rows,physicalFitVerified=False,
        limitations=['Topology does not establish sensor accuracy or identify tissue.','Open edges can be legitimate capture boundaries; no triangles or conflicts were removed.','A reported triangle is one witness for the segment, not every nearby surface triangle.'])
    (args.output/'report.json').write_text(json.dumps(output,indent=2)+'\n')
    print(json.dumps(dict(conflictCount=len(rows),uniqueWitnessTriangles=len(set((r['region'],r['triangleIndex']) for r in rows)),surfaceSummary=summary),indent=2))


if __name__=='__main__':main()
