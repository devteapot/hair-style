import hashlib
from pathlib import Path
import tempfile
import unittest
from backend.job_store import JobStore
from backend.uploads import Uploads


class UploadTests(unittest.TestCase):
    def test_reopen_duplicate_chunks_uncommitted_tail_and_finalize(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); store = JobStore(root/'jobs.sqlite')
            try:
                session = store.create_session('owner'); uploads = Uploads(store, root/'artifacts')
                data = b'{"fixture":"abcdefghijk"}'; digest = hashlib.sha256(data).hexdigest()
                row = uploads.start('owner', session, digest, len(data)); identity = row['id']
                self.assertEqual(uploads.start('owner', session, digest, len(data))['id'], identity)
                self.assertEqual(uploads.append('owner', identity, 0, data[:10])['offset'], 10)
                self.assertEqual(uploads.append('owner', identity, 0, data[:10])['offset'], 10)
                with self.assertRaises(ValueError): uploads.append('owner', identity, 0, b'wrong')
                with self.assertRaises(ValueError): uploads.finish('owner', identity)
                partial = uploads._partial(row)
                with partial.open('ab') as stream: stream.write(b'uncommitted tail')
                store.close(); store = JobStore(root/'jobs.sqlite'); uploads = Uploads(store, root/'artifacts')
                self.assertEqual(uploads.status('owner', identity)['offset'], 10)
                uploads.append('owner', identity, 10, data[10:])
                # Simulate rename completion immediately before database commit.
                destination = root/'artifacts'/session/'objects'/(digest+'.json')
                destination.parent.mkdir(); partial.replace(destination)
                self.assertEqual(uploads.finish('owner', identity)['complete'], 1)
                self.assertEqual(uploads.finish('owner', identity)['complete'], 1)
                self.assertEqual(destination.read_bytes(), data)
                with self.assertRaises(LookupError): uploads.status('other', identity)
                store.delete_session('owner', session)
                with self.assertRaises(LookupError): uploads.append('owner', identity, 0, data)
            finally: store.close()

    def test_bad_final_hash_never_publishes_and_can_reset(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); store = JobStore(root/'jobs.sqlite')
            try:
                session = store.create_session('owner'); uploads = Uploads(store, root/'artifacts')
                good = b'{"ok":1}'; bad = b'{"ok":2}'; digest = hashlib.sha256(good).hexdigest()
                identity = uploads.start('owner', session, digest, len(good))['id']
                uploads.append('owner', identity, 0, bad)
                with self.assertRaises(ValueError): uploads.finish('owner', identity)
                self.assertFalse((root/'artifacts'/session/'objects'/(digest+'.json')).exists())
                self.assertEqual(uploads.reset('owner', identity)['offset'], 0)
                uploads.append('owner', identity, 0, good); uploads.finish('owner', identity)
                with self.assertRaises(ValueError): uploads.reset('owner', identity)
            finally: store.close()
