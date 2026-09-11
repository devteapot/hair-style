#!/usr/bin/env python3
"""Actual Swift/local-API conditioning round trip; provisioned model sample required."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import threading
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from backend.local_api import make_server
from backend.job_store import JobStore
from backend.compile_worker import run_one


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs',type=Path);parser.add_argument('output',type=Path);args=parser.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    database=out/'jobs.sqlite';artifacts=out/'artifacts'
    server=make_server(database,artifacts,0)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    client=subprocess.Popen([str(ROOT/'.build/debug/processing-probe'),f'http://127.0.0.1:{server.server_port}',
        str(out/'swift-report.json'),'--conditioning',str(args.inputs.resolve())],cwd=ROOT,
        stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    store=JobStore(database);runs=[];started=time.monotonic()
    try:
        while client.poll() is None and time.monotonic()-started<240:
            result=run_one(store,artifacts,ROOT/'.build/debug/capture-inspect',ROOT)
            if result:runs.append(result)
            else:time.sleep(.1)
        stdout,stderr=client.communicate(timeout=10)
        if client.returncode:raise RuntimeError('Swift conditioning failed: '+stderr[-1500:])
        if len(runs)!=2 or not all(run['published'] for run in runs):raise RuntimeError('Expected preparation and conditioning publications')
        jobs=list(store.db.execute('SELECT attempt_count FROM jobs'))
        if len(jobs)!=2 or any(job['attempt_count']!=1 for job in jobs):raise RuntimeError('Unexpected retry or duplicate job')
        if list(artifacts.rglob('*.json')):raise RuntimeError('Deleted session retained JSON artifacts')
        report=dict(method='swift_personal_conditioning_roundtrip_v1',seconds=time.monotonic()-started,
            workerPublications=2,attemptsPerJob=1,sessionArtifactDeletionVerified=True,
            swift=json.loads((out/'swift-report.json').read_bytes()))
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
    finally:
        if client.poll() is None:client.terminate();client.wait(timeout=5)
        store.close();server.shutdown();server.server_close();thread.join(timeout=5)


if __name__=='__main__':main()
