#!/bin/zsh
# Builds Words for release and packs it into a disk image.
#
#   Scripts/make-dmg.sh
#
# The result is dist/Words-<version>.dmg, which is what goes on a release page.
# Apple silicon only: the companion runs through MLX, whose kernels are Metal on
# Apple GPUs, so an Intel slice would be a slice that cannot do half the app.
#
# The image is signed ad-hoc, because signing it properly needs a paid Apple
# Developer certificate. Gatekeeper will therefore refuse the first launch on
# anybody else's Mac, and README says how to get past it.
set -e
cd "$(dirname "$0")/.."

xcodebuild -project Words.xcodeproj -scheme Words -configuration Release \
  -derivedDataPath build -skipPackagePluginValidation -skipMacroValidation \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build

APP="build/Build/Products/Release/Words.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/Words-$VERSION.dmg"

# A folder holding the app and a shortcut to drag it into; nothing else is on
# the image, so there is nothing to explain.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
hdiutil create -volname "Words $VERSION" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

echo "$DMG — $(du -h "$DMG" | cut -f1)"
