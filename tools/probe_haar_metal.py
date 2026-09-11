#!/usr/bin/env python3
"""Run HAAR's full configured UNet on CPU and Metal.

Uses random weights unless --checkpoint supplies an extracted EMA safetensors file.
An operator/architecture portability probe only. No complete pretrained inference, text
embedding, sampling trajectory, strand decoding or personalization is claimed.
"""
import argparse,hashlib,json,os,platform,subprocess,sys,time
from pathlib import Path
from haar_worker import REVISION


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('repo',type=Path);parser.add_argument('output',type=Path);parser.add_argument('--checkpoint',type=Path)
    args=parser.parse_args();repo=args.repo.resolve()
    if args.output.exists():raise ValueError('Use a new report path')
    if os.environ.get('PYTORCH_ENABLE_MPS_FALLBACK') not in (None,'0'):raise ValueError('Disable CPU fallback for an explicit Metal probe')
    actual=subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip()
    if actual!=REVISION:raise ValueError('Unexpected HAAR revision')
    import torch
    torch.set_num_threads(4);torch.manual_seed(42)
    if not torch.backends.mps.is_available():raise RuntimeError('Metal is unavailable')
    sys.path.insert(0,str(repo/'src'))
    from openaimodel import UNetModel
    config_path=repo/'configs/infer.json';config=json.loads(config_path.read_text())['model']
    model=UNetModel(image_size=config['input_size'][0],in_channels=config['input_channels'],model_channels=config['model_channels'],
        out_channels=config['input_channels'],num_res_blocks=config['num_res_blocks'],attention_resolutions=config['attention_resolutions'],
        dropout=0,channel_mult=config['channel_mult'],conv_resample=True,dims=2,num_classes=None,use_checkpoint=False,use_fp16=False,
        num_heads=config['num_heads'],num_head_channels=config['num_head_channels'],num_heads_upsample=-1,
        use_scale_shift_norm=config['use_scale_shift_norm'],resblock_updown=config['resblock_updown'],use_new_attention_order=False,
        use_spatial_transformer=config['use_spatial_transformer'],transformer_depth=config['transformer_depth'],
        context_dim=config['context_dim'],n_embed=None,legacy=config['legacy']).eval()
    activated=0
    checkpoint_hash=None
    if args.checkpoint:
        from safetensors.torch import load_file
        model.load_state_dict(load_file(str(args.checkpoint)),strict=True,assign=True)
        hashing=hashlib.sha256()
        with args.checkpoint.open('rb') as stream:
            for block in iter(lambda:stream.read(8*1024*1024),b''):hashing.update(block)
        checkpoint_hash=hashing.hexdigest()
    with torch.no_grad():
        for name,p in model.named_parameters():
            if not args.checkpoint and name.endswith('weight') and p.ndim>=2 and not bool(torch.count_nonzero(p)):
                p.normal_(0,0.005);activated+=1
    x=torch.randn(1,config['input_channels'],*config['input_size']);t=torch.tensor([1.0]);context=torch.randn(1,1,config['context_dim'])
    report=dict(method='haar_pretrained_full_unet_cpu_mps_probe_v1' if args.checkpoint else 'haar_random_weight_full_unet_cpu_mps_probe_v1',modelRevision=actual,torchVersion=torch.__version__,
        platform=platform.platform(),configSHA256=hashlib.sha256(config_path.read_bytes()).hexdigest(),
        checkpointSHA256=checkpoint_hash,pretrainedDenoiserForward=bool(args.checkpoint),parameterCount=sum(p.numel() for p in model.parameters()),inputShape=list(x.shape),contextShape=list(context.shape),
        dtype='float32',seed=42,activatedZeroWeightTensors=activated,cpuFallbackEnabled=False,pretrainedInferenceCompleted=False,
        strandsGenerated=False,notes=['Strictly loaded pretrained EMA weights with seeded random inputs; one forward, not a denoising trajectory.' if args.checkpoint else 'Seeded random weights only; zero output/residual projections made nonzero to exercise numerical paths.',
            'Does not test BLIP, sampler trajectory, strand decoder, custom mesh operations or trained-output quality.'])
    start=time.perf_counter()
    with torch.inference_mode():reference=model(x,t,cross_cond=context)
    report['cpuForwardSeconds']=time.perf_counter()-start
    model=model.to('mps');mx=x.to('mps');mt=t.to('mps');mc=context.to('mps')
    timings=[]
    with torch.inference_mode():
        for _ in range(3):
            torch.mps.synchronize();start=time.perf_counter();result=model(mx,mt,cross_cond=mc);torch.mps.synchronize()
            timings.append(time.perf_counter()-start)
    observed=result.cpu();difference=(reference-observed).abs()
    report.update(mpsForwardSeconds=timings,allFinite=bool(torch.isfinite(observed).all()),
        maximumAbsoluteDifference=float(difference.max()),meanAbsoluteDifference=float(difference.mean()),
        cpuOutputMaximumAbsolute=float(reference.abs().max()),
        allCloseAt1e4Absolute1e3Relative=bool(torch.allclose(reference,observed,atol=1e-4,rtol=1e-3)),
        mpsAllocatedBytes=torch.mps.current_allocated_memory(),mpsDriverAllocatedBytes=torch.mps.driver_allocated_memory())
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
