import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import numpy as np
from compare_hair_image import compare_guides


class ProjectedHairTests(unittest.TestCase):
    def setUp(self):
        self.meta = dict(imageSize=dict(width=100, height=100), mirrored=False,
            pixelOrientation='sensor_native', depthRectification='synthetic_pinhole',
            intrinsics=dict(fx=100, fy=100, cx=100, cy=100, referenceSize=dict(width=200, height=200)))
        self.mask = np.ones((100, 100), dtype=bool)
        self.axes = np.zeros((100, 100, 3), dtype=np.float32)
        self.axes[..., 0] = 1; self.axes[..., 2] = 1
        self.matrix = np.eye(4)

    def compare(self, guide):
        return compare_guides([guide], self.meta, self.matrix, self.mask, self.axes)

    def test_projection_scaled_intrinsics_and_undirected_error(self):
        horizontal = [[-.4, 0, 1], [.4, 0, 1]]
        a = self.compare(horizontal); b = self.compare(horizontal[::-1])
        self.assertEqual(a['projectedSamples'], 20)
        self.assertEqual(a['hairAgreementOfInImageSamples'], 1)
        self.assertEqual(a['orientationMedianDegrees'], 0)
        self.assertEqual(b['orientationMedianDegrees'], 0)
        self.assertEqual(self.compare([[0, -.4, 1], [0, .4, 1]])['orientationMedianDegrees'], 90)
        self.assertFalse(a['acceptedForFitting'])

    def test_missing_support_and_outside_view_remain_visible(self):
        self.mask[:] = False; self.axes[:] = 0
        a = self.compare([[-2, 0, 1], [2, 0, 1]])
        self.assertEqual(a['projectedSamples'], 100)
        self.assertEqual(a['outsideImageSamples'], 50)
        self.assertEqual(a['hairAgreementOfInImageSamples'], 0)
        self.assertIsNone(a['orientationMedianDegrees'])
        a = self.compare([[0, 0, -1], [0, 0, 1]])
        self.assertEqual(a['behindOrCrossingCamera'], 1)
        self.assertIsNone(a['hairAgreementOfInImageSamples'])

    def test_unsupported_calibration_and_nonrigid_transform_rejected(self):
        guide = [[-.4, 0, 1], [.4, 0, 1]]
        self.meta['depthRectification'] = 'not_applied'
        with self.assertRaises(ValueError): self.compare(guide)
        self.meta['depthRectification'] = 'synthetic_pinhole'
        self.matrix[0, 0] = 2
        with self.assertRaises(ValueError): self.compare(guide)

    def test_cli_hash_binding_and_round_trip(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); bundle = root/'bundle'; bundle.mkdir(); evidence = root/'evidence'; evidence.mkdir()
            sha = lambda b: hashlib.sha256(b).hexdigest()
            manifest = dict(id='capture', frames=[dict(metadata={**self.meta, 'id':'frame'}, image=dict(sha256='image'))])
            manifest_bytes = json.dumps(manifest).encode(); (bundle/'manifest.json').write_bytes(manifest_bytes)
            mask = self.mask.astype(np.uint8).tobytes(); axes = self.axes.astype('<f4').tobytes()
            (evidence/'hair-mask.u8').write_bytes(mask); (evidence/'texture-axis.f32').write_bytes(axes)
            report = dict(sourceManifestSHA256=sha(manifest_bytes), captureID='capture', frameID='frame',
                imageSHA256='image', imageSize=self.meta['imageSize'], maskSHA256=sha(mask),
                textureAxisSHA256=sha(axes), captureCondition='untied')
            report_bytes = json.dumps(report).encode(); (evidence/'report.json').write_bytes(report_bytes)
            haircut = dict(guides=[dict(points=[dict(x=-.4,y=0,z=1),dict(x=.4,y=0,z=1)])])
            haircut_bytes = json.dumps(haircut).encode(); (root/'haircut.json').write_bytes(haircut_bytes)
            alignment = dict(haircutFileSHA256=sha(haircut_bytes), evidenceReportSHA256=sha(report_bytes),
                cameraFromHairRowMajor=self.matrix.reshape(-1).tolist())
            (root/'alignment.json').write_text(json.dumps(alignment))
            cmd = [sys.executable, str(Path(__file__).with_name('compare_hair_image.py')), str(bundle), str(evidence),
                str(root/'haircut.json'), str(root/'alignment.json'), str(root/'result.json')]
            result = subprocess.run(cmd, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads((root/'result.json').read_text())['orientationMedianDegrees'], 0)
            (root/'haircut.json').write_bytes(haircut_bytes+b' ')
            result = subprocess.run(cmd, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Alignment belongs to different inputs', result.stderr)


if __name__ == '__main__': unittest.main()
