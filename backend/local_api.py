"""Development API bound to loopback only. No TLS, public hosting or worker launch."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
from urllib.parse import urlsplit
from .artifact_store import ArtifactStore
from .job_store import JobStore
from .uploads import Uploads


def make_server(database, artifacts, port=0):
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup(); self.connection.settimeout(10)

        def log_message(self, format, *args):
            pass  # Never log authorization headers or request bodies.

        def send_json(self, status, value):
            data = json.dumps(value, separators=(',', ':'), allow_nan=False).encode()
            self.send_bytes(status, data)

        def send_bytes(self, status, data):
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.end_headers(); self.wfile.write(data)

        def body(self, maximum=65536):
            if self.headers.get('Transfer-Encoding'):
                raise ValueError('Chunked requests unsupported')
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 <= length <= maximum:
                raise ValueError('Request exceeds byte limit')
            data = self.rfile.read(length)
            if len(data) != length:
                raise ValueError('Incomplete request')
            return data

        def handle_request(self):
            store = JobStore(database)
            try:
                parsed = urlsplit(self.path)
                if parsed.query or parsed.fragment:
                    raise ValueError('Unexpected query')
                path = parsed.path.strip('/').split('/')
                if self.command == 'POST' and path == ['v1', 'guests']:
                    if self.body() not in (b'', b'{}'):
                        raise ValueError('Guest creation takes no identity input')
                    return self.send_json(201, store.create_guest())
                authorization = self.headers.get('Authorization', '')
                if not authorization.startswith('Bearer '):
                    raise PermissionError('Authentication required')
                owner = store.authenticate(authorization[7:])
                files = ArtifactStore(store, artifacts)
                if path == ['v1', 'sessions'] and self.command == 'POST':
                    if self.body() not in (b'', b'{}'):
                        raise ValueError('Session creation takes no owner input')
                    return self.send_json(201, dict(id=store.create_session(owner, self.headers.get('Idempotency-Key'))))
                if len(path) in (3,4) and path[:2] == ['v1', 'uploads']:
                    uploads = Uploads(store, artifacts); identity = path[2]
                    if len(path) == 3 and self.command == 'GET':
                        return self.send_json(200, uploads.status(owner, identity))
                    if len(path) == 3 and self.command == 'PUT':
                        uploads.status(owner, identity)
                        result = uploads.append(owner, identity, int(self.headers.get('Upload-Offset', '-1')),
                                                self.body(uploads.chunk_limit))
                        return self.send_json(200, result)
                    if path[3:] == ['reset'] and self.command == 'POST':
                        if self.body() not in (b'', b'{}'): raise ValueError('Unexpected reset body')
                        return self.send_json(200, uploads.reset(owner, identity))
                    if path[3:] == ['complete'] and self.command == 'POST':
                        if self.body() not in (b'', b'{}'): raise ValueError('Unexpected finalization body')
                        return self.send_json(200, uploads.finish(owner, identity))
                if len(path) == 4 and path[:2] == ['v1', 'sessions']:
                    session, action = path[2:]
                    if self.command == 'POST' and action == 'uploads':
                        value = json.loads(self.body())
                        if not isinstance(value, dict) or set(value) != {'sha256', 'size'}:
                            raise ValueError('Invalid upload declaration')
                        return self.send_json(201, Uploads(store, artifacts).start(owner, session, value['sha256'], value['size']))
                    if self.command == 'PUT' and action == 'objects':
                        # Authorize before reading a potentially large body.
                        store._session(owner, session)
                        return self.send_json(201, dict(sha256=files.stage(owner, session, self.body(100_000_000))))
                    if self.command == 'POST' and action == 'jobs':
                        request = json.loads(self.body())
                        job = store.submit(owner, session, self.headers.get('Idempotency-Key'), request)
                        return self.send_json(202, dict(id=job))
                if len(path) == 3 and path[:2] == ['v1', 'sessions'] and self.command == 'DELETE':
                    store.delete_session(owner, path[2])
                    files.purge_deleted_sessions()
                    return self.send_json(202, dict(state='deleted', accessRevoked=True))
                if len(path) >= 3 and path[:2] == ['v1', 'jobs']:
                    job = path[2]
                    if len(path) == 3 and self.command == 'GET':
                        record = store.get(owner, job)
                        # The client already owns its submitted data; status needs no raw input.
                        record.pop('request_json')
                        return self.send_json(200, record)
                    if path[3:] == ['result'] and self.command == 'GET':
                        return self.send_bytes(200, files.read_result(owner, job))
                    if path[3:] == ['cancel'] and self.command == 'POST':
                        if self.body() not in (b'', b'{}'):
                            raise ValueError('Cancellation takes no input')
                        store.cancel(owner, job)
                        return self.send_json(202, dict(state=store.get(owner, job)['state']))
                self.send_json(404, dict(error='unavailable'))
            except PermissionError:
                self.send_json(401, dict(error='authentication_required'))
            except LookupError:
                self.send_json(404, dict(error='unavailable'))
            except (ValueError, UnicodeError):
                self.send_json(400, dict(error='invalid_request'))
            except Exception:
                self.send_json(500, dict(error='operation_failed'))
            finally:
                store.close()

        do_POST = handle_request
        do_PUT = handle_request
        do_GET = handle_request
        do_DELETE = handle_request

    return ThreadingHTTPServer(('127.0.0.1', port), Handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('database', type=Path); parser.add_argument('artifacts', type=Path)
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args(); server = make_server(args.database, args.artifacts, args.port)
    print('Local development API on 127.0.0.1:' + str(server.server_port), flush=True)
    try: server.serve_forever()
    finally: server.server_close()


if __name__ == '__main__': main()
