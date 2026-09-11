import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock
from tools.fit_conditioned_export import fit_export


class DirectionFitStageTests(unittest.TestCase):
    def test_clear_or_unsupported_export_never_starts_search(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out/'export').mkdir()
            for clearance, status in [
                (dict(surfaceChecksPassed=True, violations=[]), 'unneeded'),
                (dict(surfaceChecksPassed=False, violations=[dict(guideID='a')], rootViolations=[{}]), 'unsupported'),
                (dict(surfaceChecksPassed=False, violations=[dict(guideID=str(i)) for i in range(129)]), 'unsupported')]:
                (out/'export/clearance.json').write_text(json.dumps(clearance))
                invoke = Mock()
                self.assertEqual(fit_export(out, 'inspector', invoke)['status'], status)
                invoke.assert_not_called()

    def test_unresolved_search_retains_original_without_fit_record(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out/'export').mkdir()
            original = b'{"surfaceChecksPassed":false,"violations":[{"guideID":"a"}]}'
            (out/'export/clearance.json').write_bytes(original)
            def invoke(name, command):
                self.assertEqual(name, 'direction-proposal')
                (out/'direction-fit/proposal.json').write_text('{"clearance":{"surfaceChecksPassed":false}}')
            self.assertEqual(fit_export(out, 'inspector', invoke)['status'], 'unresolved')
            self.assertEqual((out/'export/clearance.json').read_bytes(), original)
            self.assertFalse((out/'direction-fit/record.json').exists())

    def test_failed_verification_never_compiles_or_selects_fit(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out/'export').mkdir(); (out/'inputs').mkdir()
            (out/'inputs/source.json').write_bytes(b'{}')
            (out/'export/clearance.json').write_text('{"surfaceChecksPassed":false,"violations":[{"guideID":"a"}]}')
            calls = []
            def invoke(name, command):
                calls.append(name)
                if name == 'direction-proposal':
                    (out/'direction-fit/proposal.json').write_text(json.dumps(dict(
                        clearance=dict(surfaceChecksPassed=True),sourceHaircutSHA256='a'*64,haircut={},
                        decisions=[dict(guideID='a',axis='(1, -1, 0)',degrees=5)])))
                else:
                    raise RuntimeError('Cumulative movement rejected')
            with self.assertRaisesRegex(RuntimeError, 'Cumulative movement'):
                fit_export(out, 'inspector', invoke)
            self.assertEqual(calls, ['direction-proposal', 'direction-verification'])
            record = json.loads((out/'direction-fit/record.json').read_bytes())
            self.assertEqual(record['rotations'][0]['axis'], dict(x=1,y=-1,z=0))
            self.assertFalse((out/'direction-fit/mesh.json').exists())
