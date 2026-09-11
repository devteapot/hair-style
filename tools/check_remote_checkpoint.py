#!/usr/bin/env python3
"""Exercise bounded HTTP range reads without a network connection."""
import io,re
from unittest.mock import patch
from remote_checkpoint import HTTPRangeFile

content=b'P'+bytes(range(256))*9000
class Response:
    def __init__(self,status,data,headers):self.status_code=status;self.raw=io.BytesIO(data);self.headers=headers
    def __enter__(self):return self
    def __exit__(self,*args):pass
    def raise_for_status(self):
        if self.status_code>=400:raise RuntimeError('Unexpected test status')
class Session:
    invalid=False
    changed=False
    def get(self,url,headers,**kwargs):
        a,b=map(int,re.fullmatch(r'bytes=(\d+)-(\d+)',headers['Range']).groups())
        return Response(200 if self.invalid else 206,content[a:b+1],
            {'Content-Range':f'bytes {a}-{b}/{len(content)}','Last-Modified':'changed' if self.changed else 'fixed'})
    def close(self):pass
session=Session()
with patch('remote_checkpoint.requests.Session',return_value=session):
    r=HTTPRangeFile('https://test.invalid',maximum_bytes=4_000_000)
    assert r.read(7)==content[:7]
    r.seek(-17,2);assert r.read()==content[-17:]
    r.seek(1048570);assert r.read(25)==content[1048570:1048595]
    session.changed=True
    try:r.fetch(10,5)
    except ValueError:pass
    else:raise AssertionError('Changed source accepted')
    session.changed=False;session.invalid=True
    try:r.fetch(10,5)
    except ValueError:pass
    else:raise AssertionError('Ignored range accepted')
    session.invalid=False
    r.maximum_bytes=r.transferred
    try:r.fetch(100,1)
    except ValueError:pass
    else:raise AssertionError('Read budget exceeded')
print('Cross-block reads, EOF, range rejection, source changes and byte-budget checks passed.')
