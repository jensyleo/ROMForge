#!/bin/bash
#
# make-appicon.sh — build the macOS AppIcon.appiconset from a 1024×1024 PNG.
# ROMForge — Copyright (C) 2026 Jensy Leonardo Martínez Cruz — GNU GPL v3.0
#
# Usage: Scripts/make-appicon.sh <source-1024.png>

set -euo pipefail
SRC="${1:?usage: make-appicon.sh <source-1024.png>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SET="$HERE/App/Resources/Assets.xcassets/AppIcon.appiconset"

mkdir -p "$SET"

# size@scale -> filename
gen() { sips -z "$1" "$1" "$SRC" --out "$SET/$2" >/dev/null; }

gen 16   icon_16.png
gen 32   icon_16@2x.png
gen 32   icon_32.png
gen 64   icon_32@2x.png
gen 128  icon_128.png
gen 256  icon_128@2x.png
gen 256  icon_256.png
gen 512  icon_256@2x.png
gen 512  icon_512.png
gen 1024 icon_512@2x.png

cat > "$SET/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom":"mac", "size":"16x16",   "scale":"1x", "filename":"icon_16.png" },
    { "idiom":"mac", "size":"16x16",   "scale":"2x", "filename":"icon_16@2x.png" },
    { "idiom":"mac", "size":"32x32",   "scale":"1x", "filename":"icon_32.png" },
    { "idiom":"mac", "size":"32x32",   "scale":"2x", "filename":"icon_32@2x.png" },
    { "idiom":"mac", "size":"128x128", "scale":"1x", "filename":"icon_128.png" },
    { "idiom":"mac", "size":"128x128", "scale":"2x", "filename":"icon_128@2x.png" },
    { "idiom":"mac", "size":"256x256", "scale":"1x", "filename":"icon_256.png" },
    { "idiom":"mac", "size":"256x256", "scale":"2x", "filename":"icon_256@2x.png" },
    { "idiom":"mac", "size":"512x512", "scale":"1x", "filename":"icon_512.png" },
    { "idiom":"mac", "size":"512x512", "scale":"2x", "filename":"icon_512@2x.png" }
  ],
  "info" : { "author":"xcode", "version":1 }
}
JSON

echo "AppIcon.appiconset generated at: $SET"
