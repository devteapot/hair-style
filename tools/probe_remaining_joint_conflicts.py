#!/usr/bin/env python3
"""Sequential bounded joint probes; preserve failed guides and retain every report."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['source','input','base_mapping','haircut','anatomy','clearance','output']:p.add_argument(name,type=Path)
    args=p.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    check=json.loads(args.clearance.read_text())
    guides=sorted({v['guideID'] for v in check['violations']})
    if len(guides)>16:raise ValueError('Use at most sixteen targeted guides per batch')
    current=args.haircut.resolve();current_clearance=args.clearance.resolve();runs=[];started=time.monotonic()
    for guide in guides:
        directory=args.output/guide
        with (args.output/(guide+'.log')).open('w') as log:
            command=[sys.executable,str(Path(__file__).with_name('probe_joint_attachment_direction.py')),
                str(args.source.resolve()),str(args.input.resolve()),str(args.base_mapping.resolve()),str(current),
                str(args.anatomy.resolve()),str(directory.resolve()),'--guide-id',guide]
            result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=240)
        if result.returncode:raise RuntimeError('Joint probe failed to execute: '+guide)
        report=json.loads((directory/'report.json').read_text())
        if report['selectedProposalIndex'] is not None:
            current=(directory/'haircut.json').resolve();current_clearance=(directory/'clearance.json').resolve()
        runs.append(dict(guideID=guide,selectedProposalIndex=report['selectedProposalIndex'],seconds=report['seconds']))
        (args.output/'report.json').write_text(json.dumps(dict(status='running',runs=runs,seconds=time.monotonic()-started),indent=2))
    (args.output/'haircut.json').write_bytes(current.read_bytes());(args.output/'clearance.json').write_bytes(current_clearance.read_bytes())
    (args.output/'report.json').write_text(json.dumps(dict(status='completed_research',runs=runs,seconds=time.monotonic()-started,acceptedForPersonalHaircut=False),indent=2))

if __name__=='__main__':main()
