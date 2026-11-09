#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build-internal staging and stale-native-component verification."""
import argparse,hashlib,json,platform,shutil
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--project',type=Path,required=True);parser.add_argument('--library',type=Path);parser.add_argument('--verify',action='store_true');parser.add_argument('--qt-version',default='');parser.add_argument('--curl-version',default='');args=parser.parse_args()
root=args.project.resolve();target=root/'plasmoid/fi.reijo.glucoid/contents/ui/native';library=target/'libglucoidnetwork.so';manifest=target/'build-manifest.json'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
sources=[root/'CMakeLists.txt']+sorted((root/'native').glob('*.cpp'))+sorted((root/'native').glob('*.h'))+[root/'native/stage.py']
expected={str(p.relative_to(root)):digest(p) for p in sources};version=json.loads((root/'plasmoid/fi.reijo.glucoid/metadata.json').read_text())['KPlugin']['Version']
if args.verify:
 try:d=json.loads(manifest.read_text());ok=d['version']==version and d['sources']==expected and d['library_sha256']==digest(library)
 except (OSError,KeyError,ValueError):ok=False
 if not ok:raise SystemExit('Native backend is missing or stale. Build the current source with CMake before packaging/installing.')
 print('Native backend matches the current widget source and version.')
else:
 if args.library is None:parser.error('--library is required when staging')
 target.mkdir(parents=True,exist_ok=True)
 if library.exists() and digest(library)!=digest(args.library):
  history=root/'docs/artifacts/native-library-history'/digest(library);history.mkdir(parents=True,exist_ok=True)
  if not (history/library.name).exists():shutil.copy2(library,history/library.name)
 if not library.exists() or digest(library)!=digest(args.library):
  temporary=library.with_name(library.name+'.new');shutil.copy2(args.library,temporary);temporary.replace(library)
 d={'version':version,'architecture':platform.machine(),'qt_version':args.qt_version,'libcurl_version':args.curl_version,'library_sha256':digest(library),'sources':expected}
 manifest.write_text(json.dumps(d,indent=2)+'\n');print('Staged the verified native widget component.')
