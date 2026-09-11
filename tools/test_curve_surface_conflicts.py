import unittest
from diagnose_curve_surface_conflicts import topology


class SurfaceTopologyTests(unittest.TestCase):
    def test_open_square_and_separate_component(self):
        r=topology([[0,1,2],[0,2,3],[4,5,6]])
        self.assertEqual(r['componentTriangleCounts'],[2,1])
        self.assertEqual(r['boundaryEdges'],7)
        self.assertEqual(r['triangleHopsToOpenEdge'],[0,0,0])
        self.assertEqual(r['inconsistentWindingEdges'],0)

    def test_closed_tetrahedron_has_no_open_edge(self):
        r=topology([[0,2,1],[0,1,3],[1,2,3],[2,0,3]])
        self.assertEqual(r['componentTriangleCounts'],[4])
        self.assertEqual(r['triangleHopsToOpenEdge'],[None]*4)
        self.assertEqual(r['inconsistentWindingEdges'],0)

    def test_interior_triangle_one_hop_from_boundary(self):
        r=topology([[0,1,2],[1,0,3],[2,1,4],[0,2,5]])
        self.assertEqual(r['triangleHopsToOpenEdge'],[1,0,0,0])

    def test_winding_and_nonmanifold_edges_are_reported(self):
        self.assertEqual(topology([[0,1,2],[0,3,2]])['inconsistentWindingEdges'],1)
        self.assertEqual(topology([[0,1,2],[1,0,3],[0,1,4]])['nonmanifoldEdges'],1)


if __name__=='__main__':unittest.main()
