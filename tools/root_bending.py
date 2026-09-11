"""Local bending with fixed roots and individually preserved segment lengths."""
import torch
from root_rotation import axis_angle_matrix


def bend_segments(points, rotations):
    """Rotate the first K segment vectors; retain the remaining vectors exactly.

    points: N×3; rotations: ...×K×3 axis angles. Each result is ...×N×3.
    This preserves arc length, not curvature, appearance or anatomical clearance.
    """
    if (points.ndim != 2 or points.shape[1] != 3 or len(points) < 2
            or rotations.ndim < 2 or rotations.shape[-1] != 3
            or not 1 <= rotations.shape[-2] < len(points)
            or points.dtype != rotations.dtype or points.device != rotations.device
            or not points.is_floating_point()):
        raise ValueError('Invalid bending points or rotation dimensions')
    k = rotations.shape[-2]
    segments = points[1:] - points[:-1]
    rotated = (axis_angle_matrix(rotations) @ segments[:k, :, None]).squeeze(-1)
    tail = segments[k:].expand(*rotations.shape[:-2], len(segments)-k, 3)
    steps = torch.cat([rotated, tail], dim=-2)
    root = points[:1].expand(*rotations.shape[:-2], 1, 3)
    return torch.cat([root, root + torch.cumsum(steps, dim=-2)], dim=-2)
