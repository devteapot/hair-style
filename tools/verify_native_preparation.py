#!/usr/bin/env python3
"""Verify native automatic refresh after a queued status was served.

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
            '-only-testing:PersonalizedHairUITests/ModelReviewUITests/testPersonalPreparationRequiresConsentAndRestoresVerifiedResult',
            'test'],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
        try:
            while client.poll() is None and time.monotonic()-started<240:
                # The worker cannot win the first status read: it remains idle
                # until the API has produced a queued response for this client.
                result=run_one(store,state/'artifacts',ROOT/'.build/debug/capture-inspect') if queued.is_set() else None
                if result:runs.append(result)
                else:time.sleep(.1)
            code=client.wait(timeout=10)
            passed=code==0 and len(runs)==1 and runs[0]['published'] and runs[0]['job'] in observed
            report=dict(passed=passed,uiExitCode=code,queuedStatusObservedBeforeWorker=observed,
                workerRuns=runs,seconds=time.monotonic()-started,modelExecuted=False)
            (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
            print(json.dumps(report,indent=2))
            if not passed:raise RuntimeError('Native preparation refresh verification failed')
        finally:
            if client.poll() is None:client.terminate();client.wait(timeout=10)
            store.close();server.shutdown();server.server_close();thread.join(timeout=5)
            JobStore.get=original_get


if __name__=='__main__':main()
