#!/usr/bin/env python3
"""Record hashes only after real routed timing and bitstream generation pass."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import subprocess

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('routed_timing', root/'scripts/check-routed-timing.py')
timing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(timing)
core, directory, reviewed = sys.argv[1:4]
vivado_version = sys.argv[4] if len(sys.argv) > 4 else '2023.2'
if core not in ('menu', 'nes', 'snes', 'gb', 'gba', 'psx', 'n64', 'md'):
    raise ValueError('Unexpected core')
directory, reviewed = Path(directory), Path(reviewed)
snapshot = directory.parent/'source-snapshot.json'
subprocess.run([sys.executable, '-E', str(root/'scripts/snapshot-hdl.py'), '--check',
                core, str(directory.parent), str(snapshot)], check=True)
(directory/'source-snapshot.json').write_bytes(snapshot.read_bytes())

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

files = [f'{core}.bit', f'{core}.bit.bin', 'source-snapshot.json', 'routed.dcp', 'timing_routed.rpt',
         'route_status.rpt', 'utilization_routed.rpt', 'clock_utilization.rpt',
         'cdc_routed.rpt', 'exception_coverage.rpt', 'ignored_exceptions.rpt',
         'bus_skew.rpt', 'methodology_routed.rpt', 'drc_routed.rpt']
if core in ('gb','gba'):
    boot_report=directory.parent/(core+'_boot_init.tsv')
    subprocess.run([sys.executable,'-E',str(root/('scripts/check-'+core+'-boot-init.py')),str(boot_report)],check=True)
    for name in (core+'_boot_init.tsv',core+'_boot_init.json'):
        (directory/name).write_bytes((directory.parent/name).read_bytes())
        files.append(name)
if core=='gba':
    subprocess.run([sys.executable,'-E',str(root/'scripts/check-gba-ram-modes.py'),str(directory.parent/'gba_ram_modes.tsv')],check=True)
    for name in ('gba_ram_modes.tsv','gba_ram_modes.json'):
        (directory/name).write_bytes((directory.parent/name).read_bytes())
        files.append(name)
if core=='psx':
    subprocess.run([sys.executable,'-E',str(root/'scripts/check-psx-ram-modes.py'),str(directory.parent/'psx_ram_modes.tsv')],check=True)
    for name in ('psx_ram_modes.tsv','psx_ram_modes.json'):
        (directory/name).write_bytes((directory.parent/name).read_bytes())
        files.append(name)
if core in ('n64','md'):
    ram_report=directory.parent/(core+'_ram_modes.tsv')
    if not ram_report.is_file() or not ram_report.stat().st_size:
        raise ValueError('Missing inferred RAM primitive audit')
    (directory/(core+'_ram_modes.tsv')).write_bytes(ram_report.read_bytes())
    files.append(core+'_ram_modes.tsv')
for name in files:
    if not (directory/name).is_file() or not (directory/name).stat().st_size:
        raise ValueError('Missing implementation artifact: '+name)
record = {'part': 'xck26-sfvc784-2LV-c', 'stage': 'route_design',
          'core': core, 'vivado': vivado_version,
          'timing': timing.check(directory/'timing_routed.rpt'),
          'artifacts': {name: digest(directory/name) for name in files},
          'reviewed_synthesis_sha256': digest(reviewed),
          'constraints_sha256': digest(root/'hardware/kv260/cdc-mailboxes.tcl'),
          'sources_lock_sha256': digest(root/('sources-md.lock.json' if core=='md' else 'sources-n64.lock.json' if core=='n64' else 'sources-psx.lock.json' if core=='psx' else 'sources-gba.lock.json' if core=='gba' else 'sources-gb.lock.json' if core=='gb' else 'sources-snes.lock.json' if core=='snes' else 'sources.lock.json'))}
if core=='snes':
    record['snes_constraints_sha256']={name:digest(root/'hardware/kv260'/name) for name in ('snes-clocks.tcl','snes-cdc.tcl')}
if core=='psx':
    record['psx_constraints_sha256']={name:digest(root/'hardware/kv260'/name) for name in ('psx-clocks.tcl','psx-cdc.tcl')}
if core=='n64':
    record['n64_constraints_sha256'] = digest(root/'hardware/kv260/n64-cdc.tcl')
(directory/'implementation.json').write_text(json.dumps(record, indent=2)+'\n')
print('Recorded routed implementation and artifact hashes:', directory/'implementation.json')
