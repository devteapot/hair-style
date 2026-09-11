"""Run the canonical attachment check before importing neural dependencies."""
import hashlib
import json
from pathlib import Path
import subprocess


def add_arguments(parser):
    parser.add_argument('--anatomy', type=Path, required=True)
    parser.add_argument('--material-radius-meters', type=float, required=True)
    parser.add_argument('--prepared-brief', type=Path,
                        help='Replay a prepared brief against INPUT before personal conditioning.')
    parser.add_argument('--preparation-result', type=Path,
                        help='Consume a durable preparation result bound to INPUT, prepared brief, mapping and anatomy.')
    parser.add_argument('--preparation-output-sha256',
                        help='Expected published byte hash of the durable preparation result.')
    parser.add_argument('--inspector', type=Path,
                        default=Path(__file__).resolve().parents[1]/'.build/debug/capture-inspect')


def run(args):
    # Reserve a new run directory; never reuse an earlier passing report.
    args.output.mkdir(parents=True, exist_ok=False)
    handoff=None
    prepared=getattr(args,'prepared_brief',None)
    result_file=getattr(args,'preparation_result',None)
    result_hash=getattr(args,'preparation_output_sha256',None)
    if bool(result_file) != bool(result_hash) or (result_file is not None and prepared is None):
        raise ValueError('A durable preparation requires its published hash and original prepared brief')
    if result_file is not None:
        snapshots={}
        for name,path,limit in [('preparation-result.json',result_file,100_000_000),
                ('source-input.json',args.input,25_000_000),('prepared-brief.json',prepared,25_000_000),
                ('mapping.json',args.mapping,25_000_000),('anatomy.json',args.anatomy,25_000_000)]:
            if path.stat().st_size>limit:raise ValueError('Durable preparation input exceeds its byte budget')
            data=path.read_bytes()
            if len(data)>limit:raise ValueError('Durable preparation input exceeds its byte budget')
            snapshots[name]=args.output/name;snapshots[name].write_bytes(data)
        consumed=args.output/'generation-input.json'
        args.mapping=snapshots['mapping.json'];args.anatomy=snapshots['anatomy.json']
        result=subprocess.run([str(args.inspector.resolve()),'preparation-consume',str(snapshots['preparation-result.json'].resolve()),result_hash,
            str(snapshots['source-input.json'].resolve()),str(snapshots['prepared-brief.json'].resolve()),
            str(args.mapping.resolve()),str(args.anatomy.resolve()),str(consumed.resolve())],timeout=120)
        if result.returncode:
            raise RuntimeError('Durable preparation replay rejected before model loading')
        handoff=dict(preparationOutputSHA256=result_hash,generationInputFileSHA256=hashlib.sha256(consumed.read_bytes()).hexdigest())
        (args.output/'brief-handoff.json').write_text(json.dumps(handoff,indent=2)+'\n')
        args.input=consumed
    elif prepared is not None:
        # Snapshot both sides of the source binding before replay and later model use.
        source_data=args.input.read_bytes();prepared_data=prepared.read_bytes()
        if len(source_data)>25_000_000 or len(prepared_data)>25_000_000:
            raise ValueError('Prepared brief handoff exceeds its input budget')
        source=args.output/'source-input.json';saved=args.output/'prepared-brief.json'
        source.write_bytes(source_data);saved.write_bytes(prepared_data)
        consumed=args.output/'generation-input.json'
        result=subprocess.run([str(args.inspector.resolve()),'brief-consume',str(source.resolve()),
            str(saved.resolve()),str(consumed.resolve())],timeout=120)
        if result.returncode:
            raise RuntimeError('Prepared brief replay failed before root checking or model loading')
        handoff=dict(sourceFileSHA256=hashlib.sha256(source_data).hexdigest(),
            preparedFileSHA256=hashlib.sha256(prepared_data).hexdigest(),
            generationInputFileSHA256=hashlib.sha256(consumed.read_bytes()).hexdigest())
        (args.output/'brief-handoff.json').write_text(json.dumps(handoff,indent=2)+'\n')
        args.input=consumed
    report_path = args.output/'root-preflight.json'
    result = subprocess.run([str(args.inspector.resolve()), 'hair-root-preflight',
        str(args.input.resolve()), str(args.mapping.resolve()), str(args.anatomy.resolve()),
        str(args.material_radius_meters), str(report_path.resolve())], timeout=120)
    if result.returncode == 2:
        raise SystemExit('Attachment review required; no neural model was loaded. See '+str(report_path))
    if result.returncode:
        raise RuntimeError('Canonical root preflight failed')
    data = report_path.read_bytes()
    report = json.loads(data)
    if (report.get('method') != 'proposed_root_clearance_preflight_v1'
            or report.get('requiresAttachmentReview') is not False
            or report.get('suppliedSurfacesPassed') is not True
            or report.get('violations') != []
            or report.get('physicalFitVerified') is not False):
        raise ValueError('Invalid root preflight result')
    result=dict(reportSHA256=hashlib.sha256(data).hexdigest(),
                missingRegions=report['missingRegions'], physicalFitVerified=False)
    if handoff is not None:result['preparedBrief']=handoff
    return result
