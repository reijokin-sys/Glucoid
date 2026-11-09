#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Finalize generated package after stripping debug metadata; verify licenses."""
import hashlib,json,sys,os
from pathlib import Path
root=Path(sys.argv[1]);native=root/'contents/ui/native';manifest=native/'build-manifest.json'
d=json.loads(manifest.read_text());d['library_sha256']=hashlib.sha256((native/'libglucoidnetwork.so').read_bytes()).hexdigest();d['debug_symbols']='removed for distribution';manifest.write_text(json.dumps(d,indent=2)+'\n')
for path in ['LICENSE','THIRD_PARTY_NOTICES.md','licenses/LGPL-3.0.txt','licenses/curl.txt']:
 if not (root/path).is_file() or (root/path).stat().st_size<100:raise SystemExit('Required license/notice missing: '+path)

# Stable ZIP timestamps, independent of private/public checkout times.
for p in root.rglob('*'):os.utime(p,(1767225600,1767225600))
