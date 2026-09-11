#!/usr/bin/env python3
"""Synthetic checkpoint tests for restricted metadata and exact ZIP tensor bytes."""
import io,pickle,struct,zipfile,zlib
import torch
from extract_haar_ema import parse_metadata,tensor_payload

source=torch.arange(12,dtype=torch.float32).reshape(3,4)
buffer=io.BytesIO();torch.save({'model_ema':{'weight':source},'optimizer':{'unused':torch.zeros(20)}},buffer)
data=buffer.getvalue();archive=zipfile.ZipFile(io.BytesIO(data))
metadata=archive.read('archive/data.pkl');state,keys=parse_metadata(metadata)
assert keys==['model_ema','optimizer'] and state['weight'].shape==(3,4)
info=archive.getinfo('archive/data/'+state['weight'].storage.key)
raw=tensor_payload(data,0,info)
assert bytes(raw)==struct.pack('<12f',*range(12))
corrupt=bytearray(data);start=data.index(bytes(raw),info.header_offset);corrupt[start]^=1
try:tensor_payload(corrupt,0,info)
except ValueError:pass
else:raise AssertionError('Corrupt tensor was accepted')
try:parse_metadata(pickle.dumps(eval))
except ValueError:pass
else:raise AssertionError('Executable global was accepted')
view=io.BytesIO();torch.save({'model_ema':{'weight':source[:,::2]}},view)
z=zipfile.ZipFile(io.BytesIO(view.getvalue()))
try:parse_metadata(z.read('archive/data.pkl'))
except ValueError:pass
else:raise AssertionError('Unsupported tensor view was accepted')
print('Restricted metadata, exact tensor bytes, CRC corruption and unsupported-view checks passed.')
