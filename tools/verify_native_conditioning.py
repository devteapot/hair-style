#!/usr/bin/env python3
"""Verify native preparation and model conditioning through the real worker.

Requires the isolated refined revision-2 simulator fixture. Reuse the service
state directory on repeated runs so its guest credentials match the Keychain.
The test owns loopback port 8767, never a phone camera or an external service.
"""
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
    parser.add_argument('service_state',type=Path)
    parser.add_argument('report_directory',type=Path)
    args=parser.parse_args()
    state=args.service_state.resolve();state.mkdir(parents=True,exist_ok=True)
    out=args.report_directory.resolve();out.mkdir(parents=True,exist_ok=False)
    queued=threading.Event();observed=[];original_get=JobStore.get
    def get(store,owner,job):
        result=original_get(store,owner,job)
        if result['state']=='queued':
            observed.append(job);queued.set()
        return result
    JobStore.get=get
    server=make_server(state/'jobs.sqlite',state/'artifacts',8767)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    store=JobStore(state/'jobs.sqlite');runs=[];started=time.monotonic()
    with (out/'ui.log').open('w') as log:
        client=subprocess.Popen([str(ROOT/'tools/dev.sh'),'xcodebuild','-project','ios/PersonalizedHair.xcodeproj',
            '-scheme','PersonalizedHair','-destination','platform=iOS Simulator,id=A98923CF-779F-48DF-A9E5-2AF512B9587F',
            '-derivedDataPath','DerivedData',
            '-only-testing:PersonalizedHairUITests/ModelReviewUITests/testNativeConditioningPreservesSourceAndRestoresReviewedCandidate',
            'test'],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
        try:
            while client.poll() is None and time.monotonic()-started<420:
                # The worker cannot win the first status read: it remains idle
                # until the API has produced a queued response for this client.
                result=run_one(store,state/'artifacts',ROOT/'.build/debug/capture-inspect',ROOT) if queued.is_set() else None
                if result:
                    row=store.db.execute('SELECT request_json,session_id FROM jobs WHERE id=?',(result['job'],)).fetchone()
                    result['kind']=json.loads(row['request_json'])['kind'];result['sessionID']=row['session_id']
                    runs.append(result)
                else:time.sleep(.1)
            code=client.wait(timeout=10)
            removed=all(not list((state/'artifacts'/run['sessionID']).rglob('*.json')) for run in runs)
            published=any(run['kind']=='condition_personal_sample' and run['published'] for run in runs)
            passed=code==0 and len(runs)==2 and all(run['published'] for run in runs) and removed
            report=dict(passed=passed,uiExitCode=code,queuedStatusObservedBeforeWorker=observed,
                workerRuns=runs,seconds=time.monotonic()-started,modelResultPublished=published,
                sessionArtifactsRemoved=removed)
            (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
            print(json.dumps(report,indent=2))
            if not passed:raise RuntimeError('Native conditioning verification failed')
        finally:
            if client.poll() is None:client.terminate();client.wait(timeout=10)
            store.close();server.shutdown();server.server_close();thread.join(timeout=5)
            JobStore.get=original_get


if __name__=='__main__':main()
