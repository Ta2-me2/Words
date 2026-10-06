#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-release}"
swift build -c "$configuration" --product WortfallDemo
bin_dir="$(swift build -c "$configuration" --show-bin-path)"
app_dir="$PWD/Build/WordFall.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/WortfallDemo" "$app_dir/Contents/MacOS/WortfallDemo"
# Keep resource bundles inside the standard, code-signable Resources directory.
if [[ -d "$app_dir/WortfallKit_WortfallKit.bundle" ]]; then
    rm -rf "$app_dir/WortfallKit_WortfallKit.bundle"
fi
ditto "$bin_dir/WortfallKit_WortfallKit.bundle" "$app_dir/Contents/Resources/WortfallKit_WortfallKit.bundle"
xcrun swift Scripts/make-icon.swift "$PWD/Assets/IconWordFall.png" "$PWD/Build/WordFall.iconset"
iconutil -c icns "$PWD/Build/WordFall.iconset" -o "$app_dir/Contents/Resources/WordFall.icns"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>WortfallDemo</string>
<key>CFBundleIdentifier</key><string>studio.wortfall.demo</string>
<key>CFBundleIconFile</key><string>WordFall</string>
<key>CFBundleName</key><string>WordFall</string>
<key>CFBundleDisplayName</key><string>WordFall</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.2.2</string>
<key>CFBundleVersion</key><string>9</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
print "Built: $app_dir"
