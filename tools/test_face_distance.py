import unittest
import torch
from face_distance import point_surface_distance_squared as distance


class FaceDistanceTests(unittest.TestCase):
    def setUp(self):
        self.tri = torch.tensor([[[0.,0.,0.],[1.,0.,0.],[0.,1.,0.]]], dtype=torch.float64)

    def test_projection_edges_vertices_and_degeneracy(self):
        p = torch.tensor([[.2,.2,2.], [.7,.7,0.], [-1.,-1.,0.]], dtype=torch.float64)
        torch.testing.assert_close(distance(p,self.tri), torch.tensor([4.,.08,2.],dtype=p.dtype))
        degenerate = torch.zeros_like(self.tri)
        torch.testing.assert_close(distance(p,degenerate), p.square().sum(1))
        line = self.tri.clone(); line[0,2] = line[0,1]
        torch.testing.assert_close(distance(p[:1],line), torch.tensor([4.04],dtype=p.dtype))
        for tri in (degenerate,line):
            probe=p.clone().requires_grad_(True)
            distance(probe,tri).sum().backward()
            self.assertTrue(bool(torch.isfinite(probe.grad).all()))

    def test_gradient_finite_difference_and_chunk_invariance(self):
        p = torch.tensor([[.2,.2,.3],[.7,.7,.1],[-.2,-.3,.1]],dtype=torch.float64,requires_grad=True)
        self.assertTrue(torch.autograd.gradcheck(lambda x: distance(x,self.tri), (p,)))
        triangles = torch.cat([self.tri, self.tri+4, self.tri-4])
        torch.testing.assert_close(distance(p,triangles,1), distance(p,triangles,3))
        distance(p,triangles,1).sum().backward()
        torch.testing.assert_close(p.grad[0],torch.tensor([0.,0.,.6],dtype=p.dtype))

    def test_winding_and_rigid_transform_invariance(self):
        p = torch.tensor([[.2,.2,.3],[.7,.7,.1]],dtype=torch.float64)
        rotation = torch.tensor([[0.,-1.,0.],[1.,0.,0.],[0.,0.,1.]],dtype=p.dtype)
        torch.testing.assert_close(distance(p,self.tri),distance(p@rotation+2,self.tri@rotation+2))
        torch.testing.assert_close(distance(p,self.tri),distance(p,self.tri.flip(1)))

    def test_rejects_invalid_and_preserves_empty(self):
        for tri in (self.tri[:0], self.tri*float('nan')):
            with self.assertRaises(ValueError): distance(torch.zeros((1,3),dtype=tri.dtype),tri)
        self.assertEqual(distance(torch.zeros((0,3),dtype=self.tri.dtype),self.tri).shape,(0,))

    @unittest.skipUnless(torch.backends.mps.is_available(),'Requires Metal')
    def test_metal_values_and_gradients(self):
        p = torch.tensor([[.02,.02,.003],[.07,.07,.01],[-.02,-.03,.01]],requires_grad=True)
        tri = self.tri.float()*.1
        cpu = distance(p,tri); cpu.sum().backward()
        metal_p = p.detach().to('mps').requires_grad_(True)
        metal = distance(metal_p,tri.to('mps')); metal.sum().backward()
        torch.testing.assert_close(metal.cpu(),cpu,atol=1e-8,rtol=1e-5)
        torch.testing.assert_close(metal_p.grad.cpu(),p.grad,atol=1e-7,rtol=1e-5)


if __name__ == '__main__': unittest.main()
