#!/usr/bin/env python3
"""Compare selected research guides to the actual open template mesh, without moving them."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from haar_decode_metal import read_obj
from propose_model_mapping import nearest_triangle


def inspect(source_path, mesh_path, identities):
    source = json.loads(source_path.read_text())
    vertices, faces = read_obj(mesh_path); triangles = vertices[faces]
    normals = np.cross(triangles[:,1]-triangles[:,0], triangles[:,2]-triangles[:,0])
    normals /= np.linalg.norm(normals, axis=1)[:,None]
    edges = np.concatenate([faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]])
    _, counts = np.unique(np.sort(edges,axis=1),axis=0,return_counts=True)
    guides = {guide['id']:guide for guide in source['strands']}
    records = []
    for identity in identities:
        points = np.asarray(guides[identity]['points'],dtype=float)
        if points.shape != (100,3) or not np.isfinite(points).all():
            raise ValueError('Invalid ordered guide')
        samples = []
        for index, p in enumerate(points):
            triangle, bary, distance = nearest_triangle(p, triangles)
            closest = bary@triangles[triangle]
            samples.append(dict(pointIndex=index, triangle=triangle, distanceSourceUnits=distance,
                orientedNormalOffsetSourceUnits=float((p-closest)@normals[triangle]),
                closestInTriangleInterior=bool(np.min(bary)>1e-8)))
        intersections=[]
        # Moller–Trumbore segment/triangle intersection, double-sided; root/tip endpoint hits excluded.
        e1=triangles[:,1]-triangles[:,0]; e2=triangles[:,2]-triangles[:,0]
        for index, (start,end) in enumerate(zip(points,points[1:])):
            direction=end-start; h=np.cross(direction,e2); determinant=np.einsum('ij,ij->i',e1,h)
            valid=np.abs(determinant)>1e-14
            inverse=np.zeros_like(determinant);inverse[valid]=1/determinant[valid]
            s=start-triangles[:,0];u=inverse*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1)
            v=inverse*(q@direction);t=inverse*np.einsum('ij,ij->i',e2,q)
            hit=valid&(u>=0)&(v>=0)&(u+v<=1)&(t>1e-8)&(t<1-1e-8)
            for triangle in np.flatnonzero(hit):
                intersections.append(dict(segment=index,triangle=int(triangle),fraction=float(t[triangle])))
        records.append(dict(guideID=identity,samples=samples,segmentIntersections=intersections,
            minimumOrientedOffsetSourceUnits=min(s['orientedNormalOffsetSourceUnits'] for s in samples),
            rootDistanceSourceUnits=samples[0]['distanceSourceUnits']))
    return dict(method='template_closest_surface_and_segment_intersections_v1',
        sourceSHA256=hashlib.sha256(source_path.read_bytes()).hexdigest(),
        meshSHA256=hashlib.sha256(mesh_path.read_bytes()).hexdigest(),
        meshVertices=len(vertices),meshTriangles=len(faces),boundaryEdges=int(np.sum(counts==1)),
        nonmanifoldEdges=int(np.sum(counts>2)),guides=records,
        physicalUnitsVerified=False,closedVolumeClassification=False,
        notes=['Original template coordinates; no personal mapping, trimming or envelope correction applied.',
               'Open mesh: oriented local offsets are not a global inside/outside classification.',
               'A segment intersection demonstrates a crossing of this template surface, not physical scalp anatomy.'])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path);parser.add_argument('mesh',type=Path);parser.add_argument('output',type=Path)
    parser.add_argument('guides',nargs='+');args=parser.parse_args()
    report=inspect(args.source,args.mesh,args.guides)
    with args.output.open('x') as stream:json.dump(report,stream,indent=2);stream.write('\n')
    print(json.dumps({k:v for k,v in report.items() if k!='guides'}))
    for guide in report['guides']:
        print(guide['guideID'],'intersections',len(guide['segmentIntersections']),
              'minimum oriented offset',guide['minimumOrientedOffsetSourceUnits'])


if __name__=='__main__':main()
