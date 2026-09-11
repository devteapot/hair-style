"""Differentiable unsigned point/surface distance for research objectives.

This is not a segment collision or inside/outside test. Final canonical guide
clearance remains required, including between sampled curve points.
"""
import torch


def point_surface_distance_squared(points, triangles, triangle_chunk=512):
    """Return one squared distance per point, preserving autograd.

    Inputs are [N,3] and [T,3,3] on the same device/dtype, in meters.
    Degenerate triangles are treated as their edges/vertices. Chunking bounds
    individual intermediates, but autograd still retains work across chunks.
    """
    if (points.ndim != 2 or points.shape[1] != 3 or triangles.ndim != 3
            or triangles.shape[1:] != (3, 3) or not len(triangles)
            or not isinstance(triangle_chunk, int) or triangle_chunk < 1
            or not points.is_floating_point() or points.dtype != triangles.dtype
            or points.device != triangles.device):
        raise ValueError('Expected matching floating point coordinates and nonempty triangles')
    if not bool(torch.isfinite(points).all()) or not bool(torch.isfinite(triangles).all()):
        raise ValueError('Nonfinite surface coordinates')
    if not len(points):
        return points.sum(dim=1)
    best = None
    tiny = torch.finfo(points.dtype).tiny
    p = points[:, None, :]
    for tri in triangles.split(triangle_chunk):
        a, b, c = tri.unbind(dim=1)
        ab, ac = b-a, c-a
        normal = torch.linalg.cross(ab, ac)
        norm2 = (normal*normal).sum(dim=-1)
        ap = p-a
        signed = (ap*normal).sum(dim=-1)
        # Barycentric coordinates from cross products avoid cancellation in
        # the Gram determinant for narrow triangles.
        u = (torch.linalg.cross(ap, ac.expand_as(ap))*normal).sum(dim=-1)/norm2.clamp_min(tiny)
        v = (torch.linalg.cross(ab.expand_as(ap), ap)*normal).sum(dim=-1)/norm2.clamp_min(tiny)
        inside = (norm2 > tiny) & (u >= 0) & (v >= 0) & (u+v <= 1)
        plane = signed.square()/norm2.clamp_min(tiny)
        edges = []
        for start, end in ((a,b), (b,c), (c,a)):
            edge = end-start
            t = ((p-start)*edge).sum(dim=-1)/(edge*edge).sum(dim=-1).clamp_min(tiny)
            delta = p-start-t.clamp(0,1)[...,None]*edge
            edges.append(delta.square().sum(dim=-1))
        edge_distance = torch.stack(edges).amin(dim=0)
        distance = torch.where(inside, plane, edge_distance).amin(dim=1)
        best = distance if best is None else torch.minimum(best, distance)
    return best
