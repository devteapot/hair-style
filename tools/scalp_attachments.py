"""Replay canonical barycentric scalp bindings, including inferred normal offsets.

Matches HaircutValidator.attachment; these coordinates do not imply measured roots.
Canonical Swift preflight and final import remain authoritative.
"""
import numpy as np


def attachment_positions(scalp, bindings):
    vertices=np.asarray([[p[k] for k in ('x','y','z')] for p in scalp['vertices']],dtype=float)
    triangles=scalp['triangles']
    if vertices.ndim!=2 or vertices.shape[1]!=3 or not np.isfinite(vertices).all():
        raise ValueError('Invalid scalp vertices')
    roots=[]
    for binding in bindings:
        index=binding['triangleIndex'];weights=np.asarray(binding['barycentric'],dtype=float)
        offset=binding['normalOffsetMeters']
        if (type(index) is not int or not 0<=index<len(triangles) or weights.shape!=(3,)
                or not np.isfinite(weights).all() or np.any(weights<0) or np.any(weights>1)
                or abs(weights.sum()-1)>1e-8 or not np.isfinite(offset) or not 0<=offset<=.01):
            raise ValueError('Invalid scalp attachment')
        indices=triangles[index]
        if len(indices)!=3 or any(type(i) is not int or not 0<=i<len(vertices) for i in indices):
            raise ValueError('Invalid scalp triangle')
        triangle=vertices[indices];normal=np.cross(triangle[1]-triangle[0],triangle[2]-triangle[0])
        norm=np.linalg.norm(normal)
        if not np.isfinite(norm) or norm<=1e-10:raise ValueError('Degenerate scalp triangle')
        roots.append(weights@triangle+offset*normal/norm)
    return np.asarray(roots,dtype=float).reshape(-1,3)
