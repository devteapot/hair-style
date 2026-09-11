import unittest
from propose_model_mapping import attachment_boundary_report


class AttachmentBoundaryTests(unittest.TestCase):
    def test_shared_triangle_edge_is_not_open_scalp_boundary(self):
        scalp=dict(vertices=[dict(x=x,y=y,z=0) for x,y in [(0,0),(1,0),(1,1),(0,1)]],
                   triangles=[[0,1,2],[0,2,3]])
        def mapping(name,bary):
            return dict(guideID=name,region='fringe',binding=dict(
                triangleIndex=0,barycentric=bary,normalOffsetMeters=0))
        result=attachment_boundary_report(scalp,[mapping('shared',[.5,0,.5]),
            mapping('outer',[.5,.5,0]),mapping('vertex',[1,0,0]),mapping('inside',[.2,.3,.5])])
        self.assertEqual(result['openBoundaryEdges'],4)
        self.assertEqual([v['guideID'] for v in result['boundaryRoots']],['outer','vertex'])
        self.assertTrue(result['requiresBoundaryReview'])


if __name__=='__main__':unittest.main()
