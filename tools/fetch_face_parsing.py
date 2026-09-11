#!/usr/bin/env python3
"""Fetch or verify the pinned research-only face parser; never reads captures."""
import argparse
import hashlib
import json
from pathlib import Path
from huggingface_hub import hf_hub_download

REPOSITORY = 'jonathandinu/face-parsing'
REVISION = '758b82e15a0178c9db39c1ff666a8b56e3a550c8'
FILES = {
    'README.md': (5617, 'd98d46f09fe6cf246482edff8cc386a0cb8c0dd2109fd04883b298c6069b5d82'),
    'config.json': (1689, '01d82e818569beda6aec804642e34ce187bed43326337d52ce370ff015964d68'),
    'preprocessor_config.json': (374, 'e5a25d8fc054bf780be930e161b47d188bec1b0bf0a44fd5fdfb3f3312c0be0b'),
    'model.safetensors': (338580732, 'c2bec795a8c243db71bd95be538fd62559003566466c71237e45c99b920f4b62'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('.research/face-parsing'))
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    manifest = {'repository': REPOSITORY, 'revision': REVISION,
                'licenseUse': 'non-commercial research and education per model card', 'files': {}}
    for name, (size, expected) in FILES.items():
        path = args.output/name
        if not args.verify_only:
            path = Path(hf_hub_download(repo_id=REPOSITORY, filename=name, revision=REVISION, local_dir=args.output, token=False))
        if path.stat().st_size != size:
            raise ValueError('Wrong pinned asset size: '+name)
        observed = hashlib.sha256(path.read_bytes()).hexdigest()
        if observed != expected:
            raise ValueError('Wrong pinned asset hash: '+name)
        manifest['files'][name] = {'byteCount': size, 'sha256': observed}
    if not args.verify_only:
        (args.output/'download-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    else:
        existing = json.loads((args.output/'download-manifest.json').read_text())
        if existing != manifest:
            raise ValueError('Pinned download manifest mismatch')
    print('Verified four pinned face-parser assets. Research/educational use only.')


if __name__ == '__main__':
    main()
