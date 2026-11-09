#!/bin/sh
# Build dist/glucoid-<version>.plasmoid (a KPackage file) for the KDE Store
# or for installing by hand.
#
#   tools/make-package.sh
#
# The package contains metadata.json, contents/**, README.md and LICENSE.
set -eu

project=$(cd "$(dirname "$0")/.." && pwd)
package="$project/plasmoid/fi.reijo.glucoid"

[ -f "$package/metadata.json" ] || {
    echo "error: $package/metadata.json not found" >&2
    exit 1
}
command -v zip >/dev/null || {
    echo "error: zip is not installed" >&2
    exit 1
}

# Native module and QML must be updated together; never ship a stale binary.
python3 "$project/native/stage.py" --project "$project" --verify

version=$(python3 -c "import json;print(json.load(open('$package/metadata.json'))['KPlugin']['Version'])")
dist="$project/dist"
out="$dist/glucoid-$version.plasmoid"
mkdir -p "$dist"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT INT TERM
# cp -a everywhere: the file timestamps end up in the zip, so keeping the
# source timestamps makes the package byte-for-byte reproducible.
cp -a "$package/." "$stage/"
cp -a "$project/packaging/README.md" "$stage/README.md"
cp -a "$project/packaging/LICENSE" "$stage/LICENSE"
cp -a "$project/packaging/THIRD_PARTY_NOTICES.md" "$stage/THIRD_PARTY_NOTICES.md"
cp -a "$project/packaging/licenses" "$stage/licenses"
# Remove debug-only local build paths; executable code stays unchanged.
strip --strip-debug "$stage/contents/ui/native/libglucoidnetwork.so"
python3 "$project/tools/finalize-package.py" "$stage"

rm -f "$out"
python3 - "$stage" "$out" <<'PYZIP'
from pathlib import Path
import sys,zipfile
root=Path(sys.argv[1])
with zipfile.ZipFile(sys.argv[2], 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(root.rglob('*')):
        if path.is_file(): archive.write(path, path.relative_to(root).as_posix())
PYZIP

echo "built: $out ($(du -h "$out" | cut -f1))"
echo "contents:"
unzip -l "$out" | sed -n '4,12p'
