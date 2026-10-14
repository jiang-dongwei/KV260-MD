#!/usr/bin/env python3
"""Fingerprint prepared HDL before synthesis; reject changed inputs at routing."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
checking = sys.argv[1] == '--check'
args = sys.argv[2:] if checking else sys.argv[1:]
core, project, destination = args
if core not in ('menu', 'nes', 'snes', 'gb', 'gba', 'psx', 'n64', 'md'):
    raise ValueError('Unexpected core')
project, destination = Path(project), Path(destination)
suffixes = {'.v', '.sv', '.vh', '.svh', '.vhd', '.vhdl', '.hex', '.mif', '.mem'}
files = set()
for directory in [root/'build/hdl'/core, root/'build/hdl/scaler', root/'rtl',
                  root/'cores'/core, root/'hardware/kv260']:
    files.update(p for p in directory.rglob('*') if p.is_file() and p.suffix in suffixes)
files.update(root/p for p in ['hardware/kv260/board.xdc', 'sources.lock.json',
             'upstream/Template_MiSTeX/sys/math.sv', 'upstream/NES_MiSTer/sys/iir_filter.v',
             'z486_XL/platform/kv260/rtl/z486_dp_audio.sv',
             'z486_XL/platform/kv260/rtl/z486_rgb_to_dp36.v'])
if core in ('nes', 'snes', 'gb', 'gba', 'psx'):
    files.add(project/'km_core_clocks.v')
if core == 'md':
    files.update(root/p for p in ('sources-md.lock.json','hardware/kv260/build.tcl','build/hdl/md-sources.tcl'))
if core == 'snes':
    files.add(root/'sources-snes.lock.json')
    files.add(root/'cores/nes/km_nes_flush.sv')
if core == 'gb':
    files.add(root/'sources-gb.lock.json')
    files.add(root/'cores/nes/km_nes_flush.sv')
    files.update(root/'cores/snes'/p for p in ('km_snes_cart_front.sv','km_snes_cart_line_axi.sv'))
if core == 'gba':
    files.add(root/'sources-gba.lock.json')
    files.add(root/'cores/nes/km_nes_flush.sv')
    files.add(root/'cores/gb/km_gb_ram.sv')
if core == 'psx':
    files.add(root/'hardware/kv260/build.tcl')
    video_ip=list(project.rglob('km_psx_video_mmcm.xci'))
    if len(video_ip)!=1: raise ValueError('Expected one PSX dynamic video IP configuration')
    files.update(video_ip)
    files.update(root/p for p in ('sources-psx.lock.json','cores/nes/km_nes_flush.sv','cores/nes/km_nes_memory.sv'))
if core == 'n64':
    files.update(root/p for p in ('sources-n64.lock.json', 'hardware/kv260/build.tcl'))
    for name in ('core_clock', 'n64_video_clock', 'n64_pal_video_clock'):
        matches = list(project.rglob('*' + name + '*.xci'))
        if name == 'n64_video_clock':
            matches = [p for p in matches if 'n64_pal_video_clock' not in p.name]
        if len(matches) != 1:
            raise ValueError(f'Expected one N64 {name} IP configuration')
        files.add(matches[0])
entries = {}
for path in sorted(files):
    try:
        key = 'work/'+str(path.relative_to(root))
    except ValueError:
        key = 'project/'+str(path.relative_to(project))
    entries[key] = hashlib.sha256(path.read_bytes()).hexdigest()
record = {'core': core, 'sha256': entries}
if checking:
    if json.loads(destination.read_text()) != record:
        raise ValueError('HDL inputs changed since synthesis; rebuild before implementation')
    print('Synthesis HDL fingerprint matches current inputs')
else:
    destination.write_text(json.dumps(record, indent=2)+'\n')
    print('Recorded synthesis inputs:', len(entries), 'files')
