import unittest
import torch
from root_rotation import axis_angle_matrix


class RotationTests(unittest.TestCase):
    def test_known_quarter_turn(self):
        r=axis_angle_matrix(torch.tensor([0.,0.,torch.pi/2],dtype=torch.float64))
        torch.testing.assert_close(r@torch.tensor([1.,0.,0.],dtype=r.dtype),torch.tensor([0.,1.,0.],dtype=r.dtype),atol=1e-14,rtol=0)
    def test_zero_and_nonzero_gradients(self):
        for value in ([0.,0.,0.],[.13,-.2,.07]):
            v=torch.tensor(value,dtype=torch.float64,requires_grad=True)
            self.assertTrue(torch.autograd.gradcheck(axis_angle_matrix,(v,)))
    def test_proper_rotation_and_distance_preservation(self):
        v=torch.tensor([[0.,0.,0.],[.3,-.2,.1]],dtype=torch.float64);r=axis_angle_matrix(v)
        torch.testing.assert_close(r.transpose(-1,-2)@r,torch.eye(3,dtype=v.dtype).expand(2,3,3),atol=1e-14,rtol=0)
        torch.testing.assert_close(torch.linalg.det(r),torch.ones(2,dtype=v.dtype),atol=1e-14,rtol=0)
    @unittest.skipUnless(torch.backends.mps.is_available(),'Requires Metal')
    def test_metal_gradient_parity(self):
        values=[];grads=[]
        for device in ['cpu','mps']:
            v=torch.tensor([[0.,0.,0.],[.12,-.1,.07]],device=device,requires_grad=True)
            r=axis_angle_matrix(v);r[...,0,1].sum().backward();values.append(r.detach().cpu());grads.append(v.grad.cpu())
        torch.testing.assert_close(values[0],values[1],atol=1e-6,rtol=1e-5)
        torch.testing.assert_close(grads[0],grads[1],atol=1e-6,rtol=1e-5)


if __name__=='__main__':unittest.main()
