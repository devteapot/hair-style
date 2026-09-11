#!/usr/bin/env python3
"""Measure raw model response under the existing provisional affine mapping."""
import argparse
import json
import math
from pathlib import Path
import statistics


def analyze(root):
    rows=[];sets={}
    for name in ['short','long']:
        directory=root/name
        mapping=json.loads((directory/'preparation/mapping.json').read_text())
        source=json.loads((directory/'sample/guides/research-strands.json').read_text())
        report=json.loads((directory/'sample/report.json').read_text())
        brief=json.loads((directory/'preparation/prepared-brief.json').read_text())
        limits={v['region']:v for v in brief['compiled']['input']['brief']['lengthLimits']}
        scales=[mapping['metersPerSourceUnit'][k] for k in ('x','y','z')]
        assert len(source['strands'])==len(mapping['mappings'])
        lengths={};roots={}
        for guide,binding in zip(source['strands'],mapping['mappings']):
            assert guide['id']==binding['guideID']
            roots[guide['id']]=guide['points'][0]
            if binding['region']!='fringe':continue
            lengths[guide['id']]=sum(math.sqrt(sum(((b[i]-a[i])*scales[i])**2 for i in range(3))) for a,b in zip(guide['points'],guide['points'][1:]))
        lo=limits['fringe']['minimumMeters'];hi=limits['fringe']['maximumMeters']
        rows.append(dict(name=name,description=report['description'],seed=report['seed'],fringeGuideCount=len(lengths),
            provisionalMedianLengthMeters=statistics.median(lengths.values()),minimumMeters=min(lengths.values()),maximumMeters=max(lengths.values()),
            requestedMinimumMeters=lo,requestedMaximumMeters=hi,withinRequestedRange=sum(lo<=v<=hi for v in lengths.values()),
            belowRange=sum(v<lo for v in lengths.values()),aboveRange=sum(v>hi for v in lengths.values())))
        sets[name]=(lengths,roots,mapping)
    assert rows[0]['seed']==rows[1]['seed']
    assert sets['short'][2]==sets['long'][2]
    assert sets['short'][0].keys()==sets['long'][0].keys()
    delta=[sets['long'][0][key]-value for key,value in sets['short'][0].items()]
    rootdelta=max(math.dist(sets['short'][1][key],value) for key,value in sets['long'][1].items())
    return dict(method='controlled_length_prompt_response_v1',samples=rows,medianPairedLengthChangeMeters=statistics.median(delta),
        longerGuides=sum(v>0 for v in delta),templateRootMaximumDifference=rootdelta,
        physicalFitVerified=False,personalStyleVerified=False,
        limitations=['Lengths use the retained provisional affine scale; these are not measured person-fit lengths.',
            'No correction, trimming or fitting was applied before this comparison.',
            'One paired seed is not generalization evidence; numeric prompt compliance remains an empirical question.'])

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('directory',type=Path);args=p.parse_args()
    result=analyze(args.directory);(args.directory/'comparison.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
