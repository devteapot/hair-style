#!/usr/bin/env python3
"""Export a prepared neural curve bundle through the canonical Swift importer.

Preserves the base model source and distinct conditioning provenance; no automatic
physical or aesthetic acceptance. Whole-curve clearance remains a separate gate.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import uuid
import numpy as np
from safetensors.numpy import load_file
from scalp_attachments import attachment_positions


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_bytes())
def write(path,value):path.write_text(json.dumps(value,indent=2,allow_nan=False)+'\n')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('optimization','regional','source','output'):p.add_argument(name,type=Path)
    p.add_argument('--trajectory-report',type=Path,required=True)
    p.add_argument('--inspector',type=Path,default=Path(__file__).resolve().parents[1]/'.build/debug/capture-inspect')
    args=p.parse_args();opt=args.optimization;reg=args.regional;out=args.output
    initial=read(opt/'report.json');regional=read(reg/'report.json');source=read(args.source)
    trajectory=read(args.trajectory_report);seed=trajectory.get('seed')
    if (type(seed) is not int or not 0<=seed<=2**31-1 or trajectory.get('textureSHA256')!=initial['textureSHA256']
            or trajectory.get('modelRevision')!=source['modelRevision'] or source.get('samplingSeed',seed)!=seed):
        raise ValueError('Sampling seed or latent texture provenance mismatch')
    inp=read(reg/'generation-input.json');mapping=read(reg/'mapping.json')
    for name,key in [('generation-input.json','inputSHA256'),('mapping.json','mappingSHA256')]:
        if digest(reg/name)!=initial[key] or digest(reg/name)!=regional[key] or (opt/name).read_bytes()!=(reg/name).read_bytes():
            raise ValueError('Conditioning input provenance mismatch')
    if (initial['sourceSHA256']!=digest(args.source) or mapping['sourceArtifactSHA256']!=digest(args.source)
            or regional['sourceOptimizationSHA256']!=digest(opt/'curves.safetensors')
            or regional['finalUnresolved']!=0 or initial['cpuMPSGradientAgreement'] is not True
            or initial['pretrainedWeightsChanged'] is not False):
        raise ValueError('Conditioning source or completion evidence mismatch')
    # This exporter consumes the new durable-preparation path, not arbitrary tensors.
    if (opt/'preparation-result.json').read_bytes()!=(reg/'preparation-result.json').read_bytes():
        raise ValueError('Neural stages used different preparation results')
    for directory,report in [(opt,initial),(reg,regional)]:
        if (report['rootPreflight']['preparedBrief']['preparationOutputSHA256']!=digest(directory/'preparation-result.json')
                or report['rootPreflight']['reportSHA256']!=digest(directory/'root-preflight.json')):
            raise ValueError('Preparation provenance changed after conditioning')
    data=load_file(str(reg/'curves.safetensors'));count=len(mapping['mappings'])
    points=data['optimizedTemplate'].astype(float);mapped=data['optimizedMapped'].astype(float)
    if points.shape!=(count,100,3) or mapped.shape!=points.shape or not np.isfinite(points).all() or not np.isfinite(mapped).all():
        raise ValueError('Invalid conditioned tensor shape or values')
    if len(source['strands'])!=count or [s['id'] for s in source['strands']]!=[m['guideID'] for m in mapping['mappings']]:
        raise ValueError('Conditioned guide identities changed')
    base=np.array([s['points'] for s in source['strands']],dtype=float)
    if (base.shape!=points.shape or not np.isfinite(base).all() or not np.isfinite(data['originalTemplate']).all()
            or np.max(np.abs(base-data['originalTemplate']))>2e-5):
        raise ValueError('Original template does not replay the base model source')
    if not np.array_equal(data['originalMapped'][:,0],data['optimizedMapped'][:,0]):
        raise ValueError('Neural conditioning changed attachments')
    xyz=lambda v:np.array([v[k] for k in ('x','y','z')],dtype=float)
    roots=attachment_positions(inp['scalp'],[item['binding'] for item in mapping['mappings']])
    replay=(points-points[:,:1])*xyz(mapping['metersPerSourceUnit'])+roots[:,None]
    error=float(np.max(np.abs(replay-mapped)))
    if error>2e-6:raise ValueError('Template-to-person correspondence does not replay')
    out.mkdir(parents=True,exist_ok=False)
    def cli(*values):subprocess.run([str(args.inspector.resolve()),*map(str,values)],check=True,timeout=120)
    # Recompute preparation eligibility before publishing any canonical artifact.
    cli('preparation-consume',reg/'preparation-result.json',digest(reg/'preparation-result.json'),
        reg/'source-input.json',reg/'prepared-brief.json',reg/'mapping.json',reg/'anatomy.json',out/'input.json')
    if (out/'input.json').read_bytes()!=(reg/'generation-input.json').read_bytes():raise ValueError('Prepared input changed')
    cli('hair-conditioning-binding',out/'input.json',reg/'mapping.json',out/'binding.json')
    binding=read(out/'binding.json')
    manifest=dict(method='conditioned_curve_export_v1',scriptSHA256=digest(Path(__file__)),
        attachmentReplaySHA256=digest(Path(__file__).with_name('scalp_attachments.py')),
        nonzeroNormalOffsetAttachments=sum(item['binding']['normalOffsetMeters']!=0 for item in mapping['mappings']),
        baseSourceSHA256=digest(args.source),baseRunReportSHA256=source['runReportSHA256'],
        trajectoryReportSHA256=digest(args.trajectory_report),samplingSeed=seed,
        optimizationReportSHA256=digest(opt/'report.json'),regionalReportSHA256=digest(reg/'report.json'),
        curveBundleSHA256=digest(reg/'curves.safetensors'),preparationOutputSHA256=digest(reg/'preparation-result.json'),
        templateMappingMaximumErrorMeters=error,guideCount=count,acceptedForPersonalHaircut=False)
    write(out/'export-manifest.json',manifest)
    artifact={k:source[k] for k in ('schemaVersion','modelRevision','sourcePLYSHA256','coordinateConvention','units',
        'pointsPerStrand','pointOrder','strandCount')}
    artifact.update(method='personal_envelope_decoder_latents_v1',implementation='metal_decoder_personal_constraints_v1',
        runReportSHA256=digest(out/'export-manifest.json'),samplingSeed=seed,acceptedForPersonalHaircut=False,
        conditioning=dict(**binding,baseSourceSHA256=digest(args.source),optimizationReportSHA256=digest(opt/'report.json'),
            regionalReportSHA256=digest(reg/'report.json'),decoderSHA256=initial['decoderSHA256']),
        strands=[dict(id=item['guideID'],points=curve.tolist()) for item,curve in zip(mapping['mappings'],points)])
    write(out/'source.json',artifact)
    exported=copy.deepcopy(mapping);exported['id']=str(uuid.uuid4());exported['sourceArtifactSHA256']=digest(out/'source.json')
    exported['method']='Prepared personal decoder output; correspondence, physical fit and style require review'
    write(out/'mapping.json',exported)
    cli('hair-model-import',out/'input.json',out/'source.json',out/'mapping.json',out/'imported.json')
    imported=read(out/'imported.json');write(out/'haircut.json',imported['haircut'])
    # Canonical validity does not establish clearance against observed anatomy.
    # Always retain that separate result before reporting a finished export.
    clearance_process=subprocess.run([str(args.inspector.resolve()),'hair-clearance',
        str(out/'input.json'),str(out/'haircut.json'),str(reg/'anatomy.json'),str(out/'clearance.json')],
        check=False,timeout=120)
    if clearance_process.returncode not in (0,2):
        raise RuntimeError('Observed-anatomy clearance did not complete')
    clearance=read(out/'clearance.json')
    haircut_hash=imported['validation']['haircutSHA256']
    if (clearance['haircutSHA256']!=haircut_hash
            or clearance['surfaceChecksPassed'] is not (clearance_process.returncode==0)):
        raise ValueError('Clearance result does not match the exported haircut or process outcome')
    report=dict(method='conditioned_export_review_v1',guideCount=count,haircutSHA256=haircut_hash,
        exportManifestSHA256=digest(out/'export-manifest.json'),clearanceReportSHA256=digest(out/'clearance.json'),
        suppliedSurfaceChecksPassed=clearance['surfaceChecksPassed'],
        segmentViolationCount=len(clearance['violations']),
        conflictingGuideCount=len({v['guideID'] for v in clearance['violations']}),
        rootViolationCount=len(clearance.get('rootViolations',[])),
        missingRegions=clearance['missingRegions'],status='research_review_required',acceptedForPersonalHaircut=False)
    write(out/'review-report.json',report)
    print(json.dumps(report))


if __name__=='__main__':main()
