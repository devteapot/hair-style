"""Supervise trusted local stages without leaving cancelled process groups running."""
import os
import signal
import subprocess
import time


def run_stage(command, *, active, timeout, cwd=None, env=None, stdout=None):
    if not active():
        raise RuntimeError('Worker attempt is no longer active')
    started=time.monotonic()
    process=subprocess.Popen(command,cwd=cwd,env=env,stdout=stdout or subprocess.DEVNULL,
        stderr=subprocess.STDOUT,start_new_session=True)
    try:
        while process.poll() is None:
            if not active():
                raise RuntimeError('Worker attempt was cancelled or expired')
            if time.monotonic()-started>=timeout:
                raise subprocess.TimeoutExpired(command,timeout)
            time.sleep(0.1)
        if not active():
            raise RuntimeError('Worker attempt is no longer active')
        return process.returncode
    except BaseException:
        def signal_group(value):
            try:os.killpg(process.pid,value)
            except ProcessLookupError:pass
        signal_group(signal.SIGTERM)
        try:process.wait(timeout=2)
        except subprocess.TimeoutExpired:pass
        # Descendants can outlive a leader or ignore TERM. Revoke the whole group.
        signal_group(signal.SIGKILL)
        process.wait()
        raise
