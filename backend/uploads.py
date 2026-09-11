"""Sequential resumable local uploads with idempotent chunk retries."""
import hashlib
import json
import os
import uuid
from .artifact_store import ArtifactStore
from .job_store import JobStore


class Uploads:
    chunk_limit = 1_048_576

    def __init__(self, jobs, root):
        self.jobs = jobs; self.files = ArtifactStore(jobs, root)
        jobs.db.execute('''CREATE TABLE IF NOT EXISTS uploads (
            id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id),
            digest TEXT NOT NULL, size INTEGER NOT NULL, offset INTEGER NOT NULL DEFAULT 0,
            complete INTEGER NOT NULL DEFAULT 0, UNIQUE(session_id,digest))''')

    def _get(self, owner, identity):
        row = self.jobs.db.execute('''SELECT u.* FROM uploads u JOIN sessions s ON u.session_id=s.id
            WHERE u.id=? AND s.owner=? AND s.deleted=0''', (identity, owner)).fetchone()
        if row is None: raise LookupError('Upload unavailable')
        return dict(row)

    def _partial(self, row):
        directory = self.files._session_path(row['session_id'])/'uploads'
        if directory.is_symlink(): raise ValueError('Invalid upload directory')
        path = directory/(row['id']+'.part')
        if path.is_symlink(): raise ValueError('Invalid partial file')
        return path

    def start(self, owner, session, digest, size):
        JobStore._hash(digest)
        if type(size) is not int or not 0 < size <= 100_000_000:
            raise ValueError('Invalid upload size')
        with self.jobs.transaction():
            self.jobs._session(owner, session)
            row = self.jobs.db.execute('SELECT id,size FROM uploads WHERE session_id=? AND digest=?',
                                      (session, digest)).fetchone()
            if row:
                if row['size'] != size: raise ValueError('Conflicting upload size')
                return self._get(owner, row['id'])
            identity = str(uuid.uuid4())
            self.jobs.db.execute('INSERT INTO uploads(id,session_id,digest,size) VALUES (?,?,?,?)',
                                (identity, session, digest, size))
            return self._get(owner, identity)

    def status(self, owner, identity):
        return self._get(owner, identity)

    def append(self, owner, identity, offset, data):
        if type(offset) is not int or offset < 0 or not isinstance(data, bytes) or not 0 < len(data) <= self.chunk_limit:
            raise ValueError('Invalid chunk')
        with self.jobs.transaction():
            row = self._get(owner, identity)
            if row['complete']: raise ValueError('Upload already finalized')
            path = self._partial(row)
            if offset < row['offset'] and offset+len(data) <= row['offset']:
                with path.open('rb') as stream:
                    stream.seek(offset)
                    if stream.read(len(data)) != data: raise ValueError('Conflicting retry bytes')
                return row
            if offset != row['offset'] or offset+len(data) > row['size']:
                raise ValueError('Offset or total size mismatch')
            path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            if row['offset'] and (not path.exists() or path.stat().st_size < row['offset']):
                raise ValueError('Partial file is missing committed bytes')
            with path.open('r+b' if path.exists() else 'w+b') as stream:
                # Discard a tail written before a prior interrupted SQLite commit.
                stream.truncate(offset); stream.seek(offset); stream.write(data)
                stream.flush(); os.fsync(stream.fileno())
            self.jobs.db.execute('UPDATE uploads SET offset=? WHERE id=?', (offset+len(data), identity))
            return self._get(owner, identity)

    def finish(self, owner, identity):
        with self.jobs.transaction():
            row = self._get(owner, identity)
            if row['offset'] != row['size']: raise ValueError('Upload incomplete')
            objects = self.files._session_path(row['session_id'])/'objects'
            if objects.is_symlink(): raise ValueError('Invalid object directory')
            destination = objects/(row['digest']+'.json')
            if destination.is_symlink(): raise ValueError('Invalid object')
            partial = self._partial(row)
            # A crash after rename but before SQL commit can be recovered from the object.
            source = partial if partial.exists() else destination
            if not source.is_file() or source.stat().st_size != row['size']:
                raise ValueError('Upload bytes missing')
            data = source.read_bytes()
            if hashlib.sha256(data).hexdigest() != row['digest'] or not isinstance(json.loads(data), dict):
                raise ValueError('Final content validation failed')
            objects.mkdir(parents=True, exist_ok=True, mode=0o700)
            if source != destination:
                if destination.exists() and destination.read_bytes() != data:
                    raise ValueError('Existing object is corrupt')
                partial.replace(destination)
            self.jobs.db.execute('UPDATE uploads SET complete=1 WHERE id=?', (identity,))
            return self._get(owner, identity)

    def reset(self, owner, identity):
        with self.jobs.transaction():
            row = self._get(owner, identity)
            if row['complete']: raise ValueError('Finalized object cannot be reset')
            self._partial(row).unlink(missing_ok=True)
            self.jobs.db.execute('UPDATE uploads SET offset=0 WHERE id=?', (identity,))
            return self._get(owner, identity)
