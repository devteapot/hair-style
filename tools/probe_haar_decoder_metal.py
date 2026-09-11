#!/usr/bin/env python3
"""Compare the pretrained NeuralHaircut decoder on CPU/MPS for random latents.

This verifies a decoder stage, not text-conditioned hairstyle generation.
"""
import argparse,hashlib,json,os,subprocess,sys,time
from pathlib import Path

REVISION='1dbdd07797458e6e0000bd3a02f3092d419d1756'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo',type=Path);parser.add_argument('checkpoint',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args()
    if args.output.exists():raise ValueError('Use a new report path')
    if subprocess.check_output(['git','-C',str(args.repo),'rev-parse','HEAD'],text=True).strip()!=REVISION:raise ValueError('Unexpected decoder revision')
    if os.environ.get('PYTORCH_ENABLE_MPS_FALLBACK') not in (None,'0'):raise ValueError('CPU fallback must be disabled')
    import torch
    torch.set_num_threads(4);torch.manual_seed(42)
    sys.path.insert(0,str(args.repo.resolve()/'src/hair_networks'))
    from strand_prior import Decoder
    checkpoint=torch.load(args.checkpoint,map_location='cpu',weights_only=True)
    model=Decoder(None,latent_dim=64,length=99).eval();model.load_state_dict(checkpoint['decoder'],strict=True)
    latent=torch.randn(1024,64)
    start=time.perf_counter()
    with torch.inference_mode():reference=model(latent)
    cpu_seconds=time.perf_counter()-start
    model=model.to('mps');input_mps=latent.to('mps');times=[]
    with torch.inference_mode():
        for _ in range(3):
            torch.mps.synchronize();start=time.perf_counter();result=model(input_mps);torch.mps.synchronize();times.append(time.perf_counter()-start)
    result=result.cpu();difference=(result-reference).abs()
    # Match upstream local curve construction: root then cumulative learned offsets.
    local=torch.cat([torch.zeros_like(result[:,:1]),result.cumsum(1)],dim=1)
    reference_local=torch.cat([torch.zeros_like(reference[:,:1]),reference.cumsum(1)],dim=1)
    report=dict(method='pretrained_strand_decoder_random_latent_cpu_mps_probe_v1',decoderRevision=REVISION,
        torchVersion=torch.__version__,checkpointSHA256=hashlib.sha256(args.checkpoint.read_bytes()).hexdigest(),
        parameterCount=sum(p.numel() for p in model.parameters()),latentShape=list(latent.shape),offsetShape=list(result.shape),curveShape=list(local.shape),
        seed=42,cpuFallbackEnabled=False,cpuForwardSeconds=cpu_seconds,mpsForwardSeconds=times,allFinite=bool(torch.isfinite(local).all()),
        maximumOffsetAbsoluteDifference=float(difference.max()),maximumCurveAbsoluteDifference=float((local-reference_local).abs().max()),
        allCloseAt1e5Absolute1e3Relative=bool(torch.allclose(reference,result,atol=1e-5,rtol=1e-3)),
        mpsAllocatedBytes=torch.mps.current_allocated_memory(),mpsDriverAllocatedBytes=torch.mps.driver_allocated_memory(),
        textConditionedGenerationCompleted=False,acceptedForPersonalHaircut=False,
        notes=['Actual pretrained decoder weights loaded strictly with weights_only=True.',
            'Latents are seeded random test vectors, not sampled HAAR hair textures.',
            'Curve units and world scalp placement are unresolved; no generated personal hairstyle is claimed.'])
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))


if __name__=='__main__':main()
