import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import root_preflight


class RootPreflightTests(unittest.TestCase):
    def test_prepared_replay_precedes_root_check_and_replaces_generation_input(self):
        with tempfile.TemporaryDirectory() as directory:
            args=self.arguments(directory)
            args.input=Path(directory)/'source.json';args.input.write_text('{"source":1}')
            args.prepared_brief=Path(directory)/'prepared.json';args.prepared_brief.write_text('{"prepared":1}')
            commands=[]
            def inspect(command,timeout):
                commands.append(command)
                if command[1]=='brief-consume':
                    Path(command[-1]).write_text('{"compiled":2}')
                    return SimpleNamespace(returncode=0)
                self.assertEqual(Path(command[2]).read_text(),'{"compiled":2}')
                return SimpleNamespace(returncode=2)
            with patch('root_preflight.subprocess.run',side_effect=inspect):
                with self.assertRaises(SystemExit):root_preflight.run(args)
            self.assertEqual([c[1] for c in commands],['brief-consume','hair-root-preflight'])
            self.assertEqual(args.input.name,'generation-input.json')
            self.assertTrue((args.output/'brief-handoff.json').exists())

    def test_invalid_prepared_brief_never_reaches_root_check(self):
        with tempfile.TemporaryDirectory() as directory:
            args=self.arguments(directory)
            args.input=Path(directory)/'source.json';args.input.write_text('{}')
            args.prepared_brief=Path(directory)/'prepared.json';args.prepared_brief.write_text('{}')
            with patch('root_preflight.subprocess.run',return_value=SimpleNamespace(returncode=1)) as launch:
                with self.assertRaises(RuntimeError):root_preflight.run(args)
                self.assertEqual(launch.call_count,1)
                self.assertEqual(launch.call_args.args[0][1],'brief-consume')

    def test_clear_result_retains_missing_anatomy_and_refuses_reused_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            args = self.arguments(directory)
            def inspect(command, timeout):
                Path(command[-1]).write_text(json.dumps(dict(
                    method='proposed_root_clearance_preflight_v1',
                    requiresAttachmentReview=False, suppliedSurfacesPassed=True,
                    violations=[], physicalFitVerified=False,
                    missingRegions=['anatomical_left_ear', 'anatomical_right_ear'])))
                return SimpleNamespace(returncode=0)
            with patch('root_preflight.subprocess.run', side_effect=inspect) as launch:
                report = root_preflight.run(args)
                self.assertEqual(len(report['missingRegions']), 2)
                self.assertFalse(report['physicalFitVerified'])
                self.assertEqual(len(report['reportSHA256']), 64)
                with self.assertRaises(FileExistsError):
                    root_preflight.run(args)
                self.assertEqual(launch.call_count, 1)

    def test_rejected_or_failed_inspection_cannot_continue(self):
        for code in (1, 2, -9):
            with tempfile.TemporaryDirectory() as directory:
                args = self.arguments(directory)
                with patch('root_preflight.subprocess.run', return_value=SimpleNamespace(returncode=code)):
                    with self.assertRaises(SystemExit if code == 2 else RuntimeError):
                        root_preflight.run(args)

    @staticmethod
    def arguments(directory):
        return SimpleNamespace(output=Path(directory)/'run', inspector=Path('/trusted/inspector'),
            input=Path('/input.json'), mapping=Path('/mapping.json'),
            anatomy=Path('/anatomy.json'), material_radius_meters=0.00005)


if __name__ == '__main__':
    unittest.main()
