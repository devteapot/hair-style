import unittest
import torch
from root_bending import bend_segments


class BendingTests(unittest.TestCase):
    def setUp(self):
        self.points = torch.tensor([[1.,2.,3.],[2.,2.,3.],[2.,4.,3.],[2.,4.,6.]], dtype=torch.float64)

    def test_known_bend_keeps_root_lengths_and_tail_vectors(self):
        rotations = torch.tensor([[0.,0.,torch.pi/2]], dtype=torch.float64)
        result = bend_segments(self.points, rotations)
        expected = torch.tensor([[1.,2.,3.],[1.,3.,3.],[1.,5.,3.],[1.,5.,6.]], dtype=torch.float64)
        torch.testing.assert_close(result, expected, atol=1e-14, rtol=0)
        self.assertTrue(torch.equal(result[0], self.points[0]))

    def test_batch_segment_lengths_and_gradients(self):
        rotations = torch.tensor([[[0.,0.,0.],[.1,.2,-.3]],[[.3,-.4,.2],[0.,0.,0.]]],dtype=torch.float64,requires_grad=True)
        result = bend_segments(self.points, rotations)
        lengths = torch.linalg.vector_norm(torch.diff(result, dim=-2),dim=-1)
        torch.testing.assert_close(lengths,torch.tensor([[1.,2.,3.],[1.,2.,3.]],dtype=torch.float64),atol=1e-14,rtol=0)
        self.assertTrue(torch.autograd.gradcheck(lambda r: bend_segments(self.points,r),(rotations,)))

    def test_invalid_shapes(self):
        for r in [torch.zeros(3,dtype=torch.float64),torch.zeros(4,3,dtype=torch.float64),torch.zeros(1,3)]:
            with self.assertRaises(ValueError):bend_segments(self.points,r)


if __name__ == '__main__':unittest.main()
