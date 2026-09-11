"""Conservative local triangle-separating planes for a fixed hair root.

These planes describe supplied triangles, not anatomical inside/outside. They
can exclude valid paths around triangle edges; exact clearance is still required.
"""
import numpy as np


def departure_planes(root, triangles, required, radius=.012):
    root=np.asarray(root,dtype=float);triangles=np.asarray(triangles,dtype=float)
    if (root.shape!=(3,) or triangles.ndim!=3 or triangles.shape[1:]!=(3,3)
            or not len(triangles) or not np.isfinite(root).all() or not np.isfinite(triangles).all()
            or not np.isfinite([required,radius]).all() or not 0<required<radius):
        raise ValueError('Invalid departure geometry or margins')
    a,b,c=triangles[:,0],triangles[:,1],triangles[:,2];ab=b-a;ac=c-a;ap=root-a
    normal=np.cross(ab,ac);norm2=(normal*normal).sum(1)
    if np.any(norm2<1e-24):raise ValueError('Degenerate departure triangle')
    u=(np.cross(ap,ac)*normal).sum(1)/norm2;v=(np.cross(ab,ap)*normal).sum(1)/norm2
    q=a+u[:,None]*ab+v[:,None]*ac
    best=((q-root)**2).sum(1);best[(u<0)|(v<0)|(u+v>1)]=np.inf
    for start,end in ((a,b),(b,c),(c,a)):
        edge=end-start;t=np.clip(((root-start)*edge).sum(1)/(edge*edge).sum(1),0,1)
        candidate=start+t[:,None]*edge;distance=((candidate-root)**2).sum(1);improve=distance<best
        q[improve]=candidate[improve];best[improve]=distance[improve]
    distance=np.sqrt(best)
    if np.any(distance<required-2e-7):raise ValueError('Root fails supplied clearance')
    selected=np.flatnonzero(distance<=radius)
    if not len(selected):raise ValueError('No nearby triangles for departure constraint')
    origins=q[selected];normals=(root-origins)/distance[selected,None]
    # A capped buffer cannot ask the immutable root to move.
    margins=np.minimum(required+.00025,distance[selected])
    separation=((triangles[selected]-origins[:,None])*normals[:,None]).sum(2)
    if np.any(separation>1e-9):raise ValueError('Plane does not separate triangle from root')
    return dict(origins=origins,normals=normals,margins=margins,triangleIndices=selected)
