import unittest
import numpy as np
from probe_normal_root_offsets import offset_curve


class NormalOffsetTests(unittest.TestCase):
    def setUp(self):
        self.tri=np.array([[0.,0.,0.],[1.,0.,0.],[0.,1.,0.]])
        self.binding=dict(triangleIndex=0,barycentric=[.5,.25,.25],normalOffsetMeters=.001)
        self.points=np.array([[.25,.25,.001],[.25,.26,.004],[.26,.27,.004]])

    def test_translation_preserves_shape_and_records_attachment(self):
        after,binding,normal=offset_curve(self.points,self.tri,self.binding,.003)
        np.testing.assert_allclose(after,self.points+[0,0,.003],atol=1e-16,rtol=0)
        np.testing.assert_allclose(np.diff(after,axis=0),np.diff(self.points,axis=0),atol=1e-16,rtol=0)
        self.assertEqual(binding['normalOffsetMeters'],.004)
        self.assertEqual(self.binding['normalOffsetMeters'],.001)
        np.testing.assert_array_equal(normal,[0,0,1])

    def test_rigid_coordinate_change(self):
        rotation=np.array([[0.,0.,1.],[1.,0.,0.],[0.,1.,0.]])
        translation=np.array([.1,-.2,.3])
        a,_,_=offset_curve(self.points,self.tri,self.binding,.002)
        b,_,_=offset_curve(self.points@rotation.T+translation,self.tri@rotation.T+translation,self.binding,.002)
        np.testing.assert_allclose(b,a@rotation.T+translation,atol=1e-15,rtol=0)

    def test_rejects_mismatch_and_excessive_offset(self):
        for offset in [0,-.001,.004001,float('nan')]:
            with self.assertRaises(ValueError):offset_curve(self.points,self.tri,self.binding,offset)
        with self.assertRaises(ValueError):offset_curve(self.points+.01,self.tri,self.binding,.002)
        with self.assertRaises(ValueError):offset_curve(self.points,np.zeros((3,3)),self.binding,.002)


if __name__=='__main__':unittest.main()
