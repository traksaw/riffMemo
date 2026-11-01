#!/usr/bin/env bash
# Renders the three app icon SVGs into the AppIcon asset set (WAS-111).
# Needs ImageMagick 7: brew install imagemagick
# Usage: docs/design/app-icon/render.sh   (from any directory)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$here/../../../RiffMemo/RiffMemo/App/Assets.xcassets/AppIcon.appiconset"

# MSVG: forces ImageMagick's built-in renderer, so no extra SVG library is needed.
render() { magick -background none -density 1024 "MSVG:$here/$1.svg" -resize 1024x1024! "${@:3}" "$out/$2"; }

# Default must have no alpha channel, or App Store Connect rejects the upload.
render default AppIcon-1024.png        -background '#0E0E11' -flatten -alpha off -define png:color-type=2
render dark    AppIcon-1024-dark.png
render tinted  AppIcon-1024-tinted.png -colorspace Gray -define png:color-type=4

for f in AppIcon-1024.png AppIcon-1024-dark.png AppIcon-1024-tinted.png; do
  echo "$f: $(magick identify -format '%wx%h alpha=%A' "$out/$f")"
done
