#!/usr/bin/env python3
"""Package any core implementing the KV260 ABI as one copy-and-launch .k26 file."""
import argparse
import copy
import hashlib
from pathlib import Path
import sys
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'software/loader'))
from kria_core import ABI,MEMORY_SIZE,write_package,verify
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('output',type=Path)
p.add_argument('--id',required=True)
p.add_argument('--firmware',type=Path,required=True)
p.add_argument('--overlay',type=Path,required=True)
p.add_argument('--base',type=Path,
               help='verified package whose metadata and embedded assets are preserved')
p.add_argument('--asset',action='append',default=[],metavar='NAME=PATH')
a=p.parse_args()
members={}
if a.base:
    base=verify(a.base)
    if base.core_id != a.id:
        p.error('--base core identity does not match --id')
    manifest=copy.deepcopy(base.manifest)
    with zipfile.ZipFile(a.base) as archive:
        for asset in manifest.get('assets',[]):
            members[asset['file']]=archive.read(asset['file'])
else:
    manifest={'format':'kria-mister-core','version':2,'id':a.id,
              'part':'xck26-sfvc784-2LV-c','abi':ABI,
              'memory_size':MEMORY_SIZE,'display':'1920x1080p60','assets':[]}
for key,path,name in [('bitstream',a.firmware,'firmware.bit.bin'),('overlay',a.overlay,'overlay.dtbo')]:
    data=path.read_bytes(); members[name]=data
    manifest[key]={'file':name,'sha256':hashlib.sha256(data).hexdigest()}
for item in a.asset:
    name,path=item.split('=',1)
    data=Path(path).read_bytes(); entry='assets/'+name
    if entry in members: p.error('duplicate asset name')
    members[entry]=data
    manifest.setdefault('assets',[]).append(
        {'name':name,'file':entry,'sha256':hashlib.sha256(data).hexdigest()})
write_package(a.output,manifest,members)
verify(a.output)
print('Verified standalone core:',a.output)
