#!/usr/bin/env python3
"""Bounded HTTP range reader for inspecting a public model ZIP checkpoint."""
import io
import time
import re
import requests


class HTTPRangeFile(io.RawIOBase):
    def __init__(self,url,maximum_bytes=8_000_000):
        self.session=requests.Session();self.url=url;self.position=0;self.transferred=0;self.maximum_bytes=maximum_bytes
        for attempt in range(4):
            with self.session.get(url,headers={'Range':'bytes=0-0','Accept-Encoding':'identity'},stream=True,timeout=30) as response:
                match=re.fullmatch(r'bytes 0-0/(\d+)',response.headers.get('Content-Range',''))
                if response.status_code==206 and match:
                    self.size=int(match.group(1));self.etag=response.headers.get('ETag');self.modified=response.headers.get('Last-Modified')
                    if response.raw.read(2)!=b'P':raise ValueError('Expected ZIP archive prefix')
                    break
                if attempt==3:raise ValueError(f'Cannot establish archive size from range response: HTTP {response.status_code}, type {response.headers.get("Content-Type")}')
            time.sleep(0.5*2**attempt)
        self.cache={};self.block_size=1048576
    def readable(self):return True
    def seekable(self):return True
    def tell(self):return self.position
    def seek(self,offset,whence=0):
        position=offset if whence==0 else self.position+offset if whence==1 else self.size+offset if whence==2 else -1
        if position<0:raise ValueError('Invalid seek')
        self.position=position;return position
    def fetch(self,start,length):
        if length==0:return b''
        if start<0 or length<0 or start+length>self.size:raise ValueError('Range exceeds archive')
        if self.transferred+length>self.maximum_bytes:raise ValueError('Range-read byte budget exceeded')
        for attempt in range(4):
            try:
                with self.session.get(self.url,headers={'Range':f'bytes={start}-{start+length-1}','Accept-Encoding':'identity'},stream=True,timeout=60) as response:
                    if response.status_code in (429,500,502,503,504) and attempt<3:
                        time.sleep(0.5*2**attempt);continue
                    response.raise_for_status()
                    expected=f'bytes {start}-{start+length-1}/{self.size}'
                    if response.status_code!=206 or response.headers.get('Content-Range')!=expected:raise ValueError('Server did not honor exact range')
                    if self.etag and response.headers.get('ETag')!=self.etag:raise ValueError('Archive ETag changed')
                    if self.modified and response.headers.get('Last-Modified')!=self.modified:raise ValueError('Archive modification time changed')
                    data=response.raw.read(length+1)
                    if len(data)!=length:raise ValueError('Wrong range byte count')
                break
            except requests.exceptions.RequestException:
                if attempt==3:raise
                time.sleep(0.5*2**attempt)
        self.transferred+=length;return data
    def read(self,size=-1):
        size=min(self.size-self.position,size if size>=0 else self.size-self.position)
        if size<=0:return b''
        result=[]
        while size:
            block=self.position//self.block_size
            if block not in self.cache:
                start=block*self.block_size;self.cache[block]=self.fetch(start,min(self.block_size,self.size-start))
            offset=self.position%self.block_size;part=self.cache[block][offset:offset+size]
            result.append(part);self.position+=len(part);size-=len(part)
        return b''.join(result)
    def readinto(self,buffer):
        data=self.read(len(buffer));buffer[:len(data)]=data;return len(data)
    def close(self):
        self.session.close();super().close()
