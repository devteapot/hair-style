import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from backend.job_store import JobStore
from backend.artifact_store import ArtifactStore
from backend.compile_worker import run_one
from tools.canonical_json import loads


class CompileWorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        self.cli = Path('.build/debug/capture-inspect').resolve()
        subprocess.run([str(self.cli), 'hair-fixture', str(self.root/'fixture')], check=True, capture_output=True)
        self.store = JobStore(self.root/'jobs.sqlite'); self.session = self.store.create_session('owner')
        self.artifacts = self.root/'artifacts'; self.objects = self.artifacts/self.session/'objects'
        self.files = ArtifactStore(self.store, self.artifacts)
        self.request = dict(schemaVersion=1, kind='compile_hair')
        for name, key in [('input.json','inputSHA256'), ('haircut.json','haircutSHA256')]:
            data = (self.root/'fixture'/name).read_bytes(); digest = hashlib.sha256(data).hexdigest()
            self.assertEqual(self.files.stage('owner', self.session, data), digest); self.request[key] = digest

    def tearDown(self):
        self.store.close(); self.temp.cleanup()

    def test_real_compiler_result_is_bound_and_duplicate_does_not_run(self):
        fixture = self.root/'fixture/haircut.json'
        haircut = loads(fixture.read_bytes())
        root = haircut['guides'][0]['points'][0]
        haircut['guides'][0]['points'] = [dict(root), dict(root, z=root['z']+0.1)]
        fixture.write_text(json.dumps(haircut))
        self.request['haircutSHA256'] = self.files.stage('owner',self.session,fixture.read_bytes())
        job = self.store.submit('owner', self.session, 'one', self.request)
        self.assertTrue(run_one(self.store, self.artifacts, self.cli)['published'])
        output = next((self.artifacts/self.session/'jobs'/job).glob('*/result.json'))
        data = output.read_bytes(); record = self.store.get('owner', job); result = json.loads(data)
        self.assertEqual(record['output_hash'], hashlib.sha256(data).hexdigest())
        self.assertEqual(result['mesh']['haircutSHA256'], result['validation']['haircutSHA256'])
        reference = self.root/'reference-mesh.json'
        subprocess.run([str(self.cli),'hair-mesh',str(self.root/'fixture/input.json'),
            str(self.root/'fixture/haircut.json'),str(reference),'3','1'],check=True,capture_output=True)
        # Compare scalar encodings too: numeric equality hides a lost -0 sign.
        self.assertEqual(json.dumps(result['mesh'],sort_keys=True),
                         json.dumps(loads(reference.read_bytes()),sort_keys=True))
        self.assertEqual(job, self.store.submit('owner', self.session, 'one', self.request))
        self.assertIsNone(run_one(self.store, self.artifacts, self.cli))
        self.assertEqual(self.files.read_result('owner', job), data)
        with self.assertRaises(LookupError): self.files.read_result('other-owner', job)
        output.write_text('{}')
        with self.assertRaises(ValueError): self.files.read_result('owner', job)
        self.store.delete_session('owner', self.session)
        with self.assertRaises(LookupError): self.files.read_result('owner', job)
        self.files.purge_deleted_sessions()
        self.assertFalse((self.artifacts/self.session).exists())

    def test_deletion_at_publication_discards_actual_compiled_output(self):
        job = self.store.submit('owner', self.session, 'one', self.request)
        finish = self.store.finish
        def delete_before_finish(*args, **kwargs):
            self.store.delete_session('owner', self.session)
            return finish(*args, **kwargs)
        with patch.object(self.store, 'finish', side_effect=delete_before_finish):
            result = run_one(self.store, self.artifacts, self.cli)
        self.assertFalse(result['published'])
        self.assertEqual(list((self.artifacts/self.session/'jobs'/job).glob('*/result.json')), [])
        with self.assertRaises(LookupError): self.store.get('owner', job)

    def test_cancellation_at_publication_discards_actual_compiled_output(self):
        job = self.store.submit('owner', self.session, 'one', self.request)
        finish = self.store.finish
        def cancel_before_finish(*args, **kwargs):
            self.store.cancel('owner', job)
            self.store.cancel('owner', job)
            return finish(*args, **kwargs)
        with patch.object(self.store, 'finish', side_effect=cancel_before_finish):
            result = run_one(self.store, self.artifacts, self.cli)
        self.assertFalse(result['published'])
        self.assertEqual(self.store.get('owner', job)['state'], 'cancelled')
        self.assertIsNone(self.store.get('owner', job)['output_hash'])
        self.assertEqual(list((self.artifacts/self.session/'jobs'/job).glob('*/result.json')), [])
        with self.assertRaises(LookupError): self.files.read_result('owner', job)

    def test_corrupt_input_fails_without_compiling(self):
        job = self.store.submit('owner', self.session, 'one', self.request)
        (self.objects/(self.request['haircutSHA256']+'.json')).write_text('{}')
        self.assertFalse(run_one(self.store, self.artifacts, self.cli)['published'])
        self.assertEqual(self.store.get('owner', job)['state'], 'failed')
        self.assertEqual(list((self.artifacts/self.session/'jobs'/job).glob('*/result.json')), [])


if __name__ == '__main__': unittest.main()
