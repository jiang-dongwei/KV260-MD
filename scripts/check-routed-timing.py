#!/usr/bin/env python3
"""Reject failed or unreviewed routed timing."""
from pathlib import Path
import re
import sys


def check_bus_skew(path):
    report = Path(path).read_text()
    if re.search(r'^No bus skew constraints$', report, re.M):
        return
    sections = re.split(r'^Id: \d+\s*$', report, flags=re.M)[1:]
    if not sections:
        raise ValueError('Missing bus-skew constraint results')
    for section in sections:
        slacks = re.findall(r'^Slack \((MET|VIOLATED)\)\s*:\s*([-+\d.]+)ns',
                            section, re.M)
        if not slacks or any(state != 'MET' or float(value) < 0 for state, value in slacks):
            raise ValueError('Failed or missing routed bus-skew timing')


def check_timing_section(report, name):
    match = re.search(r'^\d+\. checking ' + re.escape(name) +
                      r' \((\d+)\)\n-+\n(.*?)(?=^\d+\. checking|\Z)',
                      report, re.M | re.S)
    if match is None:
        raise ValueError(f'Missing detailed timing check: {name}')
    pins = re.findall(r'^(kria_platform_i/\S+)$', match[2], re.M)
    count = int(match[1])
    if count != len(pins):
        raise ValueError(f'Unknown {name} report format')
    return pins


def check(path):
    report = Path(path).read_text()
    section = report.split('| Design Timing Summary\n', 1)[1]
    lines = section.splitlines()
    header = next(i for i, line in enumerate(lines) if line.strip().startswith('WNS(ns)'))
    values = lines[header + 2].split()
    if len(values) != 12:
        raise ValueError('Unknown Vivado timing summary format')
    for index, name in [(2, 'setup'), (6, 'hold'), (10, 'pulse width')]:
        if int(values[index]) != 0 or float(values[index - 2]) < 0:
            raise ValueError(f'Failed routed {name} timing')
    for name in ('no_input_delay', 'no_output_delay', 'multiple_clock',
                 'generated_clocks', 'loops', 'partial_input_delay',
                 'partial_output_delay', 'latch_loops'):
        matches = re.findall(r'checking ' + name + r' \((\d+)\)', report)
        if not matches or any(int(value) for value in matches):
            raise ValueError(f'Unresolved timing check: {name}')

    # The PS8 exposes unused EMIO clock outputs. N64 also deliberately uses
    # asynchronous sticky latches for its debug-only error overlay so an error
    # pulse from any core domain cannot be missed. Accept only these exact
    # structures, and require every unclocked latch G pin to have the matching
    # unconstrained PRE endpoint. Any other endpoint still fails closed.
    no_clock_pins = check_timing_section(report, 'no_clock')
    unconstrained_pins = check_timing_section(
        report, 'unconstrained_internal_endpoints')
    allowed = {'EMIOENET0MDIOMDC', 'EMIOENET1MDIOMDC', 'EMIOENET2MDIOMDC',
               'EMIOENET3MDIOMDC', 'EMIOSDIO0CLKOUT', 'EMIOSDIO1CLKOUT',
               'EMIOSPI0SCLKO', 'EMIOSPI1SCLKO'}
    ps_prefix = 'kria_platform_i/ps/inst/PS8_i/'
    ps_pins = [pin[len(ps_prefix):] for pin in no_clock_pins
               if pin.startswith(ps_prefix)]
    if not set(ps_pins) <= allowed:
        raise ValueError('Unreviewed endpoints without a clock')
    latch_re = re.compile(
        r'kria_platform_i/app/inst/impl/core/n64top/'
        r'errorCode_reg\[(\d+)\]/G$')
    latch_bits = [int(match[1]) for pin in no_clock_pins
                  if (match := latch_re.fullmatch(pin))]
    accepted_no_clock = len(ps_pins) + len(latch_bits)
    if accepted_no_clock != len(no_clock_pins) or not set(latch_bits) <= set(range(29)):
        raise ValueError('Unreviewed endpoints without a clock')
    unconstrained_re = re.compile(
        r'kria_platform_i/app/inst/impl/core/n64top/'
        r'errorCode_reg\[(\d+)\]/PRE$')
    unconstrained_bits = [int(match[1]) for pin in unconstrained_pins
                          if (match := unconstrained_re.fullmatch(pin))]
    if (len(unconstrained_bits) != len(unconstrained_pins) or
            set(unconstrained_bits) != set(latch_bits)):
        raise ValueError('Unreviewed unconstrained internal endpoints')
    check_bus_skew(Path(path).with_name('bus_skew.rpt'))
    return {'wns_ns': float(values[0]), 'whs_ns': float(values[4]),
            'wpws_ns': float(values[8]), 'setup_failures': 0, 'hold_failures': 0,
            'pulse_width_failures': 0, 'unused_ps_emio_clock_pins': ps_pins,
            'intentional_n64_error_latches': sorted(set(latch_bits))}


if __name__ == '__main__':
    print(check(sys.argv[1]))
