import unittest
import numpy as np
import torch
from root_departure import departure_planes


class DepartureTests(unittest.TestCase):
    def setUp(self):self.tri=np.array([[[0.,0.,0.],[.01,0.,0.],[0.,.01,0.]]])
    def test_interior_projection_and_winding(self):
        root=np.array([.002,.002,.002]);a=departure_planes(root,self.tri,.001)
        np.testing.assert_allclose(a['origins'],[[.002,.002,0]],atol=1e-15)
        np.testing.assert_allclose(a['normals'],[[0,0,1]],atol=1e-15)
        b=departure_planes(root,self.tri[:,::-1],.001)
        np.testing.assert_allclose(a['origins'],b['origins'],atol=1e-15)
        np.testing.assert_allclose(a['normals'],b['normals'],atol=1e-15)
    def test_edge_projection_keeps_root_feasible(self):
        root=np.array([.006,.006,.001]);r=departure_planes(root,self.tri,.001)
        np.testing.assert_allclose(r['origins'],[[.005,.005,0]],atol=1e-15)
        self.assertTrue(np.all(((root-r['origins'])*r['normals']).sum(1)>=r['margins']-1e-15))
        self.assertTrue(np.all(((self.tri-r['origins'][:,None])*r['normals'][:,None]).sum(2)<1e-15))
    def test_invalid_or_colliding_root_rejected(self):
        for root in ([.002,.002,.0001],[np.nan,0,0],[1,1,1]):
            with self.assertRaises(ValueError):departure_planes(root,self.tri,.001)
    def test_plane_loss_gradient_points_away(self):
        r=departure_planes([.002,.002,.002],self.tri,.001)
        gradients=[]
        for device in (['cpu','mps'] if torch.backends.mps.is_available() else ['cpu']):
            p=torch.tensor([[.002,.002,.0005]],device=device,requires_grad=True)
            origins=torch.tensor(r['origins'],dtype=p.dtype,device=device);normals=torch.tensor(r['normals'],dtype=p.dtype,device=device)
            loss=torch.relu(.00125-((p-origins)*normals).sum(1)).square().sum();loss.backward();gradients.append(p.grad.cpu().numpy())
        np.testing.assert_allclose(gradients[0],[[0,0,-.0015]],atol=1e-8)
        for g in gradients[1:]:np.testing.assert_allclose(g,gradients[0],atol=1e-8)


if __name__=='__main__':unittest.main()
