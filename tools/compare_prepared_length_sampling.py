#!/usr/bin/env python3
"""Controlled two-brief sampling experiment; no personal/style acceptance."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

ROOT=Path(__file__).resolve().parents[1]

def sha(data): return hashlib.sha256(data).hexdigest()
def write(path,value): path.write_text(json.dumps(value,sort_keys=True,allow_nan=False))

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('preparation',type=Path);p.add_argument('output',type=Path);args=p.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False,mode=0o700)
    cli=ROOT/'.build/debug/capture-inspect';rows=[]
    for name,lower,upper in [('short',.04,.06),('long',.10,.14)]:
        directory=out/name;directory.mkdir();prep=directory/'preparation';prep.mkdir()
        for filename in ['source-input.json','mapping.json','anatomy.json']:
            shutil.copyfile(args.preparation/filename,prep/filename)
        request=dict(schemaVersion=1,id=str(uuid.uuid4()),mode='guided',seed=42,
            lengthRanges=[dict(region='fringe',minimumMeters=lower,maximumMeters=upper)])
        write(prep/'request.json',request)
        def invoke(command):subprocess.run(list(map(str,command)),cwd=ROOT,check=True)
        invoke([cli,'brief-prepare',prep/'source-input.json',prep/'request.json',prep/'prepared-brief.json'])
        invoke([cli,'brief-consume',prep/'source-input.json',prep/'prepared-brief.json',prep/'generation-input.json'])
        invoke([cli,'hair-root-preflight',prep/'generation-input.json',prep/'mapping.json',prep/'anatomy.json','.00005',prep/'roots.json'])
        data=(prep/'generation-input.json').read_bytes();roots=json.loads((prep/'roots.json').read_text())
        # Local experimental envelope, not a claim of remote service publication.
        preparation=dict(schemaVersion=1,kind='personal_generation_preparation',
            request=dict(schemaVersion=1,kind='prepare_personal_generation',**{
                key:sha((prep/file).read_bytes()) for key,file in [('inputSHA256','source-input.json'),
                ('preparedBriefSHA256','prepared-brief.json'),('mappingSHA256','mapping.json'),('anatomySHA256','anatomy.json')]}),
            generationInputData=base64.b64encode(data).decode(),generationInputFileSHA256=sha(data),rootPreflight=roots,
            attachmentsReady=roots['suppliedSurfacesPassed'],modelExecuted=False,personalStyleVerified=False,
            limitations=['Local controlled experiment; no service publication or physical acceptance'])
        write(prep/'preparation-result.json',preparation)
        with (directory/'sampling.log').open('w') as log:
            subprocess.run([sys.executable,str(ROOT/'tools/create_prepared_model_sample.py'),str(prep),str(directory/'sample'),
                '--preparation-output-sha256',sha((prep/'preparation-result.json').read_bytes())],cwd=ROOT,check=True,stdout=log,stderr=subprocess.STDOUT)
        rows.append(dict(name=name,requestedMinimumMeters=lower,requestedMaximumMeters=upper,
            sampleReport=json.loads((directory/'sample/report.json').read_text())))
        write(out/'runs.json',rows)

if __name__=='__main__':main()
