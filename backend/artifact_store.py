"""Owner-checked local staging/reads and repeatable session tombstone purging.

The configured root and local worker processes are trusted. This is not HTTP auth.
"""
import hashlib
import json
from pathlib import Path
import shutil
import uuid


class ArtifactStore:
    def __init__(self, jobs, root):
        self.jobs = jobs
        self.root = Path(root).resolve()
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)

    def _session_path(self, identity):
        if str(uuid.UUID(identity)) != identity:
            raise ValueError('Invalid session directory identity')
        path = self.root / identity
        if path.is_symlink():
            raise ValueError('Session directory cannot be a symlink')
        return path

    def stage(self, owner, session, data):
        if not isinstance(data, bytes) or not 0 < len(data) <= 100_000_000:
            raise ValueError('Invalid artifact byte budget')
        if not isinstance(json.loads(data), dict):
            raise ValueError('Expected a JSON object')
        digest = hashlib.sha256(data).hexdigest()
        with self.jobs.transaction():
            self.jobs._session(owner, session)
            objects = self._session_path(session) / 'objects'
            if objects.is_symlink():
                raise ValueError('Object directory cannot be a symlink')
            objects.mkdir(parents=True, exist_ok=True, mode=0o700)
            destination = objects / (digest + '.json')
            if destination.is_symlink():
                raise ValueError('Object cannot be a symlink')
            if destination.exists():
                if destination.read_bytes() != data:
                    raise ValueError('Existing object is corrupt')
            else:
                temporary = objects / (str(uuid.uuid4()) + '.tmp')
                try:
                    temporary.write_bytes(data); temporary.replace(destination)
                finally:
                    temporary.unlink(missing_ok=True)
        return digest

    def read_result(self, owner, job):
        # Serializes authorization and file reading with session deletion.
        with self.jobs.transaction():
            record = self.jobs.get(owner, job)
            if record['state'] != 'succeeded' or not record['output_hash']:
                raise LookupError('Result unavailable')
            session = self._session_path(record['session_id'])
            directory = session / 'jobs' / job
            if (session/'jobs').is_symlink() or directory.is_symlink():
                raise ValueError('Invalid result directory')
            publication=self.jobs.db.execute('SELECT published_token FROM jobs WHERE id=?',(job,)).fetchone()[0]
            if publication is not None:
                self.jobs._hash(publication)
            attempts=[directory/publication] if publication is not None else directory.iterdir()
            matches = []
            for attempt in attempts:
                if attempt.is_symlink() or not attempt.is_dir():
                    continue
                result = attempt/'result.json'
                if result.is_symlink() or not result.is_file() or result.stat().st_size > 500_000_000:
                    continue
                data = result.read_bytes()
                if hashlib.sha256(data).hexdigest() == record['output_hash']:
                    matches.append(data)
            if len(matches) != 1:
                raise ValueError('Result bytes missing, corrupt or ambiguous')
            return matches[0]

    def purge_deleted_sessions(self):
        """Trusted maintenance operation; retry tombstones on every invocation.

        Repeated sweeps remove residue from a worker interrupted during cleanup.
        They do not impose a deletion deadline without a scheduled maintenance loop.
        """
        outcomes = []
        with self.jobs.transaction():
            identities = [r[0] for r in self.jobs.db.execute('SELECT id FROM sessions WHERE deleted=1')]
            for identity in identities:
                try:
                    directory = self._session_path(identity)
                    if directory.exists():
                        shutil.rmtree(directory)
                    self.jobs.db.execute('DELETE FROM purge_queue WHERE session_id=?', (identity,))
                    outcomes.append(dict(session=identity, removed=True))
                except (OSError, ValueError) as error:
                    outcomes.append(dict(session=identity, removed=False, error=type(error).__name__))
        return outcomes

    def purge_abandoned_attempts(self):
        """Remove fenced attempt directories; retain live and published attempts.

        Legacy successes without a recorded publication token are retained intact.
        This serializes with claim/publication, but cannot prevent a revoked process
        from recreating residue; repeated maintenance is required.
        """
        outcomes=[]
        with self.jobs.transaction():
            rows=self.jobs.db.execute('''SELECT j.* FROM jobs j JOIN sessions s ON j.session_id=s.id
                WHERE s.deleted=0''').fetchall()
            for row in rows:
                if row['state']=='succeeded' and row['published_token'] is None:
                    continue
                try:
                    session=self._session_path(row['session_id']);parent=session/'jobs'
                    directory=parent/row['id']
                    if str(uuid.UUID(row['id']))!=row['id'] or parent.is_symlink() or directory.is_symlink():
                        raise ValueError('Invalid attempt directory')
                    if not directory.exists():continue
                    retained={row['attempt_token'],row['published_token']}
                    for attempt in directory.iterdir():
                        if attempt.name in retained:continue
                        self.jobs._hash(attempt.name)
                        if attempt.is_symlink() or not attempt.is_dir():
                            raise ValueError('Invalid attempt path')
                        shutil.rmtree(attempt)
                        outcomes.append(dict(job=row['id'],removed=True))
                except (OSError,ValueError) as error:
                    outcomes.append(dict(job=row['id'],removed=False,error=type(error).__name__))
        return outcomes
