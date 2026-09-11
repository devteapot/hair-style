#!/usr/bin/env python3
"""Check port-specific preprocessing, sampling semantics and serialization."""
import ast
from pathlib import Path
import re
import tempfile
from types import SimpleNamespace
import numpy as np
import torch
from haar_text_metal import caption_processor
from haar_inference_metal import runtime
from haar_decode_metal import TemplateMesh, write_ply
from inspect_haar_output import read_points

repo = Path('.research/HAAR')
tree = ast.parse((repo / 'submodules/LAVIS/lavis/processors/blip_processors.py').read_text())
klass = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'BlipCaptionProcessor')
method = next(n for n in klass.body if isinstance(n, ast.FunctionDef) and n.name == 'pre_caption')
namespace = {'re': re}
exec(compile(ast.Module(body=[method], type_ignores=[]), 'upstream_caption', 'exec'), namespace)
for text in ['  SHORT! Straight... hair\n', 'one\t\ttwo\nthree', ' '.join(str(i) for i in range(60)), 'coily, side-parted HAIR', '']:
    assert caption_processor(text) == namespace['pre_caption'](SimpleNamespace(max_words=50), text)

rt = runtime(repo)
sigmas = rt.sigmas(50, .01, 80)
assert len(sigmas) == 51 and sigmas[-1] == 0 and bool((sigmas[:-1] > sigmas[1:]).all())
calls = []
def constant_model(x, sigma, cross_cond):
    calls.append(float(cross_cond.mean()))
    return torch.ones_like(x) * cross_cond.mean()
shape = (1, 2, 2, 2)
result = rt.sample(constant_model, torch.ones(shape), sigmas, extra_args={
    'cross_cond': torch.full((1, 1, 768), 2.), 'cross_cond_zero': torch.zeros(1, 1, 768)},
    cfg_scale=1.5, eta=0, noise_sampler=lambda a,b: torch.zeros(shape), disable=True)
assert len(calls) == 100 and calls == [2., 0.] * 50
assert torch.allclose(result, torch.full(shape, 3.), atol=1e-5)

vertices = np.array([[0,0,0], [1,0,0], [0,1,0]], dtype=np.float32)
mesh = TemplateMesh(vertices, np.array([[0,1,2]], dtype=np.int64))
assert torch.equal(mesh.faces_normals_packed(), torch.tensor([[0.,0.,1.]]))
assert torch.equal(TemplateMesh(vertices, np.array([[0,2,1]], dtype=np.int64)).faces_normals_packed(), torch.tensor([[0.,0.,-1.]]))
try:
    TemplateMesh(vertices, np.array([[0,1,1]], dtype=np.int64)).faces_normals_packed()
except ValueError:
    pass
else:
    raise AssertionError('Degenerate face accepted')
curves = np.arange(600, dtype=np.float32).reshape(2,100,3) / 1000
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'guides.ply'
    write_ply(path, curves)
    recovered = np.array(read_points(path.read_bytes()), dtype=np.float32).reshape(2,100,3)
    assert np.array_equal(curves, recovered)
print('Upstream caption equivalence, 50-step guidance semantics, face winding and root-to-tip PLY ordering passed.')
