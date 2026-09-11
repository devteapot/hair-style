#!/usr/bin/env python3
from diagnose_model_scale import diagnose
frames=[dict(sampleID=i,samples=3,modelDepthMeters=[.5,1.,None],observedDepthMeters=[.4,.8,.6]) for i in range(6)]
r=diagnose(frames)
assert abs(r['candidateScale']-.8)<1e-12 and r['unusedFrames']['after']['maximumMeters']<1e-12
assert all(f['modelMisses']==1 for f in r['perFrameRatioMedians'])
assert not r['modelModified'] and not r['acceptedForHeadFitting']
frames[1]['observedDepthMeters'][0]+=.01
r=diagnose(frames)
assert abs(r['candidateScale']-.8)<1e-12 and abs(r['unusedFrames']['after']['maximumMeters']-.01)<1e-12
frames[0]['modelDepthMeters'][0]=float('nan')
try:diagnose(frames)
except ValueError:pass
else:raise AssertionError('Nonfinite depth was accepted')
print('Scale diagnostic checks passed: exact scale, unused-frame error retained, misses and invalid inputs.')
