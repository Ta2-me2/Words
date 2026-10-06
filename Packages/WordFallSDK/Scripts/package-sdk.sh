#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./Scripts/build-app.sh release
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/wortfall-sdk.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
package_dir="$stage_dir/WordFallSDK-2.2.2"
mkdir -p "$package_dir/Demo"
for folder in Sources Tests Documentation Scripts Assets; do
    ditto "$folder" "$package_dir/$folder"
done
cp Package.swift README.md .gitignore "$package_dir/"
ditto Build/WordFall.app "$package_dir/Demo/WordFall.app"
codesign --verify --deep --strict "$package_dir/Demo/WordFall.app"
python3 - "$package_dir" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
lines = []
for path in sorted(root.rglob('*')):
    if path.is_file():
        lines.append(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.relative_to(root).as_posix())
(root / 'SHA256SUMS.txt').write_text('\n'.join(lines) + '\n')
PY
ditto -c -k --sequesterRsrc --keepParent "$package_dir" Build/WordFallSDK-2.2.2.zip
print "SDK archive: $PWD/Build/WordFallSDK-2.2.2.zip"
