#!/usr/bin/env bash
set -euo pipefail

# Rebuilds the release-ready 1x/2x PNG previews and the multi-resolution TIFF
# consumed by create-dmg. This is a design-time tool; release builds only need
# packaging/dmg/background.tiff.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_DIR="$ROOT_DIR/packaging/dmg"
SOURCE="$ASSET_DIR/attic-source.png"
FONT="/System/Library/Fonts/Avenir Next.ttc"

command -v magick >/dev/null 2>&1 || {
  echo "ImageMagick is required. Install it with: brew install imagemagick" >&2
  exit 1
}
command -v tiffutil >/dev/null 2>&1 || {
  echo "tiffutil is required and ships with macOS." >&2
  exit 1
}
[ -f "$SOURCE" ] || { echo "Missing source artwork: $SOURCE" >&2; exit 1; }
[ -f "$FONT" ] || { echo "Missing system font: $FONT" >&2; exit 1; }

OUT_1X="$ASSET_DIR/background.png"
OUT_2X="$ASSET_DIR/background@2x.png"
TIFF_1X="$ASSET_DIR/.background-1x.tiff"
TIFF_2X="$ASSET_DIR/.background-2x.tiff"

magick "$SOURCE" \
  -resize '1320x840^' -gravity center -extent 1320x800 \
  \( +clone -fill '#171411' -colorize 14 \) -compose over -composite \
  \( -size 1320x370 gradient:'#00000000-#D8BD91B8' \) \
  -gravity south -geometry +0+0 -compose over -composite \
  \( -size 1320x800 xc:none -stroke '#FFB54788' -strokewidth 24 -fill none \
     -draw "path 'M 520,434 L 800,434 M 756,390 L 800,434 L 756,478'" -blur 0x18 \) \
  -compose over -composite \
  -stroke '#FFB547' -strokewidth 8 -fill none \
  -draw "path 'M 520,434 L 800,434 M 756,390 L 800,434 L 756,478'" \
  -font "$FONT" -pointsize 30 -fill '#F6EFE3' -stroke none -gravity north \
  -annotate +0+286 'ARRASTRA PARA INSTALAR  ·  DRAG TO INSTALL' \
  -strip -colorspace sRGB -quality 92 "$OUT_2X"

magick "$OUT_2X" -filter Lanczos -resize 660x400 \
  -units PixelsPerInch -density 72 -strip "$OUT_1X"
magick "$OUT_1X" -units PixelsPerInch -density 72 -compress LZW "$TIFF_1X"
magick "$OUT_2X" -units PixelsPerInch -density 144 -compress LZW "$TIFF_2X"
tiffutil -cathidpicheck "$TIFF_1X" "$TIFF_2X" -out "$ASSET_DIR/background.tiff"
rm "$TIFF_1X" "$TIFF_2X"

echo "Rendered DMG artwork:"
echo "  $OUT_1X"
echo "  $OUT_2X"
echo "  $ASSET_DIR/background.tiff"
