from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import tempfile
import sqlite3
import unittest
from backend.job_store import JobStore


class JobStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'jobs.sqlite'
        self.store = JobStore(self.path)
        self.session = self.store.create_session('owner-a')

    def tearDown(self):
        self.store.close(); self.temp.cleanup()

    def test_session_creation_retry_is_atomic_and_deleted_session_stays_deleted(self):
        def create(_):
            store = JobStore(self.path)
            try: return store.create_session('owner-a', 'stable-session-key')
            finally: store.close()
        with ThreadPoolExecutor(max_workers=2) as pool:
            sessions = list(pool.map(create, range(2)))
        self.assertEqual(sessions[0], sessions[1])
        self.assertNotEqual(sessions[0], self.store.create_session('owner-b', 'stable-session-key'))
        self.store.delete_session('owner-a', sessions[0])
        self.assertEqual(self.store.delete_session('owner-a', sessions[0]), [])
        with self.assertRaises(LookupError): self.store.create_session('owner-a', 'stable-session-key')
        with self.assertRaises(LookupError): self.store.delete_session('owner-b', sessions[0])

    def test_creation_key_migration_preserves_existing_session(self):
        path = self.path.parent/'legacy.sqlite'
        connection = sqlite3.connect(path)
        connection.execute('CREATE TABLE sessions (id TEXT PRIMARY KEY, owner TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, latest_job TEXT, selected_job TEXT)')
        connection.execute("INSERT INTO sessions VALUES ('legacy','owner-a',0,NULL,NULL)")
        connection.commit(); connection.close()
        store = JobStore(path)
        try:
            self.assertEqual(store._session('owner-a', 'legacy')['id'], 'legacy')
            first = store.create_session('owner-a', 'key')
            self.assertEqual(first, store.create_session('owner-a', 'key'))
        finally: store.close()

    def test_concurrent_duplicate_submission_and_claim_survive_reopen(self):
        def submit(_):
            store = JobStore(self.path)
            try: return store.submit('owner-a', self.session, 'same-key', {'seed': 42})
            finally: store.close()
        with ThreadPoolExecutor(max_workers=2) as pool:
            jobs = list(pool.map(submit, range(2)))
        self.assertEqual(jobs[0], jobs[1])
        with self.assertRaises(ValueError):
            self.store.submit('owner-a', self.session, 'same-key', {'seed': 43})
        first = self.store.claim(); self.assertIsNotNone(first)
        self.store.close(); self.store = JobStore(self.path)
        self.assertIsNone(self.store.claim())  # Unknown worker outcome never silently reruns.
        self.assertEqual(self.store.get('owner-a', jobs[0])['state'], 'running')
        self.assertTrue(self.store.finish(jobs[0], first['token'], output_hash='a'*64))
        self.assertFalse(self.store.finish(jobs[0], first['token'], output_hash='b'*64))

    def test_out_of_order_success_and_failure_preserve_selection(self):
        old = self.store.submit('owner-a', self.session, 'old', {'seed': 1}); a = self.store.claim()
        new = self.store.submit('owner-a', self.session, 'new', {'seed': 2}); b = self.store.claim()
        self.assertTrue(self.store.finish(new, b['token'], output_hash='b'*64))
        self.assertTrue(self.store.finish(old, a['token'], output_hash='a'*64))
        self.assertEqual(self.store.selected('owner-a', self.session)['id'], new)
        failure = self.store.submit('owner-a', self.session, 'failure', {'seed': 3}); c = self.store.claim()
        self.store.finish(failure, c['token'], failure_code='generation_failed')
        self.assertEqual(self.store.selected('owner-a', self.session)['id'], new)
        self.assertEqual(self.store.get('owner-a', old)['output_hash'], 'a'*64)

    def test_cancellation_deletion_and_other_owner_reject_late_results(self):
        job = self.store.submit('owner-a', self.session, 'one', {}); attempt = self.store.claim()
        for operation in [lambda: self.store.get('owner-b', job),
                          lambda: self.store.cancel('owner-b', job),
                          lambda: self.store.delete_session('owner-b', self.session)]:
            with self.assertRaises(LookupError): operation()
        self.assertNotIn('attempt_token', self.store.get('owner-a', job))
        self.assertFalse(self.store.finish(job, 'wrong-token', output_hash='a'*64))
        self.store.cancel('owner-a', job)
        self.assertEqual(self.store.get('owner-a', job)['state'], 'cancel_requested')
        self.assertFalse(self.store.finish(job, attempt['token'], output_hash='a'*64))
        self.assertEqual(self.store.get('owner-a', job)['state'], 'cancelled')
        second = self.store.submit('owner-a', self.session, 'two', {}); attempt = self.store.claim()
        self.assertTrue(self.store.checkpoint(second, attempt['token'], 'generating', 'c'*64))
        self.assertEqual(self.store.delete_session('owner-a', self.session), ['c'*64])
        self.store.close(); self.store = JobStore(self.path)
        self.assertEqual(self.store.pending_purge(), [dict(session_id=self.session, artifact_hash='c'*64)])
        self.assertFalse(self.store.finish(second, attempt['token'], output_hash='d'*64))
        with self.assertRaises(LookupError): self.store.get('owner-a', second)
        with self.assertRaises(LookupError): self.store.submit('owner-a', self.session, 'three', {})


if __name__ == '__main__': unittest.main()
