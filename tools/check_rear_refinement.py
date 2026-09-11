#!/usr/bin/env python3
"""Numerical checks; no sensor accuracy claims."""
import numpy as np
from refine_rear_views import solve, rotation
from geometry_alignment_experiment import transform

rng=np.random.default_rng(771)
directions=rng.normal(size=(650,3));directions/=np.linalg.norm(directions,axis=1)[:,None]
axes=np.array([.08,.13,.10]);points=directions*axes
normals=points/(axes*axes);normals/=np.linalg.norm(normals,axis=1)[:,None]
a=np.eye(4);a[:3,:3]=rotation(np.array([.012,-.006,.007]));a[:3,3]=[.002,-.001,.001]
b=np.eye(4);b[:3,:3]=rotation(np.array([-.009,.008,.005]));b[:3,3]=[-.001,.002,-.001]
report,corrections=solve([points,transform(points,a),transform(points,b)],
                       [normals,normals@a[:3,:3].T,normals@b[:3,:3].T])
assert report['stopped']=='converged',report['stopped']
assert not report['acceptedForFusion']
for supplied,correction in zip([np.eye(4),a,b],corrections):
    assert np.max(np.linalg.norm(transform(transform(points,supplied),correction)-points,axis=1))<1e-5
    assert np.isclose(np.linalg.det(correction[:3,:3]),1)
# Planes leave tangent translation and yaw unconstrained; damping must not conceal this.
xy=rng.uniform(-.05,.05,size=(300,2));plane=np.column_stack((xy,np.zeros(300)))
n=np.tile([0.,0.,1.],(300,1))
r,c=solve([plane,plane+[0,0,.002]],[n,n])
assert r['stopped']=='unobservable_geometry',r['stopped']
assert not r['acceptedForFusion']
r,c=solve([points,points+[1,0,0]],[normals,normals])
assert r['stopped']=='disconnected_overlap_graph' and c is None
print('Rear refinement checks passed: known rigid recovery, proper rotations, planar degeneracy, disconnected overlap.')
