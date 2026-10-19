#!/bin/zsh
# Takes one window shot for the README.
#
#   Scripts/screenshot.sh home
#
# Click the Words window when the cursor turns into a camera. The picture
# lands in docs/screenshots/<name>.png, shadow and all, scaled to the width
# the README asks for. docs/screenshots/README.md says what each name holds.
set -e
cd "$(dirname "$0")/.."

[[ $# -eq 1 ]] || { print -u2 "usage: Scripts/screenshot.sh <name>"; exit 1 }

OUT="docs/screenshots/$1.png"
print "Click the window to capture…"
screencapture -w "$OUT"
sips -Z 1800 "$OUT" > /dev/null
print "$OUT — $(sips -g pixelWidth -g pixelHeight "$OUT" | awk '/pixel/ {printf "%s ", $2}')"
