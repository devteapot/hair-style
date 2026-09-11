#!/usr/bin/env python3
"""Compare actual decoder scalp frames with inferred personal attachment normals.

No measured growth direction or anatomical correspondence is asserted.
"""
import argparse
import json
from pathlib import Path
import subprocess
import numpy as np
from haar_decode_metal import setup
from haar_text_metal import sha256


def unit(x):
    length=np.linalg.norm(x,axis=-1,keepdims=True)
    if not np.isfinite(x).all() or np.any(length<1e-12):raise ValueError('Undefined direction')
    return x/length


def transformed_surface_normals(basis, scale):
    """Normals of the local XY plane after a general frame and axis scale."""
    basis=np.asarray(basis,dtype=float);scale=np.asarray(scale,dtype=float)
    if (basis.ndim!=3 or basis.shape[1:]!=(3,3) or scale.shape!=(3,)
            or not np.isfinite(basis).all() or not np.isfinite(scale).all()
            or np.any(scale<=0) or np.any(np.linalg.det(basis)<=1e-12)):
        raise ValueError('Invalid or reflected normal transform')
    return unit(np.linalg.inv(basis)[:,2,:]/scale)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('source','input','mapping','haircut','clearance','anatomy','output'):p.add_argument(name,type=Path)
    args=p.parse_args()
    source,inp,mapping,hair,clearance=[json.loads(getattr(args,n).read_text()) for n in ('source','input','mapping','haircut','clearance')]
    if sha256(args.source)!=mapping['sourceArtifactSHA256']:raise ValueError('Source hash mismatch')
    ids=[g['id'] for g in source['strands']]
    if ids!=[g['id'] for g in hair['guides']] or ids!=[m['guideID'] for m in mapping['mappings']]:raise ValueError('Guide order mismatch')
    args.output.mkdir(parents=True,exist_ok=False)
    replay=args.output/'clearance-replay.json'
    cli=Path(__file__).resolve().parents[1]/'.build/debug/capture-inspect'
    checked=subprocess.run([str(cli),'hair-clearance',str(args.input),str(args.haircut),str(args.anatomy),str(replay)],capture_output=True,text=True,timeout=120)
    if checked.returncode not in (0,2) or not replay.exists() or json.loads(replay.read_text())!=clearance:
        raise ValueError('Clearance must replay exactly with the supplied anatomy snapshot')
    h=setup(Path('.research/HAAR').resolve(),Path('.research/metal-assets/scalp'),Path('.research/metal-assets/strand_ckpt.pth'),42)
    basis=h.small_R_inv[:,0].numpy().astype(float)
    roots=np.array([s['points'][0] for s in source['strands']])
    root_error=float(np.abs(roots-h.small_origins[:,0].numpy()).max())
    if root_error>2e-5:raise ValueError('Template root order does not replay')
    orthogonality=float(np.abs(basis.transpose(0,2,1)@basis-np.eye(3)).max())
    determinants=np.linalg.det(basis)
    if not np.isfinite(basis).all() or np.any(determinants<=1e-12):raise ValueError('Singular or reflected source frame')
    xyz=lambda v:np.array([v[k] for k in ('x','y','z')],dtype=float)
    scale=xyz(mapping['metersPerSourceUnit'])
    if np.any(scale<=0):raise ValueError('Requires positive affine scales')
    # Surface normals transform by inverse transpose, not by the point scale.
    # The upstream float32 frame is not assumed exactly orthonormal. The
    # normal is the third row of global-to-local, not column 3 of its inverse.
    source_normals=transformed_surface_normals(basis,scale)
    transformed_tangents=basis[:,:,:2]*scale[None,:,None]
    cross_normals=unit(np.cross(transformed_tangents[:,:,0],transformed_tangents[:,:,1]))
    normal_cross_error=float(np.abs(cross_normals-source_normals).max())
    if normal_cross_error>1e-10:raise ValueError('Inverse-transpose normal disagrees with transformed tangent cross product')
    envelope=mapping['envelopeGuard']['envelope'];center=xyz(envelope['center']);radii=xyz(envelope['radii'])
    vertices=np.array([xyz(v) for v in inp['scalp']['vertices']]);triangles=vertices[np.array(inp['scalp']['triangles'])]
    conflicts={v['guideID'] for v in clearance['violations']}
    details=[]
    for i,g in enumerate(hair['guides']):
        points=np.array([xyz(v) for v in g['points']]);target=unit((points[0]-center)/(radii*radii))
        tri=triangles[g['root']['triangleIndex']];normal=unit(np.cross(tri[1]-tri[0],tri[2]-tri[0]))
        tangent=unit(points[1]-points[0]);original_tangent=unit((np.array(source['strands'][i]['points'][1])-roots[i])*scale)
        angle=lambda a,b:float(np.degrees(np.arccos(np.clip(np.dot(a,b),-1,1))))
        details.append(dict(guideID=g['id'],hasFaceConflict=g['id'] in conflicts,
            sourceToInferredNormalDegrees=angle(source_normals[i],target),
            triangleToInferredNormalDegrees=angle(normal,target),
            sourceTangentToSourceNormalDegrees=angle(original_tangent,source_normals[i]),
            currentTangentToInferredNormalDegrees=angle(tangent,target),
            mappedSourceSurfaceNormal=source_normals[i].tolist(),inferredTargetNormal=target.tolist()))
    groups={}
    for name,items in [('conflicting',[d for d in details if d['hasFaceConflict']]),('other',[d for d in details if not d['hasFaceConflict']])]:
        angles=[d['sourceToInferredNormalDegrees'] for d in items]
        groups[name]=dict(count=len(items),medianNormalMismatchDegrees=float(np.median(angles)) if angles else None,maximumNormalMismatchDegrees=max(angles,default=None))
    result=dict(method='actual_template_to_inferred_root_frame_audit_v1',inputHashes={n:sha256(getattr(args,n)) for n in ('source','input','mapping','haircut','clearance','anatomy')},
        scriptSHA256=sha256(Path(__file__)),templateRootMaximumError=root_error,sourceFrameOrthogonalityMaximumError=orthogonality,
        sourceFrameDeterminantRange=[float(determinants.min()),float(determinants.max())],groups=groups,guides=details,
        transformedTangentCrossNormalMaximumError=normal_cross_error,
        measuredGrowthDirections=False,anatomicalCorrespondenceVerified=False,physicalFitVerified=False)
    (args.output/'report.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='guides'},indent=2))


if __name__=='__main__':main()
