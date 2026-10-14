#!/usr/bin/env python3
"""Run on the KV260: read only the frame-held MD diagnostic status at 0x34."""
import argparse,collections,ctypes,json,mmap,os,re,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--expected-sha256',required=True);args=p.parse_args()
assert re.fullmatch('[0-9a-f]{64}',args.expected_sha256)
assert os.uname().machine=='aarch64'
active_path=Path('/run/kria-mister/active.json')
active=active_path.read_text();info=json.loads(active)
assert info['id']=='Genesis' and info['manifest_sha256']==args.expected_sha256
uios=[p for p in Path('/sys/class/uio').glob('uio*') if (p/'name').read_text().strip()=='kria-mister'];assert len(uios)==1
assert int((uios[0]/'maps/map0/size').read_text(),0)>=0x38
fd=os.open('/dev/'+uios[0].name,os.O_RDONLY)
libc=ctypes.CDLL(None,use_errno=True)
libc.mmap.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_long]
libc.mmap.restype=ctypes.c_void_p
libc.munmap.argtypes=[ctypes.c_void_p,ctypes.c_size_t]
address=libc.mmap(None,mmap.PAGESIZE,mmap.PROT_READ,mmap.MAP_SHARED,fd,0)
assert address!=ctypes.c_void_p(-1).value,os.strerror(ctypes.get_errno())
values=[]
try:
    # This register returns debug_sync; no read-clear, ack or snapshot side effect.
    register=ctypes.c_uint32.from_address(address+0x34)
    for i in range(60):
        assert active_path.read_text()==active
        values.append(register.value);time.sleep(0.025)
finally:
    libc.munmap(address,mmap.PAGESIZE);os.close(fd)
assert active_path.read_text()==active
result={'active':info,'register_offset':'0x34','values':[],'stable_by_stage':{}}
for value,count in collections.Counter(values).most_common():
    signature=value>>28
    stage={12:'native',13:'post_cofi',14:'native_frame',15:'post_cofi_frame'}.get(signature,'unknown')
    item={'word':f'{value:08x}','samples':count,'valid_signature':signature in (12,13,14,15),'stage':stage}
    if signature in (14,15):
        item.update(width=(value>>18)&1023,complete_lines=(value>>9)&511,
            incorrect_lines=value&511,pattern='literal red-left/green-right diagnostic only')
    else:
        item.update(native_width=(value>>18)&1023,post_cofi_width=(value>>8)&1023,
            colors_x32_96_160_224=[(value>>(2*i))&3 for i in range(4)])
    result['values'].append(item)
for stage in ('native','post_cofi','native_frame','post_cofi_frame'):
    observations=[v for v in result['values'] if v['stage']==stage]
    result['stable_by_stage'][stage]=bool(observations and observations[0]['samples']>=3 and len(observations)==1)
print(json.dumps(result,indent=2))
