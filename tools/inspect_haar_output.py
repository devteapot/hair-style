#!/usr/bin/env python3
"""Recover ordered research strands from the pinned HAAR guiding PLY.

HAAR's decoder emits 100 points per guide, root first; infer.py flattens those
rows directly into its point cloud. This adapter preserves that ordering. It
never infers metric units, personal scalp attachment or anatomical alignment.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
from haar_worker import REVISION

TYPES={'char':'b','uchar':'B','short':'h','ushort':'H','int':'i','uint':'I',
       'float':'f','double':'d','int8':'b','uint8':'B','int16':'h','uint16':'H',
       'int32':'i','uint32':'I','float32':'f','float64':'d'}


def read_points(data):
    end=data.find(b'end_header\n')
    if end<0 or end>65536: raise ValueError('Missing or oversized PLY header')
    header=data[:end].decode('ascii').splitlines()
    if not header or header[0]!='ply': raise ValueError('Expected PLY')
    encoding=None;count=None;properties=[];element=None
    for line in header[1:]:
        fields=line.split()
        if not fields or fields[0] in ('comment','obj_info'):continue
        if fields[0]=='format':
            if len(fields)!=3 or fields[2]!='1.0' or encoding is not None:raise ValueError('Invalid PLY format')
            encoding=fields[1]
        elif fields[0]=='element':
            if len(fields)!=3:raise ValueError('Invalid element')
            element=fields[1];n=int(fields[2])
            if element=='vertex':
                if count is not None or not 100<=n<=1_000_000:raise ValueError('Invalid vertex count')
                count=n
            elif n!=0:raise ValueError('Expected point cloud without other nonempty elements')
        elif fields[0]=='property' and element=='vertex':
            if len(fields)!=3 or fields[1] not in TYPES:raise ValueError('Unsupported vertex property')
            properties.append((fields[2],TYPES[fields[1]]))
        elif fields[0]=='property' and element is not None:continue
        else:raise ValueError('Unsupported PLY header entry')
    names=[p[0] for p in properties]
    if count is None or len(names)!=len(set(names)) or not set('xyz')<=set(names):raise ValueError('Missing or duplicate positions')
    if any(properties[names.index(k)][1] not in ('f','d') for k in 'xyz'):raise ValueError('Positions must be floating point')
    if count%100:raise ValueError('Guiding point count must be divisible by the pinned decoder length of 100')
    payload=data[end+len(b'end_header\n'):]
    if encoding=='binary_little_endian':
        layout=struct.Struct('<'+''.join(p[1] for p in properties))
        if len(payload)!=count*layout.size:raise ValueError('PLY payload length does not match header')
        rows=layout.iter_unpack(payload)
    elif encoding=='ascii':
        lines=payload.decode('ascii').splitlines()
        if len(lines)!=count:raise ValueError('ASCII vertex count mismatch')
        def parse():
            for line in lines:
                fields=line.split()
                if len(fields)!=len(properties):raise ValueError('Invalid ASCII vertex record')
                yield tuple(float(x) if t in ('f','d') else int(x) for x,(_,t) in zip(fields,properties))
        rows=parse()
    else:raise ValueError('Only ASCII or little-endian binary PLY supported')
    indices=[names.index(k) for k in 'xyz'];points=[]
    for row in rows:
        p=[float(row[i]) for i in indices]
        if not all(math.isfinite(v) and abs(v)<1e6 for v in p):raise ValueError('Nonfinite or unbounded position')
        points.append(p)
    return points


def convert(report_path, output):
    run=json.loads(report_path.read_text())
    if run.get('model')!='HAAR' or run.get('revision')!=REVISION or not run.get('inferenceCompleted') or run.get('exitCode')!=0 or run.get('errors'):
        raise ValueError('Requires a completed, error-free pinned HAAR run')
    implementation=run.get('implementation','upstream_cli')
    sampling_seed=run.get('samplingSeed', run.get('seed'))
    if sampling_seed is not None and (type(sampling_seed) is not int or not 0 <= sampling_seed < 2**32):
        raise ValueError('Invalid recorded sampling seed')
    if implementation not in ('upstream_cli','metal_inference_port_v1'):raise ValueError('Unknown HAAR implementation')
    if implementation=='metal_inference_port_v1' and (not run.get('rootOrderVerified') or not run.get('stageReportSHA256')):
        raise ValueError('Metal port requires connected stage and root-order verification')
    evidence=run['output'];path=Path(evidence['path']).resolve()
    if not path.is_relative_to(report_path.resolve().parent):raise ValueError('Output must belong to this run directory')
    if not 1<=path.stat().st_size<=64_000_000:raise ValueError('Output size exceeds the 64 MB adapter limit')
    data=path.read_bytes();digest=hashlib.sha256(data).hexdigest()
    if len(data)!=evidence['bytes'] or digest!=evidence['sha256']:raise ValueError('Guiding output integrity mismatch')
    points=read_points(data);strands=[];lengths=[]
    for start in range(0,len(points),100):
        curve=points[start:start+100]
        length=sum(math.dist(a,b) for a,b in zip(curve,curve[1:]))
        if length<=1e-9:raise ValueError('Degenerate guide with no extent')
        strands.append(dict(id=f'haar-{start//100:05d}',points=curve));lengths.append(length)
    result=dict(schemaVersion=1,method='pinned_haar_flattened_guides_adapter_v1',modelRevision=REVISION,
        implementation=implementation,samplingSeed=sampling_seed,runReportSHA256=hashlib.sha256(report_path.read_bytes()).hexdigest(),sourcePLYSHA256=digest,
        coordinateConvention='haar_template_coordinates_unresolved',units='unresolved',pointsPerStrand=100,
        pointOrder='root_to_tip_as_emitted_by_texture2strands',strandCount=len(strands),strands=strands,
        lengthInSourceUnits=dict(minimum=min(lengths),maximum=max(lengths)),
        acceptedForPersonalHaircut=False,notes=['No vertex sorting, welding, resampling or nearest-neighbor curve reconstruction.',
            'The pinned decoder prepends the local root before cumulative offsets; infer.py preserves flattened row order.',
            'Personal scalp bindings, units, template-to-person mapping and feasibility validation remain required.'])
    with output.open('x') as stream:json.dump(result,stream,indent=2);stream.write('\n')
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run_report',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();result=convert(args.run_report,args.output)
    print(f'{result["strandCount"]} ordered research guides; personal attachment and units unresolved.')


if __name__=='__main__':main()
