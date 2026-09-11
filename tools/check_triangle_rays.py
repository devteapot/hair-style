#!/usr/bin/env python3
"""Analytic ray/triangle checks for model-depth diagnostics."""
import numpy as np
from check_model_depth import first_hit

v=np.array([[-.2,-.2,.5],[.2,-.2,.5],[.2,.2,.5],[-.2,.2,.5]],dtype=float)
t=np.array([[0,1,2],[0,2,3]])
rays=np.array([[0,0,1],[.1,.2,1],[1,0,1],[0,0,-1],[1,0,0]],dtype=float)
hit=first_hit(np.zeros(3),rays,v,t)
assert np.allclose(hit[:2],[.5,.5]);assert np.isinf(hit[2:]).all()
assert np.allclose(first_hit(np.zeros(3),rays,v,t[:,::-1]),hit)
# Two surfaces on a ray must choose the first, independent of triangle ordering.
v2=np.concatenate([v*2,v]);t2=np.concatenate([t,t+4])
assert np.isclose(first_hit(np.zeros(3),rays[:1],v2,t2)[0],.5)
# Rotating/translating both rays and geometry preserves t; it is optical Z, not Euclidean range.
r=np.array([[0,0,1],[0,1,0],[-1,0,0]],dtype=float);origin=np.array([1.,2.,3.])
assert np.allclose(first_hit(origin,rays@r.T,v@r.T+origin,t),hit)
print('Triangle-ray checks passed: plane depth, misses, reverse winding, nearest layer, rigid invariance.')
