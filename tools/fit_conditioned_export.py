"""Bounded canonical post-fit stage; never changes the original decoder export."""
import ast
import base64
import hashlib
import json
try:
    from .canonical_json import loads
except ImportError:
    from canonical_json import loads


def fit_export(out, inspector, invoke):
    def read(name):
        return loads((out / name).read_bytes())

    def write(name, value):
        (out / name).write_text(json.dumps(value, allow_nan=False) + '\n')

    clearance = read('export/clearance.json')
    if clearance['surfaceChecksPassed']:
        return {'status': 'unneeded'}
    conflicts = {v['guideID'] for v in clearance['violations']}
    if clearance.get('rootViolations') or not 1 <= len(conflicts) <= 128:
        return {'status': 'unsupported', 'reason': 'Requires clear roots and 1–128 conflicting guides.'}
    fit = out / 'direction-fit'
    fit.mkdir(mode=0o700)
    invoke('direction-proposal', [inspector, 'hair-rotate-proposal', out/'export/input.json',
        out/'export/haircut.json', out/'inputs/anatomy.json', fit/'proposal.json', '--diagonal-axes'])
    proposal = read('direction-fit/proposal.json')
    if not proposal['clearance']['surfaceChecksPassed']:
        return {'status': 'unresolved', 'reason': 'Bounded rotations did not clear all supplied anatomy.'}
    axes = {'x': (1, 0, 0), 'y': (0, 1, 0), 'z': (0, 0, 1)}
    rotations = []
    for decision in proposal['decisions']:
        label = decision.get('axis')
        if label is None:
            continue
        axis = axes[label] if label in axes else ast.literal_eval(label)
        if not isinstance(axis, (tuple, list)) or len(axis) != 3:
            raise ValueError('Invalid declared rotation axis')
        rotations.append(dict(guideID=decision['guideID'], axis=dict(zip(('x', 'y', 'z'), axis)),
                              degrees=decision['degrees']))
    source = (out/'inputs/source.json').read_bytes()
    if len(source) > 25_000_000:
        raise ValueError('Original sample exceeds fit byte budget')
    record = dict(schemaVersion=1, sourceHaircutSHA256=proposal['sourceHaircutSHA256'],
                  originalSampleData=base64.b64encode(source).decode(), rotations=rotations)
    write('direction-fit/record.json', record)
    write('direction-fit/haircut.json', proposal['haircut'])
    # A claimed passing search is insufficient: independently replay every edit
    # and enforce cumulative movement from the original model sample.
    invoke('direction-verification', [inspector, 'conditioning-fit-verify', out/'export/input.json',
        out/'export/haircut.json', fit/'haircut.json', out/'inputs/mapping.json',
        out/'inputs/anatomy.json', fit/'record.json', hashlib.sha256(source).hexdigest(), fit/'verification.json'])
    verification = read('direction-fit/verification.json')
    invoke('direction-mesh', [inspector, 'hair-mesh', out/'export/input.json', fit/'haircut.json',
                            fit/'mesh.json', '3', '1'], 120)
    mesh = read('direction-fit/mesh.json')
    if (not verification['clearance']['surfaceChecksPassed'] or
            mesh['haircutSHA256'] != verification['validation']['haircutSHA256'] or
            mesh['haircutSHA256'] != verification['clearance']['haircutSHA256'] or mesh['radiusScale'] != 1):
        raise ValueError('Verified direction fit and mesh disagree')
    return dict(status='verified', haircutSHA256=mesh['haircutSHA256'],
                correctedGuideCount=len(rotations),
                maximumCumulativeMovementMeters=verification['maximumCumulativeMovementMeters'])
