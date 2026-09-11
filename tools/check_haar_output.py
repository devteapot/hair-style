#!/usr/bin/env python3
"""Synthetic serialization checks, never evidence of HAAR inference."""
import hashlib,json,math,struct,tempfile
from pathlib import Path
from inspect_haar_output import read_points,convert,REVISION

points=[[float(g)+i/100,math.sin(i/15)*.1,g*.2] for g in range(2) for i in range(100)]
header='ply\nformat binary_little_endian 1.0\nelement vertex 200\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nend_header\n'
data=header.encode()+b''.join(struct.pack('<fffB',*p,255) for p in points)
actual=read_points(data)
assert len(actual)==200 and abs(actual[100][0]-1)<1e-7
for a,b in zip(actual,points):assert max(abs(x-y) for x,y in zip(a,b))<1e-6
ascii_header=header.replace('binary_little_endian','ascii')
ascii_data=ascii_header.encode()+''.join(' '.join(map(str,p))+' 255\n' for p in points).encode()
assert read_points(ascii_data)==points
for invalid in [data[:-1],data+b'!',data.replace(b'vertex 200',b'vertex 199'),
                header.encode()+struct.pack('<fffB',float('nan'),0,0,255)+data[len(header)+13:]]:
    try:read_points(invalid)
    except ValueError:pass
    else:raise AssertionError('Malformed PLY accepted')
with tempfile.TemporaryDirectory() as root:
    root=Path(root);ply=root/'fixture.ply';ply.write_bytes(data)
    report=dict(model='HAAR',revision=REVISION,inferenceCompleted=True,exitCode=0,errors=[],
                syntheticTestOnly=True,output=dict(path=str(ply),bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
    path=root/'run.json';path.write_text(json.dumps(report));result=convert(path,root/'strands.json')
    assert result['strandCount']==2 and result['strands'][1]['points'][0]==actual[100]
    assert result['units']=='unresolved' and not result['acceptedForPersonalHaircut']
    assert result['samplingSeed'] is None
    report['samplingSeed']=43;path.write_text(json.dumps(report))
    assert convert(path,root/'seeded.json')['samplingSeed']==43
    report['samplingSeed']=True;path.write_text(json.dumps(report))
    try:convert(path,root/'bad-seed.json')
    except ValueError:pass
    else:raise AssertionError('Boolean sampling seed accepted')
    report['samplingSeed']=43;path.write_text(json.dumps(report))
    ply.write_bytes(data[:-1])
    try:convert(path,root/'bad.json')
    except ValueError:pass
    else:raise AssertionError('Changed output accepted')
print('Synthetic binary/ASCII order, malformed data, integrity and unaccepted-output checks passed.')
