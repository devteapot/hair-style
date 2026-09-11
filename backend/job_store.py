"""Local job persistence. Owner IDs must come from a trusted authentication layer.

No HTTP authentication, model execution, asset serving or storage purge is supplied.
Worker leases fence late results; recovery is bounded to three attempts.
"""
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import secrets
import sqlite3
import time
import uuid


class JobStore:
    LEASE_SECONDS = 600
    MAX_ATTEMPTS = 3
    def __init__(self, path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.db = sqlite3.connect(path, isolation_level=None, timeout=10)
        os.chmod(path, 0o600)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA foreign_keys=ON')
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS guests (owner TEXT PRIMARY KEY, token_hash TEXT NOT NULL UNIQUE);
        CREATE TABLE IF NOT EXISTS sessions (
          id TEXT PRIMARY KEY, owner TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
          latest_job TEXT, selected_job TEXT, creation_key TEXT);
        CREATE TABLE IF NOT EXISTS purge_queue (session_id TEXT NOT NULL, artifact_hash TEXT NOT NULL, PRIMARY KEY(session_id,artifact_hash));
        CREATE TABLE IF NOT EXISTS jobs (
          id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id),
          request_key TEXT NOT NULL, request_hash TEXT NOT NULL, request_json TEXT NOT NULL,
          state TEXT NOT NULL, stage TEXT NOT NULL, attempt_token TEXT,
          checkpoint TEXT, output_hash TEXT, failure_code TEXT,
          created REAL NOT NULL, updated REAL NOT NULL,
          UNIQUE(session_id,request_key));
        ''')
        with self.transaction():
            columns = {row['name'] for row in self.db.execute('PRAGMA table_info(sessions)')}
            if 'creation_key' not in columns:
                self.db.execute('ALTER TABLE sessions ADD COLUMN creation_key TEXT')
            self.db.execute('CREATE UNIQUE INDEX IF NOT EXISTS session_creation_key ON sessions(owner,creation_key)')
            columns = {row['name'] for row in self.db.execute('PRAGMA table_info(jobs)')}
            if 'lease_expires' not in columns:
                self.db.execute('ALTER TABLE jobs ADD COLUMN lease_expires REAL')
                self.db.execute("UPDATE jobs SET lease_expires=updated+? WHERE state IN ('running','cancel_requested')", (self.LEASE_SECONDS,))
            if 'attempt_count' not in columns:
                self.db.execute('ALTER TABLE jobs ADD COLUMN attempt_count INTEGER NOT NULL DEFAULT 0')
                self.db.execute("UPDATE jobs SET attempt_count=1 WHERE state IN ('running','cancel_requested')")
            if 'published_token' not in columns:
                self.db.execute('ALTER TABLE jobs ADD COLUMN published_token TEXT')

    def close(self):
        self.db.close()

    @contextmanager
    def transaction(self):
        self.db.execute('BEGIN IMMEDIATE')
        try:
            yield
            self.db.execute('COMMIT')
        except BaseException:
            self.db.execute('ROLLBACK')
            raise

    def _session(self, owner, session_id):
        row = self.db.execute('SELECT * FROM sessions WHERE id=? AND owner=? AND deleted=0',
                              (session_id, owner)).fetchone()
        if row is None:
            raise LookupError('Session unavailable')
        return row

    def create_session(self, owner, request_key=None):
        if not isinstance(owner, str) or not 1 <= len(owner) <= 128:
            raise ValueError('Invalid trusted owner ID')
        key = str(uuid.uuid4()) if request_key is None else request_key
        if not isinstance(key, str) or not 1 <= len(key) <= 128:
            raise ValueError('Invalid session creation key')
        with self.transaction():
            existing = self.db.execute('SELECT id,deleted FROM sessions WHERE owner=? AND creation_key=?',
                                       (owner, key)).fetchone()
            if existing:
                if existing['deleted']: raise LookupError('Session unavailable')
                return existing['id']
            identity = str(uuid.uuid4())
            self.db.execute('INSERT INTO sessions(id,owner,creation_key) VALUES (?,?,?)', (identity, owner, key))
            return identity

    def submit(self, owner, session_id, request_key, request):
        if not isinstance(request_key, str) or not 1 <= len(request_key) <= 128:
            raise ValueError('Invalid idempotency key')
        if not isinstance(request, dict):
            raise ValueError('Expected structured request')
        encoded = json.dumps(request, sort_keys=True, separators=(',', ':'), allow_nan=False)
        if len(encoded.encode()) > 65536:
            raise ValueError('Request exceeds 64 KiB')
        digest = hashlib.sha256(encoded.encode()).hexdigest()
        with self.transaction():
            self._session(owner, session_id)
            old = self.db.execute('SELECT * FROM jobs WHERE session_id=? AND request_key=?',
                                  (session_id, request_key)).fetchone()
            if old:
                if old['request_hash'] != digest:
                    raise ValueError('Idempotency key was already used for different input')
                return old['id']
            identity = str(uuid.uuid4()); now = time.time()
            self.db.execute('''INSERT INTO jobs(id,session_id,request_key,request_hash,request_json,
                state,stage,created,updated) VALUES (?,?,?,?,?,'queued','queued',?,?)''',
                (identity, session_id, request_key, digest, encoded, now, now))
            self.db.execute('UPDATE sessions SET latest_job=? WHERE id=?', (identity, session_id))
            return identity

    def get(self, owner, job_id):
        row = self.db.execute('''SELECT j.* FROM jobs j JOIN sessions s ON j.session_id=s.id
             WHERE j.id=? AND s.owner=? AND s.deleted=0''', (job_id, owner)).fetchone()
        if row is None:
            raise LookupError('Job unavailable')
        result = dict(row)
        result.pop('attempt_token')  # Worker fencing token is not a client credential.
        result.pop('lease_expires')
        result.pop('published_token')
        return result

    def selected(self, owner, session_id):
        row = self._session(owner, session_id)
        return self.get(owner, row['selected_job']) if row['selected_job'] else None

    def claim(self):
        """Trusted worker only. Atomically claims a queued job exactly once."""
        with self.transaction():
            row = self.db.execute('''SELECT j.* FROM jobs j JOIN sessions s ON j.session_id=s.id
                WHERE j.state='queued' AND s.deleted=0 ORDER BY j.created,j.id LIMIT 1''').fetchone()
            if row is None:
                return None
            token = secrets.token_hex(32)
            now=time.time()
            self.db.execute("UPDATE jobs SET state='running',stage='starting',attempt_token=?,updated=?,lease_expires=?,attempt_count=attempt_count+1 WHERE id=?",
                            (token, now, now+self.LEASE_SECONDS, row['id']))
            return dict(id=row['id'], session_id=row['session_id'], token=token, request=json.loads(row['request_json']),
                        checkpoint=row['checkpoint'])

    def recover_expired(self):
        """Trusted scheduler: revoke expired attempts before retrying from original inputs."""
        now=time.time(); recovered=[]
        with self.transaction():
            rows=self.db.execute('''SELECT j.* FROM jobs j JOIN sessions s ON j.session_id=s.id
                WHERE j.state IN ('running','cancel_requested') AND j.lease_expires<=? AND s.deleted=0''',(now,)).fetchall()
            for row in rows:
                state=('cancelled' if row['state']=='cancel_requested' else
                       'failed' if row['attempt_count']>=self.MAX_ATTEMPTS else 'queued')
                self.db.execute('''UPDATE jobs SET state=?,stage=?,attempt_token=NULL,lease_expires=NULL,
                    checkpoint=NULL,failure_code=?,updated=? WHERE id=?''',
                    (state,'queued' if state=='queued' else 'finished',
                     'budget_exhausted' if state=='failed' else None,now,row['id']))
                recovered.append(dict(job=row['id'],state=state))
        return recovered

    @staticmethod
    def _hash(value):
        if not isinstance(value, str) or len(value) != 64 or any(c not in '0123456789abcdef' for c in value):
            raise ValueError('Expected SHA-256 artifact reference')

    def checkpoint(self, job_id, token, stage, artifact_hash):
        self._hash(artifact_hash)
        if stage not in ('reconstructing', 'generating', 'compiling', 'validating'):
            raise ValueError('Unknown processing stage')
        with self.transaction():
            now=time.time()
            changed = self.db.execute('''UPDATE jobs SET stage=?,checkpoint=?,updated=?,lease_expires=?
                WHERE id=? AND attempt_token=? AND state='running'
                AND lease_expires>?
                AND session_id IN (SELECT id FROM sessions WHERE deleted=0)''',
                (stage, artifact_hash, now,now+self.LEASE_SECONDS,job_id,token,now)).rowcount
            return changed == 1

    def attempt_active(self, job_id, token):
        return self.db.execute('''SELECT 1 FROM jobs j JOIN sessions s ON j.session_id=s.id
            WHERE j.id=? AND j.attempt_token=? AND j.state='running'
            AND j.lease_expires>? AND s.deleted=0''',(job_id,token,time.time())).fetchone() is not None

    def finish(self, job_id, token, output_hash=None, failure_code=None):
        if (output_hash is None) == (failure_code is None):
            raise ValueError('Supply one output or failure')
        if output_hash is not None:
            self._hash(output_hash)
        if failure_code is not None and failure_code not in ('generation_failed', 'constraint_violation', 'input_incomplete', 'budget_exhausted'):
            raise ValueError('Unknown failure code')
        with self.transaction():
            row = self.db.execute('''SELECT j.* FROM jobs j JOIN sessions s ON j.session_id=s.id
                WHERE j.id=? AND j.attempt_token=? AND j.state IN ('running','cancel_requested') AND s.deleted=0
                AND j.lease_expires>?''',
                (job_id, token,time.time())).fetchone()
            if row is None:
                return False  # Late or cancelled result must not be published.
            if row['state'] == 'cancel_requested':
                self.db.execute("UPDATE jobs SET state='cancelled',attempt_token=NULL,updated=? WHERE id=?",
                                (time.time(), job_id))
                return False
            self.db.execute('''UPDATE jobs SET state=?,stage='finished',output_hash=?,failure_code=?,
                attempt_token=NULL,published_token=?,updated=? WHERE id=?''',
                ('succeeded' if output_hash else 'failed', output_hash, failure_code, token if output_hash else None, time.time(), job_id))
            if output_hash:
                self.db.execute('UPDATE sessions SET selected_job=? WHERE id=? AND latest_job=?',
                                (job_id, row['session_id'], job_id))
            return True

    def cancel(self, owner, job_id):
        with self.transaction():
            self.get(owner, job_id)
            self.db.execute("""UPDATE jobs SET state=CASE WHEN state='running' THEN 'cancel_requested' ELSE 'cancelled' END,
                attempt_token=CASE WHEN state='running' THEN attempt_token ELSE NULL END,updated=?
                WHERE id=? AND state IN ('queued','running')""", (time.time(), job_id))

    def delete_session(self, owner, session_id):
        with self.transaction():
            row = self.db.execute('SELECT deleted FROM sessions WHERE id=? AND owner=?', (session_id, owner)).fetchone()
            if row is None: raise LookupError('Session unavailable')
            if row['deleted']: return []
            # Return refs for the future storage purger; this transaction revokes metadata access.
            refs = self.db.execute('SELECT checkpoint,output_hash FROM jobs WHERE session_id=?', (session_id,)).fetchall()
            for row in refs:
                for value in row:
                    if value is not None:
                        self.db.execute('INSERT OR IGNORE INTO purge_queue VALUES (?,?)', (session_id, value))
            self.db.execute('UPDATE sessions SET deleted=1,latest_job=NULL,selected_job=NULL WHERE id=?', (session_id,))
            self.db.execute("""UPDATE jobs SET state='cancelled',attempt_token=NULL,request_json='{}',
                checkpoint=NULL,output_hash=NULL,published_token=NULL,lease_expires=NULL,updated=? WHERE session_id=?""", (time.time(), session_id))
            return sorted({value for row in refs for value in row if value is not None})

    def pending_purge(self):
        """Trusted storage worker only; deletion is not complete until storage confirms it."""
        return [dict(row) for row in self.db.execute('SELECT session_id,artifact_hash FROM purge_queue ORDER BY session_id,artifact_hash')]

    def create_guest(self):
        owner = str(uuid.uuid4()); token = secrets.token_urlsafe(32)
        digest = hashlib.sha256(token.encode()).hexdigest()
        self.db.execute('INSERT INTO guests(owner,token_hash) VALUES (?,?)', (owner, digest))
        return dict(owner=owner, token=token)

    def authenticate(self, token):
        if not isinstance(token, str) or not 32 <= len(token) <= 128:
            raise PermissionError('Authentication required')
        digest = hashlib.sha256(token.encode()).hexdigest()
        row = self.db.execute('SELECT owner FROM guests WHERE token_hash=?', (digest,)).fetchone()
        if row is None:
            raise PermissionError('Authentication required')
        return row['owner']
