#!/usr/bin/env python3
"""Decode a HAAR texture onto the upstream template scalp on CPU and Metal.

Template coordinates and units remain research data, not a personal head fit.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys
import time
import numpy as np
from haar_inference_metal import definitions, verify_repo
from haar_text_metal import sha256
from haar_worker import REVISION
from probe_haar_decoder_metal import REVISION as DECODER_REVISION


def read_obj(path):
    vertices, faces = [], []
    for line in Path(path).read_text().splitlines():
        fields = line.split()
        if not fields or fields[0].startswith('#'):
            continue
        if fields[0] == 'v':
            if len(fields) != 4:
                raise ValueError('Expected 3D OBJ vertices')
            vertices.append([float(x) for x in fields[1:]])
        elif fields[0] == 'f':
            if len(fields) != 4:
                raise ValueError('Expected triangular OBJ faces')
            faces.append([int(x.split('/')[0]) - 1 for x in fields[1:]])
    verts, tris = np.asarray(vertices, dtype=np.float32), np.asarray(faces, dtype=np.int64)
    if verts.ndim != 2 or verts.shape[1] != 3 or not np.isfinite(verts).all() or tris.ndim != 2 or tris.shape[1] != 3:
        raise ValueError('Invalid OBJ mesh')
    if tris.min() < 0 or tris.max() >= len(verts):
        raise ValueError('OBJ face index out of range')
    return verts, tris


class TemplateMesh:
    """The three packed-mesh accessors used by upstream scalp basis setup."""
    def __init__(self, vertices, faces):
        import torch
        self.vertices = torch.from_numpy(vertices)
        self.faces = torch.from_numpy(faces)
    def verts_packed(self):
        return self.vertices
    def faces_packed(self):
        return self.faces
    def faces_normals_packed(self):
        import torch
        triangles = self.vertices[self.faces]
        normals = torch.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0], dim=-1)
        length = normals.norm(dim=-1, keepdim=True)
        if bool((length < 1e-12).any()):
            raise ValueError('Degenerate template faces')
        return normals / length


def setup(repo, scalp, decoder_checkpoint, seed):
    import torch
    verify_repo(repo, REVISION)
    verify_repo(repo / 'submodules/NeuralHaircut', DECODER_REVISION)
    geometry_path = repo / 'src/utils/geometry.py'
    spec = importlib.util.spec_from_file_location('haar_geometry', geometry_path)
    geometry = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(geometry)
    namespace = definitions(repo / 'src/datasets/dataset.py', ['Hairstyle'], {
        'Dataset': torch.utils.data.Dataset, 'torch': torch,
        'barycentric_coordinates_of_projection': geometry.barycentric_coordinates_of_projection})
    # Inference-only initialization: the original initializer also loads a
    # training dataset/encoder and hardcodes CUDA for several tensors.
    hairstyle = namespace['Hairstyle'].__new__(namespace['Hairstyle'])
    hairstyle.device = 'cpu'
    hairstyle.texture_size, hairstyle.patch_size, hairstyle.desc_size = 64, 32, 64
    vertices, faces = read_obj(scalp / 'final_scalp.obj')
    hairstyle.scalp_mesh = TemplateMesh(vertices, faces)
    hairstyle.scalp_uvs = torch.load(scalp / 'symmetry_scalp_uvcoords.pth', map_location='cpu', weights_only=True)[None].float()
    if hairstyle.scalp_uvs.shape != (1, len(vertices), 2):
        raise ValueError('Scalp UV/vertex mismatch')
    hairstyle._setup_basis()
    u, v = np.meshgrid(np.linspace(-1., 1., 64), np.linspace(-1., 1., 64))
    mapped = geometry.map_uv_to_3d(u, v, faces, hairstyle.scalp_uvs.numpy(), vertices)
    hairstyle.faces_for_each_origin = mapped[:, :, 3].long()
    hairstyle.coords_for_each_origin = mapped[:, :, :3].float()
    hairstyle.meshgrid_mask = hairstyle.faces_for_each_origin != -100
    torch.manual_seed(seed)
    hairstyle._create_average_texture()
    sys.path.insert(0, str(repo / 'submodules/NeuralHaircut/src/hair_networks'))
    from strand_prior import Decoder
    hairstyle.dec = Decoder(None, latent_dim=64, length=99).eval()
    state = torch.load(decoder_checkpoint, map_location='cpu', weights_only=True)
    hairstyle.dec.load_state_dict(state['decoder'], strict=True)
    return hairstyle


def write_ply(path, strands):
    points = np.asarray(strands, dtype='<f4').reshape(-1, 3)
    header = ('ply\nformat binary_little_endian 1.0\ncomment HAAR template research output; units unresolved\n'
              f'element vertex {len(points)}\nproperty float x\nproperty float y\nproperty float z\nend_header\n')
    with Path(path).open('xb') as stream:
        stream.write(header.encode('ascii'))
        stream.write(points.tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo', type=Path)
    parser.add_argument('scalp', type=Path)
    parser.add_argument('decoder_checkpoint', type=Path)
    parser.add_argument('texture', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--root-seed', type=int, default=42)
    args = parser.parse_args()
    import torch
    from safetensors.torch import load_file, save_file
    if os.environ.get('PYTORCH_ENABLE_MPS_FALLBACK') not in (None, '0'):
        raise ValueError('Disable CPU fallback')
    if not torch.backends.mps.is_available():
        raise RuntimeError('Metal unavailable')
    torch.set_num_threads(4)
    args.output.mkdir(parents=True, exist_ok=False)
    start = time.perf_counter()
    hairstyle = setup(args.repo.resolve(), args.scalp, args.decoder_checkpoint, args.root_seed)
    setup_seconds = time.perf_counter() - start
    texture = load_file(str(args.texture))['texture']
    if texture.shape != (1, 64, 32, 32) or texture.dtype != torch.float32 or not bool(torch.isfinite(texture).all()):
        raise ValueError('Invalid latent texture')
    start = time.perf_counter()
    with torch.inference_mode():
        cpu = hairstyle.texture2strands(texture)
    cpu_seconds = time.perf_counter() - start
    hairstyle.dec.to('mps')
    for name in ('small_R_inv', 'small_origins', 'nonzerox', 'nonzeroy'):
        setattr(hairstyle, name, getattr(hairstyle, name).to('mps'))
    start = time.perf_counter()
    with torch.inference_mode():
        metal = hairstyle.texture2strands(texture.to('mps'))
    torch.mps.synchronize()
    metal_seconds = time.perf_counter() - start
    metal = metal.cpu()
    if not bool(torch.isfinite(metal).all()):
        raise ValueError('Nonfinite decoded geometry')
    difference = (metal - cpu).abs()
    strands = metal[0].numpy()
    lengths = np.linalg.norm(np.diff(strands, axis=1), axis=-1).sum(axis=1)
    attachment = float((metal[0, :, :1] - hairstyle.small_origins.cpu()).norm(dim=-1).max())
    save_file({'strands': metal[0].contiguous(), 'roots': hairstyle.small_origins.cpu().contiguous()}, str(args.output / 'strands.safetensors'))
    write_ply(args.output / 'guides.ply', strands)
    report = dict(method='haar_template_strand_decode_cpu_mps_v1', modelRevision=REVISION, decoderRevision=DECODER_REVISION,
        decoderSHA256=sha256(args.decoder_checkpoint), textureSHA256=sha256(args.texture),
        scalpFiles={p.name: sha256(p) for p in sorted(args.scalp.iterdir()) if p.is_file()},
        rootSeed=args.root_seed, rootInitialization='upstream 1000 subsample intersection, CPU RNG',
        setupSeconds=setup_seconds, cpuSeconds=cpu_seconds, mpsSeconds=metal_seconds,
        strandCount=len(strands), pointsPerStrand=100, allFinite=True,
        maximumAbsoluteDifference=float(difference.max()), meanAbsoluteDifference=float(difference.mean()),
        allCloseAt1e5Absolute1e3Relative=bool(torch.allclose(cpu, metal, atol=1e-5, rtol=1e-3)),
        maximumRootAttachmentError=attachment, lengthRange=[float(lengths.min()), float(lengths.max())],
        bounds=[strands.min(axis=(0, 1)).tolist(), strands.max(axis=(0, 1)).tolist()],
        plySHA256=sha256(args.output / 'guides.ply'), strandsSHA256=sha256(args.output / 'strands.safetensors'),
        cpuFallbackEnabled=False, templateStrandsGenerated=True, acceptedForPersonalHaircut=False,
        units='unresolved upstream template units',
        notes=['Unchanged upstream basis, UV mapping, root sampling and texture2strands methods.',
               'Packed-mesh accessors replaced with an OBJ-order-preserving CPU mesh adapter.',
               'Generic template output; not fitted to participant scans or validated as a feasible haircut.'])
    (args.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
