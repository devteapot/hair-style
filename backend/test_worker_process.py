from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
import threading
from backend.worker_process import run_stage
from backend.job_store import JobStore


class WorkerProcessTests(unittest.TestCase):
    def test_database_cancellation_interrupts_running_stage(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'jobs.sqlite';marker=Path(directory)/'started'
            store=JobStore(path);session=store.create_session('owner')
            job=store.submit('owner',session,'one',{});attempt=store.claim()
            def cancel():
                deadline=time.monotonic()+5
                while not marker.exists() and time.monotonic()<deadline:time.sleep(.02)
                other=JobStore(path)
                try:other.cancel('owner',job)
                finally:other.close()
            thread=threading.Thread(target=cancel);thread.start()
            try:
                with self.assertRaises(RuntimeError):
                    run_stage([sys.executable,'-c','import pathlib,sys,time; pathlib.Path(sys.argv[1]).touch(); time.sleep(30)',str(marker)],
                        active=lambda:store.attempt_active(job,attempt['token']),timeout=10)
                self.assertFalse(store.finish(job,attempt['token'],failure_code='generation_failed'))
                self.assertEqual(store.get('owner',job)['state'],'cancelled')
            finally:thread.join(timeout=6);store.close()

    def test_revoked_stage_stops_descendant_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            marker=Path(directory)/'heartbeat'
            child='import pathlib,sys,time,signal; signal.signal(signal.SIGTERM,signal.SIG_IGN); p=pathlib.Path(sys.argv[1]);\nwhile True: p.write_text(str(time.monotonic())); time.sleep(.02)'
            parent='import subprocess,sys,time; subprocess.Popen([sys.executable,"-c",sys.argv[1],sys.argv[2]]); time.sleep(30)'
            started=time.monotonic()
            with self.assertRaises(RuntimeError):
                run_stage([sys.executable,'-c',parent,child,str(marker)],
                    active=lambda:not marker.exists(),timeout=5)
            self.assertLess(time.monotonic()-started,4)
            self.assertTrue(marker.exists())
            before=marker.read_bytes();time.sleep(.2)
            self.assertEqual(marker.read_bytes(),before)

    def test_timeout_terminates_and_success_returns_exit_code(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            run_stage([sys.executable,'-c','import time; time.sleep(30)'],active=lambda:True,timeout=.1)
        self.assertEqual(run_stage([sys.executable,'-c','raise SystemExit(7)'],active=lambda:True,timeout=5),7)
