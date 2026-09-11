#!/usr/bin/env python3
"""Local Swift/API personal preparation round trip; no model or external upload."""
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
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('inputs',type=Path);parser.add_argument('output',type=Path);args=parser.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    database=out/'jobs.sqlite';artifacts=out/'artifacts'
    server=make_server(database,artifacts,0)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    client=subprocess.Popen([str(ROOT/'.build/debug/processing-probe'),f'http://127.0.0.1:{server.server_port}',str(out/'swift-report.json'),'--preparation',str(args.inputs.resolve())],
        cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    store=JobStore(database);runs=[];started=time.monotonic()
    try:
        while client.poll() is None and time.monotonic()-started<150:
            result=run_one(store,artifacts,ROOT/'.build/debug/capture-inspect')
            if result:runs.append(result)
            else:time.sleep(.1)
        stdout,stderr=client.communicate(timeout=10)
        if client.returncode!=0:raise RuntimeError('Swift preparation probe failed: '+stderr[-1000:])
        if len(runs)!=1 or not runs[0]['published']:raise RuntimeError('Expected exactly one publication')
        jobs=list(store.db.execute('SELECT attempt_count FROM jobs'))
        if len(jobs)!=1 or jobs[0]['attempt_count']!=1:raise RuntimeError('Unexpected duplicate/retried preparation')
        report=dict(method='supervised_swift_preparation_roundtrip_v1',seconds=time.monotonic()-started,
            workerInvocationsWithJob=len(runs),publishedBeforeClientDeletion=True,attemptCount=jobs[0]['attempt_count'],
            swift=json.loads((out/'swift-report.json').read_text()))
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
    finally:
        if client.poll() is None:client.terminate();client.wait(timeout=5)
        store.close();server.shutdown();server.server_close();thread.join(timeout=5)


if __name__=='__main__':main()
