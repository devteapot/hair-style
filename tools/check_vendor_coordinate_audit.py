#!/usr/bin/env python3
import numpy as np
from audit_vendor_coordinates import compare
p=np.array([[0,0,0],[1,0,0],[0,1,0]],dtype=float);f=[[0,1,2]]
r=compare(p,p.copy(),f,f);assert r['sameCoordinates'] and r['differsOnlyByTranslation']
r=compare(p,p+[.01,.02,.03],f,f)
assert not r['sameCoordinates'] and r['differsOnlyByTranslation']
assert np.allclose(r['indexedMedianTranslationMeters'],[-.01,-.02,-.03])
q=p.copy();q[0,2]=.01;r=compare(p,q,f,f);assert not r['differsOnlyByTranslation']
r=compare(p,p,f,[[0,2,1]]);assert not r['identicalTopology'] and 'indexedMedianTranslationMeters' not in r
print('Coordinate audit checks passed: identity, translation, deformation and unmatched topology.')
