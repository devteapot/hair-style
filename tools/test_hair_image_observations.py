import unittest
import numpy as np
from hair_image_observations import observe_hair


class HairImageObservationTests(unittest.TestCase):
    def test_native_bounds_and_boundary_color_exclusion(self):
        rgb = np.zeros((30, 40, 3), dtype=np.uint8)
        labels = np.zeros((30, 40), dtype=np.uint8)
        labels[3:27, 8:32] = 13
        rgb[3:27, 8:32] = [255, 0, 0]
        rgb[5:25, 10:30] = [20, 30, 40]
        mask, interior, report = observe_hair(rgb, labels, np.ones(labels.shape))
        self.assertEqual(report['boundsPixels'], dict(x=8, y=3, width=24, height=24))
        self.assertEqual(report['recordedColor']['median'], [20, 30, 40])
        self.assertEqual(interior.sum(), 400)
        self.assertTrue(np.all(~interior | mask))
        self.assertFalse(report['recordedColor']['intrinsicColorCalibrated'])
        self.assertIsNone(report['rootDirection'])
        self.assertIsNone(report['metricVolume'])

    def test_posterior_alone_does_not_override_nonhair_label(self):
        rgb = np.zeros((20, 20, 3), dtype=np.uint8)
        labels = np.full((20, 20), 13, dtype=np.uint8)
        labels[:10] = 14
        confidence = np.ones((20, 20)); confidence[10:] = .79
        mask, _, report = observe_hair(rgb, labels, confidence)
        self.assertEqual(mask.sum(), 0)
        self.assertIsNone(report['boundsPixels'])
        self.assertIsNone(report['recordedColor'])
        self.assertEqual(report['status'], 'insufficient_support')

    def test_image_edges_are_not_treated_as_interior(self):
        _, interior, _ = observe_hair(np.zeros((20, 20, 3), dtype=np.uint8),
            np.full((20, 20), 13), np.ones((20, 20)), interior_radius=2)
        self.assertEqual(interior.sum(), 16*16)
        self.assertFalse(interior[0].any())

    def test_invalid_arrays_fail(self):
        rgb = np.zeros((20, 20, 3), dtype=np.uint8)
        labels = np.full((20, 20), 13)
        for posterior in [np.ones((19, 20)), np.full((20, 20), np.nan), np.full((20, 20), 1.1)]:
            with self.assertRaises(ValueError):
                observe_hair(rgb, labels, posterior)


if __name__ == '__main__':
    unittest.main()
