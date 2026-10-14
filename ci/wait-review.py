#!/usr/bin/env python3
import hashlib,json,time,urllib.request,urllib.error
from pathlib import Path
r=Path('/work');identity=json.loads((r/'ci-output/review-identity.json').read_text())
checkpoint=identity['reviewed_checkpoint_sha256']
assert len(checkpoint)==64 and all(c in '0123456789abcdef' for c in checkpoint)
url='https://raw.githubusercontent.com/jiang-dongwei/KV260-MD/main/ci/reviews/'+checkpoint+'.json'
deadline=time.monotonic()+5400
print('Waiting for technical review of exact checkpoint '+checkpoint,flush=True)
while time.monotonic()<deadline:
 try:
  with urllib.request.urlopen(url,timeout=20) as response:record=json.load(response)
  assert record.get('accepted') is True
  for key in ('source_commit','reviewed_checkpoint_sha256','source_fingerprint_sha256','constraints_sha256'):
   assert record[key]==identity[key],key
  (r/'ci-output/cdc-accepted.json').write_text(json.dumps(record,indent=2)+'\n')
  print('Exact CDC review accepted; routing permitted',flush=True)
  break
 except urllib.error.HTTPError as e:
  if e.code!=404:print('Review fetch HTTP '+str(e.code),flush=True)
 except urllib.error.URLError:pass
 time.sleep(30)
else:raise RuntimeError('Exact checkpoint review not received before deadline')
