#!/usr/bin/env python3
"""Keep docker exec alive until all descendants of a build have finished."""
import ctypes
import os
import signal
import subprocess
import sys

if len(sys.argv) < 2:
    sys.exit('Usage: container-build.py command [args...]')

# Vivado launch_runs starts a run manager that survives a crashing GUI/Tcl
# process. Adopt those descendants so the host lock outlives the whole build.
libc = ctypes.CDLL(None, use_errno=True)
libc.prctl.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong,
                      ctypes.c_ulong, ctypes.c_ulong]
libc.prctl.restype = ctypes.c_int
if libc.prctl(36, 1, 0, 0, 0):  # PR_SET_CHILD_SUBREAPER
    raise OSError(ctypes.get_errno(), 'Cannot adopt container build descendants')

def interrupted(signum, frame):
    print('Waiting for container build children; cancel their processes explicitly.',
          file=sys.stderr, flush=True)

signal.signal(signal.SIGINT, interrupted)
signal.signal(signal.SIGTERM, interrupted)
primary = subprocess.Popen(sys.argv[1:])
result = None
descendant_result = 0
announced = False
while True:
    try:
        # Reap adopted helpers even while the primary command is alive. Vivado
        # waits for some detached helper PIDs to disappear before returning
        # from synth_design; keeping their zombies until primary.wait() returns
        # deadlocks both processes.
        if result is not None:
            pid, status = os.waitpid(-1, os.WNOHANG)
            if not pid and not announced:
                print('Waiting for remaining container build children.', flush=True)
                announced = True
        else:
            pid = 0
        if not pid:
            pid, status = os.waitpid(-1, 0)
    except ChildProcessError:
        break
    # Quartus 17's existing image has Python 3.4, before waitstatus_to_exitcode.
    if os.WIFEXITED(status):
        child_result = os.WEXITSTATUS(status)
    elif os.WIFSIGNALED(status):
        child_result = -os.WTERMSIG(status)
    else:
        raise RuntimeError('Unexpected child wait status: %s' % status)
    if pid == primary.pid:
        primary.returncode = child_result
        result = child_result
    elif descendant_result == 0 and child_result != 0:
        descendant_result = child_result
if result is None:
    raise RuntimeError('Primary build exit status was not collected')
if result == 0:
    result = descendant_result
sys.exit(128 - result if result < 0 else result)
