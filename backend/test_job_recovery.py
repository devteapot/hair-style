import tempfile
from pathlib import Path
import unittest
import subprocess
import sys
from unittest.mock import patch
from backend.job_store import JobStore


class JobRecoveryTests(unittest.TestCase):
    def test_abrupt_process_exit_preserves_recoverable_claim(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'jobs.sqlite'
            store=JobStore(path);session=store.create_session('owner')
            job=store.submit('owner',session,'one',{'input':'durable'});store.close()
            result=subprocess.run([sys.executable,'-c',
                'import os,sys; from backend.job_store import JobStore; s=JobStore(sys.argv[1]); s.claim(); os._exit(9)',str(path)],timeout=10)
            self.assertEqual(result.returncode,9)
            store=JobStore(path)
            self.assertEqual(store.get('owner',job)['state'],'running')
            row=store.db.execute('SELECT attempt_token,lease_expires FROM jobs WHERE id=?',(job,)).fetchone()
            with patch('backend.job_store.time.time',return_value=row['lease_expires']+1):
                self.assertEqual(store.recover_expired(),[dict(job=job,state='queued')])
                replacement=store.claim()
                self.assertEqual(replacement['id'],job)
                self.assertEqual(replacement['request'],{'input':'durable'})
                self.assertFalse(store.finish(job,row['attempt_token'],output_hash='a'*64))
                self.assertTrue(store.finish(job,replacement['token'],output_hash='b'*64))
            store.close()

    def test_expired_worker_cannot_renew_or_publish_after_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            store=JobStore(Path(directory)/'jobs.sqlite')
            session=store.create_session('owner')
            job=store.submit('owner',session,'one',{'input':'original'})
            with patch('backend.job_store.time.time',return_value=1000): first=store.claim()
            with patch('backend.job_store.time.time',return_value=1600):
                self.assertFalse(store.checkpoint(job,first['token'],'generating','a'*64))
                self.assertFalse(store.finish(job,first['token'],output_hash='a'*64))
                self.assertEqual(store.recover_expired(),[dict(job=job,state='queued')])
                second=store.claim()
                self.assertEqual(second['request'],first['request'])
                self.assertNotEqual(second['token'],first['token'])
                self.assertFalse(store.finish(job,first['token'],output_hash='a'*64))
                self.assertTrue(store.finish(job,second['token'],output_hash='b'*64))
                self.assertEqual(store.selected('owner',session)['output_hash'],'b'*64)
            store.close()

    def test_recovery_is_bounded_and_cancelled_attempts_are_not_retried(self):
        with tempfile.TemporaryDirectory() as directory:
            store=JobStore(Path(directory)/'jobs.sqlite');session=store.create_session('owner')
            job=store.submit('owner',session,'one',{})
            for n in range(3):
                with patch('backend.job_store.time.time',return_value=n*601):
                    self.assertIsNotNone(store.claim())
                with patch('backend.job_store.time.time',return_value=(n+1)*601):
                    store.recover_expired()
            self.assertEqual(store.get('owner',job)['failure_code'],'budget_exhausted')
            self.assertIsNone(store.claim())
            cancelled=store.submit('owner',session,'cancel',{})
            with patch('backend.job_store.time.time',return_value=3000):
                store.claim();store.cancel('owner',cancelled)
            with patch('backend.job_store.time.time',return_value=3601):
                store.recover_expired()
            self.assertEqual(store.get('owner',cancelled)['state'],'cancelled')
            self.assertIsNone(store.claim());store.close()

    def test_checkpoint_renews_live_lease(self):
        with tempfile.TemporaryDirectory() as directory:
            store=JobStore(Path(directory)/'jobs.sqlite');session=store.create_session('owner')
            job=store.submit('owner',session,'one',{})
            with patch('backend.job_store.time.time',return_value=100):attempt=store.claim()
            with patch('backend.job_store.time.time',return_value=600):
                self.assertTrue(store.checkpoint(job,attempt['token'],'validating','a'*64))
            with patch('backend.job_store.time.time',return_value=701):
                self.assertEqual(store.recover_expired(),[])
                self.assertTrue(store.finish(job,attempt['token'],output_hash='b'*64))
            store.close()
