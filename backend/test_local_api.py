import json
import hashlib
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from backend.local_api import make_server
from backend.compile_worker import run_one
from backend.job_store import JobStore


class LocalAPITests(unittest.TestCase):
    def test_two_guest_identities_compile_and_revoke_results_over_http(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); database = root/'jobs.sqlite'; artifacts = root/'artifacts'
            server = make_server(database, artifacts)
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            address = f'http://127.0.0.1:{server.server_port}'
            def call(method, path, token=None, body=None, key=None, offset=None):
                headers = {'Content-Type': 'application/json'}
                if token: headers['Authorization'] = 'Bearer '+token
                if key: headers['Idempotency-Key'] = key
                if offset is not None: headers['Upload-Offset'] = str(offset)
                encoded = body if isinstance(body, bytes) else json.dumps(body).encode() if body is not None else None
                request = Request(address+path, data=encoded, headers=headers, method=method)
                try: response = urlopen(request, timeout=10)
                except HTTPError as error: response = error
                with response: return response.status, json.loads(response.read())
            try:
                a = call('POST', '/v1/guests')[1]['token']; b = call('POST', '/v1/guests')[1]['token']
                self.assertEqual(call('POST', '/v1/sessions')[0], 401)
                session = call('POST', '/v1/sessions', a, key='session-key')[1]['id']
                self.assertEqual(call('POST', '/v1/sessions', a, key='session-key')[1]['id'], session)
                cli = Path('.build/debug/capture-inspect').resolve()
                subprocess.run([str(cli), 'hair-fixture', str(root/'fixture')], check=True, capture_output=True)
                request = dict(schemaVersion=1, kind='compile_hair')
                for name, key in [('input.json','inputSHA256'), ('haircut.json','haircutSHA256')]:
                    data = (root/'fixture'/name).read_bytes()
                    self.assertEqual(call('PUT', f'/v1/sessions/{session}/objects', b, data)[0], 404)
                    if name == 'input.json':
                        declaration = dict(sha256=hashlib.sha256(data).hexdigest(), size=len(data))
                        status, upload = call('POST', f'/v1/sessions/{session}/uploads', a, declaration)
                        self.assertEqual(status, 201); path = '/v1/uploads/'+upload['id']
                        self.assertEqual(call('GET', path, b)[0], 404)
                        half = len(data)//2
                        self.assertEqual(call('PUT', path, a, data[:half], offset=0)[1]['offset'], half)
                        self.assertEqual(call('PUT', path, a, data[:half], offset=0)[1]['offset'], half)
                        self.assertEqual(call('GET', path, a)[1]['offset'], half)
                        self.assertEqual(call('POST', path+'/complete', a)[0], 400)
                        self.assertEqual(call('PUT', path, a, data[half:], offset=half)[0], 200)
                        self.assertEqual(call('POST', path+'/complete', a)[1]['complete'], 1)
                        request[key] = declaration['sha256']
                    else:
                        status, result = call('PUT', f'/v1/sessions/{session}/objects', a, data)
                        self.assertEqual(status, 201); request[key] = result['sha256']
                path = f'/v1/sessions/{session}/jobs'
                job = call('POST', path, a, request, 'once')[1]['id']
                self.assertEqual(call('POST', path, a, request, 'once')[1]['id'], job)
                self.assertEqual(call('GET', f'/v1/jobs/{job}', b)[0], 404)
                self.assertEqual(call('GET', '/v1/jobs/unknown', b)[0], 404)
                store = JobStore(database)
                try: self.assertTrue(run_one(store, artifacts, cli)['published'])
                finally: store.close()
                status, output = call('GET', f'/v1/jobs/{job}/result', a)
                self.assertEqual(status, 200); self.assertFalse(output['personalStyleVerified'])
                self.assertEqual(call('GET', f'/v1/jobs/{job}/result', b)[0], 404)
                self.assertEqual(call('DELETE', f'/v1/sessions/{session}', b)[0], 404)
                self.assertEqual(call('DELETE', f'/v1/sessions/{session}', a)[0], 202)
                self.assertEqual(call('GET', f'/v1/jobs/{job}/result', a)[0], 404)
                self.assertFalse((artifacts/session).exists())
                self.assertEqual(call('DELETE', f'/v1/sessions/{session}', a)[0], 202)
                self.assertEqual(call('POST', '/v1/sessions', a, key='session-key')[0], 404)
                self.assertEqual(call('POST', path, a, request, 'again')[0], 404)
                store = JobStore(database)
                try:
                    self.assertNotEqual(store.authenticate(a), store.authenticate(b))
                    hashes = [row[0] for row in store.db.execute('SELECT token_hash FROM guests')]
                    self.assertNotIn(a, hashes); self.assertNotIn(b, hashes)
                finally: store.close()
            finally:
                server.shutdown(); server.server_close(); thread.join()


if __name__ == '__main__': unittest.main()
