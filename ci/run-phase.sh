#!/usr/bin/env bash
set -euo pipefail
/work/ci/compile.sh /work/scripts/vivado.sh -mode batch -source /work/hardware/kv260/preflight-k26.tcl
/work/ci/compile.sh /work/scripts/vivado.sh -mode batch -source /work/ci/license-smoke.tcl
if [[ "$BUILD_PHASE" == synth-review ]]; then
  /work/ci/compile.sh /work/scripts/vivado.sh -mode batch -source /work/hardware/kv260/build.tcl -tclargs md
  /work/ci/compile.sh /work/scripts/vivado.sh -mode batch -source /work/hardware/kv260/review-cdc.tcl -tclargs md
  cp -a /build/kria-mister-md-vivado/cdc-review /work/ci-output/
  cp /build/kria-mister-md-vivado/source-snapshot.json /work/ci-output/
  python3 - <<'REPORT'
import hashlib,json,os
from pathlib import Path
r=Path('/work');p=r/'ci-output'
digest=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
identity={'core':'md','vivado':'2026.1','source_commit':os.environ.get('GITHUB_SHA'),
'reviewed_checkpoint_sha256':digest(p/'cdc-review/constrained_synth.dcp'),
'source_fingerprint_sha256':digest(p/'source-snapshot.json'),
'constraints_sha256':digest(r/'hardware/kv260/cdc-mailboxes.tcl'),
'status':'technical CDC review required before routing'}
(p/'review-identity.json').write_text(json.dumps(identity,indent=2)+'\n')
print(json.dumps(identity))
REPORT
fi
