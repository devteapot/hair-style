#!/usr/bin/env python3
"""Independent float64 replay of saved length-constrained decoder tensors."""
import argparse
import json
from pathlib import Path
import numpy as np
from safetensors.numpy import load_file


def verify(directory, fallback_mapping=None):
    data=load_file(str(directory/'curves.safetensors'));report=json.loads((directory/'report.json').read_text())
    inp=json.loads((directory/'generation-input.json').read_text())
    # Regional stages retain a mapping snapshot only for verified preparation mode.
    mapping_path=directory/'mapping.json'
    if not mapping_path.exists():
        if fallback_mapping is None: raise ValueError("Mapping is required for a non-snapshotted experiment")
        mapping_path=Path(fallback_mapping)
    mapping=json.loads(mapping_path.read_text())
    by_id={m['guideID']:m for m in mapping['mappings']}
    assert len(by_id)==len(mapping['mappings'])
    ids=report['guideIDs']
    assert ids and len(set(ids))==len(ids) and all(i in by_id for i in ids)
    selected=[by_id[i] for i in ids]
    before=data['originalMapped'].astype(np.float64);after=data['optimizedMapped'].astype(np.float64)
    assert before.shape==after.shape==(len(selected),100,3)
    assert np.isfinite(before).all() and np.isfinite(after).all()
    assert np.array_equal(before[:,0],after[:,0])
    limits={x['region']:x for x in inp['brief']['lengthLimits']}
    length=np.linalg.norm(np.diff(after,axis=1),axis=2).sum(axis=1)
    lower=np.array([limits[m['region']]['minimumMeters'] for m in selected])
    upper=np.array([limits[m['region']]['maximumMeters'] for m in selected])
    errors=np.maximum(lower-length,0)+np.maximum(length-upper,0)
    count=int(np.sum(errors>1e-7))
    assert count==report['finallyLengthViolatingGuides']
    movement=float(np.linalg.norm(after-before,axis=2).max())
    return dict(independentLengthViolationCount=count,maximumLengthViolationMeters=float(errors.max()),rootsExactlyUnchanged=True,
        maximumPointMovementMeters=movement,withinExisting20mmCandidateMovementBound=movement<=.02,
        physicalFitVerified=False)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('directory',type=Path);p.add_argument('--mapping');args=p.parse_args()
    report=verify(args.directory,args.mapping);(args.directory/'independent-length-check.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
