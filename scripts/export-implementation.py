#!/usr/bin/env python3
"""Export a completed implementation from Vivado's private build filesystem."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys

core = sys.argv[1]
if core not in ('menu', 'nes', 'snes', 'gb', 'gba', 'psx', 'n64', 'md'):
    raise ValueError('Expected menu, nes, snes, gb, gba, psx or n64')
project = Path(os.environ.get('KRIA_BUILD_OUTPUT', f'/build/kria-mister-{core}-vivado')).resolve()
if project.parent != Path('/build'):
    raise ValueError('KRIA_BUILD_OUTPUT must name a direct child of /build')
source = project/'implementation'
root = Path(__file__).resolve().parents[1]
destination = root/'build/implementations'/core
record = json.loads((source/'implementation.json').read_text())
if record['core'] != core or record['stage'] != 'route_design':
    raise ValueError('Incomplete implementation record')
for name, expected in record['artifacts'].items():
    if Path(name).name != name:
        raise ValueError('Implementation filenames must be flat')
    if hashlib.sha256((source/name).read_bytes()).hexdigest() != expected:
        raise ValueError('Changed implementation artifact: '+name)
destination.mkdir(parents=True, exist_ok=True)
for name in record['artifacts']:
    shutil.copyfile(source/name, destination/name)
shutil.copyfile(source/'implementation.json', destination/'implementation.json')
print('Exported verified implementation:', destination)
