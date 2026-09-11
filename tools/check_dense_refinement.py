#!/usr/bin/env python3
"""Synthetic numerical checks for research rigid refinement, not sensor validation."""
import unittest
import numpy as np
from refine_face_rigid import nearest,optimize,transform


class RefinementChecks(unittest.TestCase):
    def testNearestMatchesBruteForceIncludingExactCoincidence(self):
        rng=np.random.default_rng(9);target=rng.normal(size=(731,3))*.05
        query=np.concatenate((target[:17],rng.normal(size=(280,3))*.05))
        indices,distances=nearest(query,target)
        brute=np.linalg.norm(query[:,None,:]-target[None,:,:],axis=2)
        np.testing.assert_array_equal(indices,brute.argmin(axis=1))
        np.testing.assert_allclose(distances,brute.min(axis=1),atol=3e-9)

    def testRecoversKnownRigidTransformWithoutScale(self):
        rng=np.random.default_rng(42);source=rng.uniform(-.05,.05,(1200,3));source[:,1]*=1.4;source[:,2]*=.4;source[:,2]+=.3
        angle=np.deg2rad(2);truth=np.eye(4);truth[:3,:3]=[[np.cos(angle),-np.sin(angle),0],[np.sin(angle),np.cos(angle),0],[0,0,1]];truth[:3,3]=[.001,-.0015,.0005]
        target=transform(source,truth)
        recovered,history=optimize(source,target,np.eye(4))
        np.testing.assert_allclose(recovered,truth,atol=1e-6)
        self.assertTrue(history)
        self.assertAlmostEqual(np.linalg.det(recovered[:3,:3]),1,places=10)

    def testRejectsDistantCloudAndInsufficientSamples(self):
        rng=np.random.default_rng(4);points=rng.uniform(-.01,.01,(200,3))
        with self.assertRaisesRegex(ValueError,'overlap'):optimize(points,points+1,np.eye(4))
        with self.assertRaisesRegex(ValueError,'Insufficient fitting'):optimize(points[:20],points,np.eye(4))


if __name__=='__main__':unittest.main()
