from pathlib import Path
import tempfile
import unittest
import hashlib
from unittest.mock import patch
from backend.artifact_store import ArtifactStore
from backend.job_store import JobStore


class ArtifactStoreTests(unittest.TestCase):
    def test_attempt_cleanup_preserves_live_and_published_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);jobs=JobStore(root/'jobs.sqlite')
            session=jobs.create_session('owner');files=ArtifactStore(jobs,root/'artifacts')
            job=jobs.submit('owner',session,'one',{})
            with patch('backend.job_store.time.time',return_value=1000): first=jobs.claim()
            old=files.root/session/'jobs'/job/first['token'];old.mkdir(parents=True)
            (old/'scratch').write_bytes(b'old')
            files.purge_abandoned_attempts();self.assertTrue(old.exists())
            with patch('backend.job_store.time.time',return_value=1601):
                jobs.recover_expired();second=jobs.claim()
                live=old.parent/second['token'];live.mkdir()
                data=b'{"result":"published"}';(live/'result.json').write_bytes(data)
                files.purge_abandoned_attempts()
                self.assertFalse(old.exists());self.assertTrue(live.exists())
                jobs.finish(job,second['token'],output_hash=hashlib.sha256(data).hexdigest())
            old.mkdir();(old/'late').write_bytes(b'late residue');(old/'result.json').write_bytes(data)
            self.assertEqual(files.read_result('owner',job),data)
            files.purge_abandoned_attempts()
            self.assertFalse(old.exists());self.assertEqual(files.read_result('owner',job),data)
            # No successful legacy result is deleted based on a guessed winner.
            jobs.db.execute('UPDATE jobs SET published_token=NULL WHERE id=?',(job,))
            old.mkdir();(old/'legacy').write_bytes(b'unknown')
            files.purge_abandoned_attempts();self.assertTrue(old.exists())
            jobs.close()

    def test_owner_scope_and_repeatable_full_session_purge(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); jobs = JobStore(root/'jobs.sqlite')
            try:
                a = jobs.create_session('a'); b = jobs.create_session('b')
                files = ArtifactStore(jobs, root/'artifacts')
                h = files.stage('a', a, b'{"fixture":1}')
                files.stage('b', b, b'{"fixture":1}')
                with self.assertRaises(LookupError): files.stage('b', a, b'{}')
                jobs.delete_session('a', a)
                with self.assertRaises(LookupError): files.stage('a', a, b'{}')
                files.purge_deleted_sessions()
                self.assertFalse((files.root/a).exists())
                self.assertTrue((files.root/b/'objects'/(h+'.json')).exists())
                # Simulate residue from an interrupted old worker, never served.
                (files.root/a/'jobs').mkdir(parents=True)
                (files.root/a/'jobs'/'residue').write_bytes(b'fixture')
                files.purge_deleted_sessions()
                self.assertFalse((files.root/a).exists())
            finally: jobs.close()
