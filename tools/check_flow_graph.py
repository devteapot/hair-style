#!/usr/bin/env python3
"""Check registration graph bookkeeping, including isolated failed-frame nodes."""
from register_rear_flow import components

assert components([3,4,5,6,7],[(3,4),(4,5),(6,7)]) == [[3,4,5],[6,7]]
assert components([3,4,5],[]) == [[3],[4],[5]]
assert components([3,4,5],[(3,4),(4,5),(5,3)]) == [[3,4,5]]
for edge in [(3,9),(3,3)]:
    try: components([3,4,5],[edge])
    except ValueError: pass
    else: raise AssertionError('Invalid endpoint or self-edge accepted')
print('Graph chains, disconnected frames, cycles and invalid edges passed.')

from audit_flow_loops import compose, discrepancy
identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
a=identity.copy();a[3]=.02
b=identity.copy();b[7]=.03
c=compose(b,a)
assert c[3]==.02 and c[7]==.03
r=[0,-1,0,0,1,0,0,0,0,0,1,0,0,0,0,1]
assert compose(r,a)[7]==.02
assert compose(a,r)[3]==.02
assert abs(discrepancy(r,identity)['rotationDegrees']-90)<1e-10
assert abs(discrepancy(a,identity)['sourceCameraOriginDisplacementMeters']-.02)<1e-10
assert discrepancy(c,c)==dict(rotationDegrees=0,sourceCameraOriginDisplacementMeters=0)
print('Known transform composition and loop discrepancy checks passed.')
