#!/usr/bin/env python3
"""Extract only HAAR EMA tensors from a public ZIP checkpoint into safetensors.

Parses metadata with a narrow, non-executing pickle allowlist; tensor bytes are
fetched by HTTP range and checked against ZIP CRCs. Training state is omitted.
"""
import argparse,collections,dataclasses,hashlib,io,json,math,pickle,shutil,struct,zipfile,zlib
from pathlib import Path
from remote_checkpoint import HTTPRangeFile

URL='https://drive.usercontent.google.com/download?id=1vCQ7vX3v6GWMQUv9gUkqJOutvAwb3uvF&export=download&confirm=t'

@dataclasses.dataclass(frozen=True)
class Storage:
    key:str
    dtype:str
    count:int

@dataclasses.dataclass(frozen=True)
class Tensor:
    storage:Storage
    offset:int
    shape:tuple
    stride:tuple


def rebuild(storage,offset,shape,stride,requires_grad,hooks,metadata=None):
    if not isinstance(storage,Storage) or type(offset)!=int or not isinstance(shape,tuple) or not isinstance(stride,tuple):
        raise ValueError('Unsupported tensor descriptor')
    if len(shape)!=len(stride) or len(shape)>8 or any(type(x)!=int or x<0 for x in shape+stride):raise ValueError('Invalid tensor dimensions')
    return Tensor(storage,offset,shape,stride)


class MetadataReader(pickle.Unpickler):
    def find_class(self,module,name):
        allowed={('collections','OrderedDict'):collections.OrderedDict,('torch','FloatStorage'):'F32',
                 ('torch','ByteStorage'):'U8',('torch._utils','_rebuild_tensor_v2'):rebuild}
        if (module,name) not in allowed:raise ValueError(f'Unsupported pickle global: {module}.{name}')
        return allowed[(module,name)]
    def persistent_load(self,value):
        if not isinstance(value,tuple) or len(value)!=5 or value[0]!='storage':raise ValueError('Unsupported persistent metadata')
        _,dtype,key,location,count=value
        if dtype not in ('F32','U8') or type(key)!=str or not key.isdigit() or type(count)!=int or not 0<=count<=100_000_000:
            raise ValueError('Invalid storage descriptor')
        return Storage(key,dtype,count)


def parse_metadata(data):
    if len(data)>8_000_000:raise ValueError('Metadata too large')
    root=MetadataReader(io.BytesIO(data)).load()
    if not isinstance(root,dict) or not isinstance(root.get('model_ema'),dict):raise ValueError('Missing EMA state dictionary')
    state=root['model_ema'];seen=set()
    for name,t in state.items():
        if type(name)!=str or not isinstance(t,Tensor) or t.offset!=0 or math.prod(t.shape)!=t.storage.count:
            raise ValueError('Only complete dense EMA tensors supported')
        expected=1
        for dim,stride in zip(reversed(t.shape),reversed(t.stride)):
            if dim>1 and stride!=expected:raise ValueError('Noncontiguous tensor unsupported')
            expected*=dim
        if t.storage.key in seen:raise ValueError('Shared EMA storage needs explicit alias handling')
        seen.add(t.storage.key)
    if not 1<=len(state)<=5000:raise ValueError('Invalid EMA tensor count')
    return state,sorted(root.keys())


def tensor_payload(group,start,info):
    offset=info.header_offset-start
    if group[offset:offset+4]!=b'PK\x03\x04':raise ValueError('Invalid local ZIP header')
    flags,compression=struct.unpack_from('<HH',group,offset+6)
    name_length,extra_length=struct.unpack_from('<HH',group,offset+26)
    name=group[offset+30:offset+30+name_length].decode('utf-8')
    if flags&1 or compression!=0 or name!=info.filename:raise ValueError('Unsupported or inconsistent ZIP entry')
    data_start=offset+30+name_length+extra_length
    payload=memoryview(group)[data_start:data_start+info.file_size]
    if len(payload)!=info.file_size or zlib.crc32(payload)!=info.CRC:raise ValueError('Tensor ZIP CRC/length mismatch')
    return payload


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path);p.add_argument('--extract',action='store_true')
    args=p.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    with HTTPRangeFile(URL) as remote:
        archive=zipfile.ZipFile(remote);infos=archive.infolist();by_name={x.filename:x for x in infos}
        metadata_info=next(x for x in infos if x.filename.endswith('/data.pkl'))
        metadata=archive.read(metadata_info);state,root_keys=parse_metadata(metadata)
        prefix=metadata_info.filename[:-len('data.pkl')]
        ordered=sorted([(name,t,by_name[prefix+'data/'+t.storage.key]) for name,t in state.items()],key=lambda entry:entry[2].header_offset)
        header={};cursor=0
        for name,t,info in ordered:
            size=t.storage.count*(4 if t.storage.dtype=='F32' else 1)
            if info.compress_type!=0 or info.file_size!=size or info.compress_size!=size:raise ValueError('Unexpected tensor storage size or compression')
            header[name]=dict(dtype=t.storage.dtype,shape=list(t.shape),data_offsets=[cursor,cursor+size]);cursor+=size
        result=dict(source=URL,archiveBytes=remote.size,lastModified=remote.modified,etag=remote.etag,
            metadataSHA256=hashlib.sha256(metadata).hexdigest(),rootKeys=root_keys,tensorCount=len(state),emaBytes=cursor,
            fullArchiveDownloaded=False,fullArchiveSHA256Verified=False,extractionCompleted=False,
            notes=['EMA tensors only, with no execution of checkpoint pickle globals.',
                   'Each extracted tensor must pass original ZIP CRC; full archive hash is unavailable.'])
        report=args.output/'report.json';report.write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(result,indent=2),flush=True)
        if not args.extract:return
        if cursor>4_000_000_000 or shutil.disk_usage(args.output).free<cursor+1_000_000_000:raise ValueError('Insufficient disk space or unsupported EMA size')
        encoded=json.dumps(header,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%8)
        spans=sorted(infos,key=lambda x:x.header_offset)
        ends={x.filename:(spans[i+1].header_offset if i+1<len(spans) else archive.start_dir) for i,x in enumerate(spans)}
        groups=[]
        for entry in ordered:
            info=entry[2];end=ends[info.filename]
            if groups and info.header_offset-groups[-1][1]<65536 and end-groups[-1][0]<=32*1024*1024:
                groups[-1][1]=end;groups[-1][2].append(entry)
            else:groups.append([info.header_offset,end,[entry]])
        remote.maximum_bytes=remote.transferred+sum(end-start for start,end,_ in groups)+1_000_000
        partial=args.output/'ema.safetensors.partial';hashing=hashlib.sha256()
        with partial.open('xb') as output:
            def write(data):output.write(data);hashing.update(data)
            write(struct.pack('<Q',len(encoded)));write(encoded)
            for index,(start,end,entries) in enumerate(groups):
                data=remote.fetch(start,end-start)
                for _,_,info in entries:write(tensor_payload(data,start,info))
                if index%10==0 or index==len(groups)-1:print(f'Extracted groups {index+1}/{len(groups)}',flush=True)
        destination=args.output/'ema.safetensors';partial.rename(destination)
        result.update(extractionCompleted=True,outputBytes=destination.stat().st_size,outputSHA256=hashing.hexdigest(),transferredBytes=remote.transferred)
        report.write_text(json.dumps(result,indent=2)+'\n');print('Inference checkpoint extracted and CRC-checked.',flush=True)


if __name__=='__main__':main()
