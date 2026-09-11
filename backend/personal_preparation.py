"""Durable brief replay and attachment review, before personal model execution."""
import base64
import hashlib
import json
from pathlib import Path
from .job_store import JobStore
from .worker_process import run_stage


def prepare(store, attempt, work, root, inspector):
    request = attempt['request']; job = attempt['id']; token = attempt['token']
    names = {'inputSHA256': 'source-input.json', 'preparedBriefSHA256': 'brief.json',
             'mappingSHA256': 'mapping.json', 'anatomySHA256': 'anatomy.json'}
    if (set(request) != {'schemaVersion', 'kind', *names}
            or type(request['schemaVersion']) is not int or request['schemaVersion'] != 1
            or request['kind'] != 'prepare_personal_generation'):
        raise ValueError('Invalid personal preparation request')
    for key in names:
        JobStore._hash(request[key])
    work.mkdir(parents=True, exist_ok=False, mode=0o700)
    for key, name in names.items():
        source = root/'objects'/(request[key]+'.json')
        if source.is_symlink() or source.stat().st_size > 25_000_000:
            raise ValueError('Invalid personal input object')
        data = source.read_bytes()
        if hashlib.sha256(data).hexdigest() != request[key]:
            raise ValueError('Personal input hash mismatch')
        (work/name).write_bytes(data)
    anatomy = json.loads((work/'anatomy.json').read_bytes())
    if not isinstance(anatomy, dict):
        raise ValueError('Personal anatomy must be an object')
    clearance = anatomy.get('clearanceMeters')
    if type(clearance) not in (int, float) or not 0.001 <= clearance <= 0.02:
        raise ValueError('Personal preparation requires at least 1 mm supplied-anatomy clearance')

    def invoke(arguments, allowed=(0,)):
        if not store.checkpoint(job, token, 'validating', request['preparedBriefSHA256']):
            raise RuntimeError('Personal preparation no longer active')
        code = run_stage([str(Path(inspector).resolve()), *map(str, arguments)],
                         timeout=120, active=lambda: store.attempt_active(job, token))
        if code not in allowed:
            raise RuntimeError('Personal preparation rejected')
        return code

    invoke(['brief-consume', work/'source-input.json', work/'brief.json', work/'input.json'])
    code = invoke(['hair-root-preflight', work/'input.json', work/'mapping.json',
                   work/'anatomy.json', '0.00005', work/'roots.json'], allowed=(0, 2))
    report = json.loads((work/'roots.json').read_bytes())
    ready = code == 0
    if (report.get('method') != 'proposed_root_clearance_preflight_v1'
            or report.get('suppliedSurfacesPassed') is not ready
            or report.get('requiresAttachmentReview') is not (not ready)
            or report.get('physicalFitVerified') is not False):
        raise ValueError('Inconsistent attachment report')
    data = (work/'input.json').read_bytes()
    output = dict(schemaVersion=1, kind='personal_generation_preparation', request=request,
                  generationInputData=base64.b64encode(data).decode("ascii"), generationInputFileSHA256=hashlib.sha256(data).hexdigest(),
                  rootPreflight=report, attachmentsReady=ready, modelExecuted=False,
                  personalStyleVerified=False,
                  limitations=['Preparation only; no haircut was generated.',
                               'Model source correspondence must be replayed before model use.',
                               'Missing anatomy, inferred scalp and styling feasibility remain unverified.'])
    encoded = json.dumps(output, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
    digest = hashlib.sha256(encoded).hexdigest()
    (work/'result.tmp').write_bytes(encoded); (work/'result.tmp').replace(work/'result.json')
    for child in work.iterdir():
        if child.name != 'result.json': child.unlink()
    published = store.finish(job, token, output_hash=digest)
    return dict(job=job, published=published, outputSHA256=digest if published else None)
