"""Trusted local adapter for validating/compiling an existing canonical haircut.

Requests contain content hashes only. This does not generate a hairstyle.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
from .job_store import JobStore
from .worker_process import run_stage


def run_one(store, artifact_root, inspector, haar_workspace=None):
    store.recover_expired()
    from .artifact_store import ArtifactStore
    artifacts = ArtifactStore(store, artifact_root)
    outcomes = artifacts.purge_deleted_sessions() + artifacts.purge_abandoned_attempts()
    if any(not item['removed'] for item in outcomes):
        raise RuntimeError('Artifact maintenance failed; inspect the configured artifact paths and permissions')
    attempt = store.claim()
    if attempt is None:
        return None
    request = attempt['request']; job = attempt['id']; token = attempt['token']
    root = Path(artifact_root) / attempt['session_id']
    work = root / 'jobs' / job / token
    published = False
    started = time.monotonic()
    try:
        if request.get('kind') == 'prepare_personal_generation':
            from .personal_preparation import prepare
            result = prepare(store, attempt, work, root, inspector)
            published = result['published']
            return result
        if request.get('kind') == 'condition_personal_sample' and haar_workspace is not None:
            from .personal_conditioning import condition
            result = condition(store, attempt, work, root, haar_workspace)
            published = result['published']
            return result
        if request.get('kind') == 'generate_haar_template' and haar_workspace is not None:
            from .haar_generation import generate
            result = generate(store, attempt, work, haar_workspace)
            published = result['published']
            return result
        if set(request) != {'schemaVersion', 'kind', 'inputSHA256', 'haircutSHA256'} or request['schemaVersion'] != 1 or request['kind'] != 'compile_hair':
            raise ValueError('Unsupported compile request')
        for key in ('inputSHA256', 'haircutSHA256'):
            JobStore._hash(request[key])
        work.mkdir(parents=True, exist_ok=False, mode=0o700)
        for key, name in [('inputSHA256', 'input.json'), ('haircutSHA256', 'haircut.json')]:
            source = root / 'objects' / (request[key] + '.json')
            if source.is_symlink() or source.stat().st_size > 100_000_000:
                raise ValueError('Invalid input object')
            data = source.read_bytes()
            if hashlib.sha256(data).hexdigest() != request[key]:
                raise ValueError('Input object hash mismatch')
            (work / name).write_bytes(data)
        if not store.checkpoint(job, token, 'validating', request['inputSHA256']):
            store.finish(job, token, failure_code='generation_failed')
            return dict(job=job, published=False)
        def invoke(arguments):
            code = run_stage([str(Path(inspector).resolve()), *map(str, arguments)],
                timeout=120, active=lambda:store.attempt_active(job,token))
            if code:
                raise RuntimeError('Inspector rejected the artifact')
        invoke(['hair-validate', work/'input.json', work/'haircut.json', work/'validation.json'])
        if not store.checkpoint(job, token, 'compiling', request['haircutSHA256']):
            store.finish(job, token, failure_code='generation_failed')
            return dict(job=job, published=False)
        invoke(['hair-mesh', work/'input.json', work/'haircut.json', work/'mesh.json', '3', '1'])
        output = dict(schemaVersion=1, kind='compiled_hair', request=request,
            validation=json.loads((work/'validation.json').read_text()),
            mesh=json.loads((work/'mesh.json').read_text()),
            wallSeconds=time.monotonic()-started, personalStyleVerified=False)
        encoded = json.dumps(output, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
        digest = hashlib.sha256(encoded).hexdigest()
        temporary = work/'result.tmp'; temporary.write_bytes(encoded); temporary.replace(work/'result.json')
        for name in ('input.json','haircut.json','validation.json','mesh.json'):
            (work/name).unlink()
        published = store.finish(job, token, output_hash=digest)
        return dict(job=job, published=published, outputSHA256=digest if published else None)
    except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired):
        store.finish(job, token, failure_code='generation_failed')
        return dict(job=job, published=False, failure='generation_failed')
    finally:
        if not published and work.exists():
            shutil.rmtree(work)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('database', type=Path); p.add_argument('artifacts', type=Path)
    p.add_argument('--inspector', type=Path, required=True)
    p.add_argument('--haar-workspace', type=Path, help='Explicitly enable prepared local Metal research generation')
    args = p.parse_args(); store = JobStore(args.database)
    try: print(json.dumps(run_one(store, args.artifacts, args.inspector, args.haar_workspace)))
    finally: store.close()


if __name__ == '__main__': main()
