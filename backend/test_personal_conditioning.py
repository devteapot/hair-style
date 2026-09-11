"""Worker boundary tests; model correctness uses the separate actual Metal run."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import uuid
from unittest.mock import patch
from backend.artifact_store import ArtifactStore
from backend.compile_worker import run_one
from backend.job_store import JobStore


class PersonalConditioningBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        self.store=JobStore(self.root/'jobs.sqlite');self.session=self.store.create_session('owner')
        self.artifacts=self.root/'artifacts';self.files=ArtifactStore(self.store,self.artifacts)
        self.object_hash=self.files.stage('owner',self.session,b'{}')
        sample_bytes=b'{"testOnly":true}';self.sample_hash=hashlib.sha256(sample_bytes).hexdigest()
        self.sample=self.root/'.research/conditioning-samples'/self.sample_hash
        self.sample.mkdir(parents=True);(self.sample/'source.json').write_bytes(sample_bytes)
        (self.sample/'texture.safetensors').write_bytes(b'test-only-texture')
        (self.sample/'trajectory-report.json').write_text(json.dumps({'textureSHA256':hashlib.sha256(b'test-only-texture').hexdigest()}))
        self.request=dict(schemaVersion=1,kind='condition_personal_sample',modelSampleSHA256=self.sample_hash,
                          **{key:self.object_hash for key in ('inputSHA256','preparedBriefSHA256','mappingSHA256','anatomySHA256','preparationSHA256')})

    def tearDown(self):
        self.store.close();self.temp.cleanup()

    def submit(self, request=None):
        return self.store.submit('owner',self.session,str(uuid.uuid4()),request or self.request)

    def run_worker(self, enabled=True):
        return run_one(self.store,self.artifacts,Path('.build/debug/capture-inspect'),self.root if enabled else None)

    def assert_clean_failure(self, job, result):
        self.assertFalse(result['published'])
        with self.assertRaises(LookupError):self.files.read_result('owner',job)
        self.assertEqual(list((self.artifacts/self.session/'jobs'/job).glob('*/result.json')),[])

    def test_disabled_and_malformed_requests_never_execute_pipeline(self):
        with patch('backend.personal_conditioning.run_stage') as stage:
            job=self.submit();self.assert_clean_failure(job,self.run_worker(False))
            for request in (dict(self.request,schemaVersion=True),dict(self.request,extraPath='/tmp'),
                            dict(self.request,modelSampleSHA256='../outside')):
                job=self.submit(request);self.assert_clean_failure(job,self.run_worker())
            stage.assert_not_called()

    def test_sample_tampering_and_foreign_objects_rejected_before_execution(self):
        with patch('backend.personal_conditioning.run_stage') as stage:
            (self.sample/'texture.safetensors').write_bytes(b'changed')
            job=self.submit();self.assert_clean_failure(job,self.run_worker())
            (self.sample/'texture.safetensors').write_bytes(b'test-only-texture')
            foreign=self.store.create_session('someone-else')
            digest=self.files.stage('someone-else',foreign,b'{"foreign":true}')
            job=self.submit(dict(self.request,inputSHA256=digest));self.assert_clean_failure(job,self.run_worker())
            stage.assert_not_called()

    def test_cancellation_after_launch_prevents_publication(self):
        job=self.submit()
        def cancel(*args,**kwargs):
            self.assertTrue(kwargs['active']())
            self.store.cancel('owner',job)
            self.assertFalse(kwargs['active']())
            return 0
        with patch('backend.personal_conditioning.run_stage',side_effect=cancel) as stage:
            self.assert_clean_failure(job,self.run_worker());stage.assert_called_once()
        self.assertEqual(self.store.get('owner',job)['state'],'cancelled')
