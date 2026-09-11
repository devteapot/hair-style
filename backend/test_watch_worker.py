import json
import signal
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from backend.artifact_store import ArtifactStore
from backend.job_store import JobStore


class WatchWorkerTests(unittest.TestCase):
    def test_idle_worker_picks_up_job_recovers_lease_and_repeats_deleted_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cli = Path('.build/debug/capture-inspect').resolve()
            subprocess.run([str(cli), 'hair-fixture', str(root/'fixture')], check=True, capture_output=True)
            store = JobStore(root/'jobs.sqlite')
            files = ArtifactStore(store, root/'artifacts')
            session = store.create_session('owner')
            request = dict(schemaVersion=1, kind='compile_hair')
            for name, key in [('input.json','inputSHA256'),('haircut.json','haircutSHA256')]:
                request[key] = files.stage('owner', session, (root/'fixture'/name).read_bytes())
            second = store.submit('owner', session, 'expired', request)
            stale = store.claim()
            store.db.execute('UPDATE jobs SET lease_expires=? WHERE id=?',(time.time()+2,second))
            log = open(root/'worker.log', 'w+')
            process = subprocess.Popen([sys.executable, '-m', 'backend.watch_worker', str(root/'jobs.sqlite'),
                str(root/'artifacts'), '--inspector', str(cli), '--poll-seconds', '0.1'], stdout=log, stderr=log)
            def wait_for(predicate):
                deadline = time.monotonic()+10
                while time.monotonic() < deadline:
                    if predicate(): return
                    if process.poll() is not None: break
                    time.sleep(0.02)
                log.flush()
                self.fail('Worker condition timed out: '+(root/'worker.log').read_text())
            try:
                wait_for(lambda:'worker_started' in (root/'worker.log').read_text())
                self.assertIsNone(process.poll())
                self.assertEqual(store.get('owner',second)['state'],'running')
                # No new invocation: the watcher stays idle until this lease expires.
                wait_for(lambda:store.get('owner', second)['state']=='succeeded')
                self.assertEqual(store.get('owner',second)['attempt_count'],2)
                self.assertFalse(store.finish(second,stale['token'],output_hash='a'*64))
                first = store.submit('owner', session, 'after-start', request)
                wait_for(lambda:store.get('owner', first)['state']=='succeeded')
                self.assertEqual(json.loads(files.read_result('owner', first))['kind'],'compiled_hair')
                store.delete_session('owner',session)
                namespace = root/'artifacts'/session
                wait_for(lambda:not namespace.exists())
                namespace.mkdir();(namespace/'late-residue').write_text('late worker bytes')
                wait_for(lambda:not namespace.exists())
                process.terminate();self.assertEqual(process.wait(timeout=5),0)
                self.assertIn('worker_stopped',(root/'worker.log').read_text())
            finally:
                if process.poll() is None:
                    process.kill();process.wait(timeout=5)
                log.close();store.close()

    def test_stop_during_compile_drains_current_job_and_leaves_next_queued(self):
        for stop_signal in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=stop_signal), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                cli = Path('.build/debug/capture-inspect').resolve()
                subprocess.run([str(cli),'hair-fixture',str(root/'fixture')],check=True,capture_output=True)
                store = JobStore(root/'jobs.sqlite')
                files = ArtifactStore(store,root/'artifacts')
                session = store.create_session('owner')
                request = dict(schemaVersion=1,kind='compile_hair')
                for name,key in [('input.json','inputSHA256'),('haircut.json','haircutSHA256')]:
                    request[key] = files.stage('owner',session,(root/'fixture'/name).read_bytes())
                first = store.submit('owner',session,'current',request)
                # Gate the real compiler so the signal arrives while its stage is
                # running. After release, exec the trusted Swift binary unchanged.
                wrapper = root/'gated-inspector'
                wrapper.write_text('#!'+sys.executable+'\n'+
                    'import os, pathlib, sys, time\n'+
                    'root=pathlib.Path(__file__).parent\n'+
                    'if sys.argv[1] == "hair-validate":\n'+
                    ' (root/"started").touch()\n'+
                    ' deadline=time.monotonic()+10\n'+
                    ' while not (root/"release").exists():\n'+
                    '  if time.monotonic()>deadline: sys.exit(3)\n'+
                    '  time.sleep(0.01)\n'+
                    'os.execv('+repr(str(cli))+', ['+repr(str(cli))+']+sys.argv[1:])\n')
                wrapper.chmod(0o700)
                with open(root/'worker.log','w') as log:
                    process = subprocess.Popen([sys.executable,'-m','backend.watch_worker',str(root/'jobs.sqlite'),
                        str(root/'artifacts'),'--inspector',str(wrapper),'--poll-seconds','0.1'],stdout=log,stderr=log)
                    try:
                        deadline = time.monotonic()+5
                        while not (root/'started').exists() and time.monotonic()<deadline and process.poll() is None:
                            time.sleep(0.01)
                        self.assertTrue((root/'started').exists(),(root/'worker.log').read_text())
                        self.assertEqual(store.get('owner',first)['state'],'running')
                        second = store.submit('owner',session,'next',request)
                        process.send_signal(stop_signal)
                        (root/'release').touch()
                        self.assertEqual(process.wait(timeout=5),0,(root/'worker.log').read_text())
                        self.assertEqual(store.get('owner',first)['state'],'succeeded')
                        self.assertEqual(json.loads(files.read_result('owner',first))['kind'],'compiled_hair')
                        self.assertEqual(store.get('owner',second)['state'],'queued')
                        self.assertEqual(store.get('owner',second)['attempt_count'],0)
                        events=[json.loads(line) for line in (root/'worker.log').read_text().splitlines()]
                        self.assertEqual([e['event'] for e in events],['worker_started','job_finished','worker_stopped'])
                        # A later invocation can resume the untouched queued job.
                        from backend.compile_worker import run_one
                        self.assertTrue(run_one(store,root/'artifacts',cli)['published'])
                        self.assertEqual(store.get('owner',second)['state'],'succeeded')
                    finally:
                        (root/'release').touch()
                        if process.poll() is None:
                            process.terminate()
                            try:process.wait(timeout=5)
                            except subprocess.TimeoutExpired:process.kill();process.wait(timeout=5)
                        store.close()

    def test_failed_cleanup_prevents_claim_and_does_not_follow_symlink(self):
        from backend.compile_worker import run_one
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = JobStore(root/'jobs.sqlite')
            try:
                removed = store.create_session('owner')
                active = store.create_session('owner')
                job = store.submit('owner', active, 'queued', {})
                store.delete_session('owner', removed)
                outside = root/'outside';outside.mkdir()
                (outside/'keep').write_text('retained')
                artifacts = root/'artifacts';artifacts.mkdir()
                (artifacts/removed).symlink_to(outside, target_is_directory=True)
                with self.assertRaisesRegex(RuntimeError, 'maintenance failed'):
                    run_one(store, artifacts, root/'unused-inspector')
                self.assertEqual(store.get('owner',job)['state'],'queued')
                self.assertTrue((artifacts/removed).is_symlink())
                self.assertEqual((outside/'keep').read_text(),'retained')
            finally:
                store.close()

    def test_invalid_poll_interval_exits_without_running(self):
        result = subprocess.run([sys.executable,'-m','backend.watch_worker','unused.sqlite','unused-artifacts',
            '--inspector','unused','--poll-seconds','nan'],capture_output=True,timeout=5)
        self.assertEqual(result.returncode,2)
        self.assertIn(b'--poll-seconds must be',result.stderr)
