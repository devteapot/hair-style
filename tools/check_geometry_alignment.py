#!/usr/bin/env python3
"""Numerical checks for the experimental NumPy rigid ICP implementation."""
import numpy as np
from geometry_alignment_experiment import nearest, solve, transform
rng = np.random.default_rng(8391)
points = rng.uniform(-.025,.025,(1200,3)) + [0,0,.2]
angle = .025
truth = np.eye(4); truth[:3,:3] = [[np.cos(angle),0,np.sin(angle)],[0,1,0],[-np.sin(angle),0,np.cos(angle)]]
truth[:3,3] = [.003,-.002,.001]
target = transform(points,truth)
initial = truth.copy(); initial[:3,3] += [.0002,-.0001,.00015]
result = solve(points,target,initial)
assert result['stopped'] == 'converged', result['stopped']
recovered = np.array(result['targetFromSourceRowMajor']).reshape(4,4)
assert np.max(np.abs(recovered-truth)) < 1e-8
assert abs(np.linalg.det(recovered[:3,:3])-1) < 1e-10
assert not result['acceptedForFusion']
# Exact blocked nearest-neighbor search agrees with a direct distance matrix.
query = rng.uniform(-.1,.1,(71,3)); candidates = rng.uniform(-.1,.1,(93,3))
distance,index = nearest(query,candidates)
expected = np.linalg.norm(query[:,None,:]-candidates[None,:,:],axis=2)
assert np.array_equal(index,expected.argmin(axis=1))
assert np.max(np.abs(distance-expected.min(axis=1))) < 1e-12
# No invented solution when a coarse initialization has no local overlap.
failed = solve(points,target+10,np.eye(4))
assert failed['stopped'] == 'insufficient_overlap'
assert not failed['acceptedForFusion']
print('Passed known rigid recovery, proper rotation, exact neighbor search, and no-overlap rejection.')
