#!/usr/bin/env python3
"""Cancel the real prepared HAAR worker when its diffusion subprocess appears."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from backend.job_store import JobStore


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path);args=p.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    store=JobStore(out/'jobs.sqlite');session=store.create_session('probe')
    job=store.submit('probe',session,'cancel-diffusion',dict(schemaVersion=1,kind='generate_haar_template',description='short wavy hair with a side part',seed=45))
    worker=subprocess.Popen([sys.executable,'-m','backend.compile_worker',str(out/'jobs.sqlite'),str(out/'artifacts'),
        '--inspector',str(ROOT/'.build/debug/capture-inspect'),'--haar-workspace',str(ROOT)],
        cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    pid=None;started=time.monotonic();deadline=started+180
    try:
        while worker.poll() is None and time.monotonic()<deadline:
            rows=subprocess.check_output(['ps','-axo','pid=,ppid=,command='],text=True)
            for row in rows.splitlines():
                parts=row.strip().split(None,2)
                if len(parts)==3 and int(parts[1])==worker.pid and 'haar_inference_metal.py' in parts[2]:
                    pid=int(parts[0]);break
            if pid is not None:break
            time.sleep(.1)
        if pid is None:raise RuntimeError('Diffusion stage was not observed before worker exit/deadline')
        cancellation=time.monotonic();store.cancel('probe',job)
        stdout,stderr=worker.communicate(timeout=10)
        latency=time.monotonic()-cancellation
        record=store.get('probe',job)
        result=json.loads(stdout)
        alive=True
        for _ in range(50):
            try:os.kill(pid,0)
            except ProcessLookupError:alive=False;break
            time.sleep(.1)
        reports=list((out/'artifacts').rglob('result.json'))
        if worker.returncode!=0 or record['state']!='cancelled' or result['published'] or reports or alive:
            raise RuntimeError('Cancellation verification failed')
        report=dict(method='local_haar_diffusion_cancellation_v1',stageObserved='haar_inference_metal.py',
            secondsBeforeCancellation=cancellation-started,cancellationToWorkerExitSeconds=latency,
            observedStageProcessExited=not alive,jobState=record['state'],published=False,resultFiles=len(reports),
            attemptDirectories=len([x for x in (out/'artifacts').glob('*/jobs/*/*') if x.is_dir()]),
            limitations=['One local run; GPU kernel execution at cancellation was not measured.',
                'No participant input or remote model service was used.'])
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
    finally:
        if worker.poll() is None:
            store.cancel('probe',job)
            try:worker.communicate(timeout=10)
            except subprocess.TimeoutExpired:worker.terminate();worker.wait(timeout=5)
        store.close()


if __name__=='__main__':main()
