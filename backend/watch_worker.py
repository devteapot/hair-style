"""Foreground local worker: serial jobs and recurring idle recovery/cleanup.

SIGINT/SIGTERM stop new polling and drain the current job. An external service
manager remains responsible for restart and hard-kill process-tree cleanup.
"""
import argparse
import json
import math
from pathlib import Path
import signal
import threading
from .compile_worker import run_one
from .job_store import JobStore


def run_forever(store, artifacts, inspector, *, stop, poll_seconds=1.0,
                haar_workspace=None, on_result=None):
    if not math.isfinite(poll_seconds) or not 0.1 <= poll_seconds <= 60:
        raise ValueError('Polling interval must be between 0.1 and 60 seconds')
    while not stop.is_set():
        result = run_one(store, artifacts, inspector, haar_workspace)
        if result is None:
            # Interruptible even when configured for a long polling interval.
            stop.wait(poll_seconds)
        elif on_result is not None:
            on_result(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('database', type=Path)
    parser.add_argument('artifacts', type=Path)
    parser.add_argument('--inspector', type=Path, required=True)
    parser.add_argument('--haar-workspace', type=Path)
    parser.add_argument('--poll-seconds', type=float, default=1.0)
    args = parser.parse_args()
    if not math.isfinite(args.poll_seconds) or not 0.1 <= args.poll_seconds <= 60:
        parser.error('--poll-seconds must be between 0.1 and 60')
    stop = threading.Event()
    previous = {}
    for name in (signal.SIGINT, signal.SIGTERM):
        previous[name] = signal.signal(name, lambda *_: stop.set())
    store = None
    try:
        store = JobStore(args.database)
        print(json.dumps(dict(event='worker_started', pollSeconds=args.poll_seconds)), flush=True)
        run_forever(store, args.artifacts, args.inspector, stop=stop,
                    poll_seconds=args.poll_seconds, haar_workspace=args.haar_workspace,
                    on_result=lambda result: print(json.dumps(dict(event='job_finished', **result)), flush=True))
        print(json.dumps(dict(event='worker_stopped')), flush=True)
    finally:
        if store is not None:
            store.close()
        for name, handler in previous.items():
            signal.signal(name, handler)


if __name__ == '__main__':
    main()
