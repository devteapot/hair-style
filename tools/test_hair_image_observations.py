import unittest
import numpy as np
from hair_image_observations import observe_hair, texture_orientation


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

    def test_orientation_tracks_texture_tangent_with_180_degree_ambiguity(self):
        y, x = np.mgrid[:96, :96]
        for gradient, expected in [(y, [1, 0]), (x, [-1, 0]), (x+y, [0, -1])]:
            gray = np.round(128+100*np.sin(gradient*.3)).astype(np.uint8)
            rgb = np.repeat(gray[..., None], 3, axis=2)
            field, report = texture_orientation(rgb, np.ones(gray.shape, dtype=bool))
            supported = field[..., 2] > 0
            self.assertGreater(report['supportedPixels'], 1000)
            np.testing.assert_allclose(field[supported, :2].mean(axis=0), expected, atol=.002)
            np.testing.assert_allclose(np.linalg.norm(field[supported, :2], axis=1), 1, atol=1e-6)
            self.assertFalse(report['directed'])
            inverted, _ = texture_orientation(255-rgb, np.ones(gray.shape, dtype=bool))
            np.testing.assert_allclose(field, inverted, atol=1e-6)
            rotated, _ = texture_orientation(np.rot90(rgb), np.ones(gray.shape, dtype=bool))
            expected_rotated = np.rot90(field).copy()
            expected_rotated[..., :2] *= -1
            np.testing.assert_allclose(rotated, expected_rotated, atol=1e-6)

    def test_orientation_has_no_support_on_flat_or_mask_boundary(self):
        rgb = np.full((50, 50, 3), 128, dtype=np.uint8)
        mask = np.ones((50, 50), dtype=bool)
        field, report = texture_orientation(rgb, mask)
        self.assertEqual(report['supportedPixels'], 0)
        self.assertTrue(np.all(field == 0))
        rgb[:] = np.round(128+100*np.sin(np.arange(50)*.3)).astype(np.uint8)[:, None, None]
        mask[:, 24:26] = False
        field, _ = texture_orientation(rgb, mask)
        self.assertTrue(np.all(field[:, 16:34] == 0))
        self.assertGreater(np.count_nonzero(field[..., 2]), 0)

    def test_orientation_rejects_invalid_inputs(self):
        rgb = np.zeros((20, 20, 3), dtype=np.uint8)
        mask = np.ones((20, 20), dtype=bool)
        for kwargs in [dict(radius=0), dict(minimum_coherence=float('nan')), dict(minimum_energy=-1)]:
            with self.assertRaises(ValueError): texture_orientation(rgb, mask, **kwargs)
        with self.assertRaises(ValueError): texture_orientation(rgb, mask.astype(np.uint8))


if __name__ == '__main__':
    unittest.main()
