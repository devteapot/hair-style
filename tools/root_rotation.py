"""Differentiable proper rotations, including a finite gradient at zero angle."""
import torch


def axis_angle_matrix(vector):
    if vector.shape[-1]!=3 or not vector.is_floating_point():raise ValueError('Expected floating axis-angle vectors')
    x,y,z=vector.unbind(-1);zero=torch.zeros_like(x)
    skew=torch.stack([zero,-z,y,z,zero,-x,-y,x,zero],dim=-1).reshape(*vector.shape[:-1],3,3)
    angle=torch.linalg.vector_norm(vector,dim=-1)
    a=torch.sinc(angle/torch.pi)[...,None,None]
    b=(.5*torch.sinc(angle/(2*torch.pi)).square())[...,None,None]
    return torch.eye(3,dtype=vector.dtype,device=vector.device)+a*skew+b*(skew@skew)
