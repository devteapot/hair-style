import copy
import unittest
import numpy as np
from scalp_attachments import attachment_positions


class AttachmentTests(unittest.TestCase):
    def setUp(self):
        self.scalp=dict(vertices=[dict(x=0,y=0,z=0),dict(x=1,y=0,z=0),dict(x=0,y=1,z=0)],triangles=[[0,1,2]])
        self.binding=dict(triangleIndex=0,barycentric=[.5,.2,.3],normalOffsetMeters=.003)
    def test_offset_zero_offset_and_winding(self):
        b=copy.deepcopy(self.binding);b['normalOffsetMeters']=0
        np.testing.assert_allclose(attachment_positions(self.scalp,[self.binding,b]),[[.2,.3,.003],[.2,.3,0]],atol=1e-15,rtol=0)
        self.scalp['triangles']=[[0,2,1]]
        np.testing.assert_allclose(attachment_positions(self.scalp,[self.binding]),[[.3,.2,-.003]],atol=1e-15,rtol=0)
    def test_rejects_invalid_binding_and_degenerate_triangle(self):
        for key,value in [('triangleIndex',-1),('triangleIndex',True),('normalOffsetMeters',-.001),('normalOffsetMeters',.011),('normalOffsetMeters',float('nan')),('barycentric',[1,1,1])]:
            b={**self.binding,key:value}
            with self.assertRaises(ValueError):attachment_positions(self.scalp,[b])
        self.scalp['triangles']=[[0,0,1]]
        with self.assertRaises(ValueError):attachment_positions(self.scalp,[self.binding])
    def test_rigid_transform(self):
        r=np.array([[0.,0.,1.],[1.,0.,0.],[0.,1.,0.]]);t=np.array([.1,.2,-.1])
        before=attachment_positions(self.scalp,[self.binding])
        for p in self.scalp['vertices']:
            v=r@np.array([p[k] for k in ('x','y','z')])+t;p.update(zip(('x','y','z'),v))
        np.testing.assert_allclose(attachment_positions(self.scalp,[self.binding]),before@r.T+t,atol=1e-15,rtol=0)


if __name__=='__main__':unittest.main()
