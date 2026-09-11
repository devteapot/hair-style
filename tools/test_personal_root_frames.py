import unittest
import numpy as np
from audit_personal_root_frames import transformed_surface_normals


class RootFrameTests(unittest.TestCase):
    def test_sheared_frame_and_nonuniform_scale(self):
        # z=.3x+.2y becomes z=.6x+(.8/3)y after scaling by (2,3,4).
        basis=np.array([[[1,0,0],[0,1,0],[.3,.2,1]]],dtype=float)
        expected=np.array([-.6,-.8/3,1.]);expected/=np.linalg.norm(expected)
        np.testing.assert_allclose(transformed_surface_normals(basis,[2,3,4])[0],expected,atol=1e-14)

    def test_rotation_and_batch_identity(self):
        basis=np.array([np.eye(3),[[1,0,0],[0,0,-1],[0,1,0]]])
        np.testing.assert_allclose(transformed_surface_normals(basis,[1,1,1]),[[0,0,1],[0,-1,0]],atol=1e-14)

    def test_invalid_frames_rejected(self):
        for basis,scale in [(np.zeros((1,3,3)),[1,1,1]),(np.diag([-1,1,1])[None],[1,1,1]),(np.eye(3)[None],[0,1,1]),(np.eye(3)[None],[1,np.nan,1])]:
            with self.assertRaises(ValueError):transformed_surface_normals(basis,scale)


if __name__=='__main__':unittest.main()
