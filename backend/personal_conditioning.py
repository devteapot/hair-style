"""Durable conditioning of an explicitly provisioned local research model sample."""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
from .job_store import JobStore
from .worker_process import run_stage
from tools.canonical_json import loads


def condition(store, attempt, work, root, workspace):
    request=attempt['request']; job=attempt['id']; token=attempt['token']
    names={'inputSHA256':'source-input.json','preparedBriefSHA256':'prepared-brief.json',
           'mappingSHA256':'mapping.json','anatomySHA256':'anatomy.json',
           'preparationSHA256':'preparation-result.json'}
    if (set(request)!={'schemaVersion','kind','modelSampleSHA256',*names}
            or type(request['schemaVersion']) is not int or request['schemaVersion']!=1
            or request['kind']!='condition_personal_sample'):
        raise ValueError('Invalid personal conditioning request')
    for key in (*names,'modelSampleSHA256'):JobStore._hash(request[key])
    base=Path(workspace).resolve();work=work.resolve();work.mkdir(parents=True,exist_ok=False,mode=0o700)
    preparation=work/'preparation';preparation.mkdir(mode=0o700)
    for key,name in names.items():
        source=root/'objects'/(request[key]+'.json')
        limit=100_000_000 if key=='preparationSHA256' else 25_000_000
        if source.is_symlink() or source.stat().st_size>limit:raise ValueError('Invalid personal input object')
        data=source.read_bytes()
        if len(data)>limit or hashlib.sha256(data).hexdigest()!=request[key]:raise ValueError('Personal input hash mismatch')
        (preparation/name).write_bytes(data)
    # Sample hashes select administrator-provisioned model artifacts, never user paths.
    catalog=base/'.research/conditioning-samples';sample=catalog/request['modelSampleSHA256']
    if sample.is_symlink() or sample.resolve().parent!=catalog.resolve():raise ValueError('Invalid model sample directory')
    for name,limit in [('source.json',25_000_000),('trajectory-report.json',5_000_000),('texture.safetensors',100_000_000)]:
        path=sample/name
        if path.is_symlink() or not path.is_file() or path.stat().st_size>limit:raise ValueError('Model sample is unavailable')
    if hashlib.sha256((sample/'source.json').read_bytes()).hexdigest()!=request['modelSampleSHA256']:
        raise ValueError('Model sample source hash mismatch')
    trajectory=json.loads((sample/'trajectory-report.json').read_bytes())
    if trajectory.get('textureSHA256')!=hashlib.sha256((sample/'texture.safetensors').read_bytes()).hexdigest():
        raise ValueError('Model sample texture hash mismatch')
    if not store.checkpoint(job,token,'generating',request['preparationSHA256']):
        raise RuntimeError('Personal conditioning is no longer active')
    environment=dict(os.environ,HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',HF_DATASETS_OFFLINE='1',PYTORCH_ENABLE_MPS_FALLBACK='0')
    with (work/'pipeline.log').open('wb') as log:
        code=run_stage([str(base/'.research/metal-env/bin/python'),str(base/'tools/run_prepared_personal_generation.py'),
            str(preparation),str(sample/'texture.safetensors'),str(sample/'source.json'),str(sample/'trajectory-report.json'),
            str(work/'pipeline'),'--preparation-output-sha256',request['preparationSHA256']],
            cwd=base,env=environment,stdout=log,timeout=600,active=lambda:store.attempt_active(job,token))
    if code:raise RuntimeError('Personal conditioning pipeline rejected')
    if not store.checkpoint(job,token,'compiling',request['preparationSHA256']):
        raise RuntimeError('Personal conditioning is no longer active')
    pipeline=work/'pipeline'
    output=assemble_result(pipeline,request)
    data=json.dumps(output,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
    if len(data)>100_000_000:raise ValueError('Conditioning result exceeds retrieval budget')
    digest=hashlib.sha256(data).hexdigest();(work/'result.tmp').write_bytes(data);(work/'result.tmp').replace(work/'result.json')
    for child in work.iterdir():
        if child.name!='result.json':
            if child.is_dir():shutil.rmtree(child)
            else:child.unlink()
    published=store.finish(job,token,output_hash=digest)
    return dict(job=job,published=published,outputSHA256=digest if published else None)


def assemble_result(pipeline,request):
    """Assemble retained canonical artifacts; native consumption replays the fit."""
    def read(name):return loads((pipeline/name).read_bytes())
    report=read('report.json');review=read('export/review-report.json');mesh=read('mesh.json')
    imported=read('export/imported.json');clearance=read('export/clearance.json')
    if (report.get('status')!='research_review_required' or report.get('acceptedForPersonalHaircut') is not False
            or mesh.get('haircutSHA256')!=review.get('haircutSHA256')
            or imported['validation']['haircutSHA256']!=review.get('haircutSHA256')
            or clearance.get('haircutSHA256')!=review.get('haircutSHA256')):
        raise ValueError('Conditioning result is inconsistent')
    output=dict(schemaVersion=1,kind='conditioned_personal_research',request=request,
        input=read('export/input.json'),sourceArtifactData=base64.b64encode((pipeline/'export/source.json').read_bytes()).decode(),mapping=read('export/mapping.json'),
        haircut=imported['haircut'],validation=imported['validation'],mesh=mesh,clearance=clearance,
        pipelineReport=report,acceptedForPersonalHaircut=False,personalStyleVerified=False,
        limitations=['Conditions an existing model sample; does not resample a hairstyle from preferences.',
                     'Clearance failures and missing anatomy require review; output is not an accepted personal design.'])
    fit=report.get('directionFit',{})
    if fit.get('status')=='verified':
        record=read('direction-fit/record.json');verified=read('direction-fit/verification.json')
        fitted_mesh=read('direction-fit/mesh.json')
        if (record.get('sourceHaircutSHA256')!=review['haircutSHA256']
                or verified['clearance'].get('surfaceChecksPassed') is not True
                or any(value!=fit.get('haircutSHA256') for value in (
                    verified['validation']['haircutSHA256'],verified['clearance']['haircutSHA256'],
                    fitted_mesh['haircutSHA256'],report.get('selectedHaircutSHA256')))
                or hashlib.sha256((pipeline/'direction-fit/mesh.json').read_bytes()).hexdigest()!=report.get('selectedMeshFileSHA256')):
            raise ValueError('Fitted conditioning result is inconsistent')
        output.update(directionFit=record,haircut=read('direction-fit/haircut.json'),
                      validation=verified['validation'],clearance=verified['clearance'],mesh=fitted_mesh)
    return output
