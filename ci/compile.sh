#!/usr/bin/env bash
set -euo pipefail
exec flock /tmp/kria-mister-handoff-build.lock /work/scripts/container-build.py "$@"
