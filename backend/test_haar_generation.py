from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from backend.job_store import JobStore
from backend.compile_worker import run_one


class ResearchGenerationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        self.store = JobStore(self.root/'jobs.sqlite')
        self.session = self.store.create_session('owner')
        self.request = dict(schemaVersion=1, kind='generate_haar_template', description='short wavy hair', seed=43)

    def tearDown(self):
        self.store.close(); self.temp.cleanup()

    def test_disabled_or_invalid_generation_never_starts_model_process(self):
        for i, (enabled, request) in enumerate([(False, self.request),
                (True, dict(self.request, seed=True)), (True, dict(self.request, description='x\ny')),
                (True, dict(self.request, checkpoint='/untrusted/weights'))]):
            job = self.store.submit('owner', self.session, str(i), request)
            with patch('backend.haar_generation.run_stage') as launch:
                result = run_one(self.store, self.root/'artifacts', '/unused', self.root if enabled else None)
            launch.assert_not_called()
            self.assertFalse(result['published'])
            self.assertEqual(self.store.get('owner', job)['state'], 'failed')

    def test_cancellation_after_claim_prevents_model_loading(self):
        job = self.store.submit('owner', self.session, 'cancel', self.request)
        claim = self.store.claim
        def cancel_after_claim():
            attempt = claim(); self.store.cancel('owner', job); return attempt
        with patch.object(self.store, 'claim', side_effect=cancel_after_claim), \
                patch('backend.haar_generation.run_stage') as launch:
            result = run_one(self.store, self.root/'artifacts', '/unused', self.root)
        launch.assert_not_called()
        self.assertFalse(result['published'])
        self.assertEqual(self.store.get('owner', job)['state'], 'cancelled')
        self.assertEqual(list((self.root/'artifacts').rglob('result.json')), [])
