#!/bin/bash
# Generate a 784x442 store tile in the psd-source/thumbnail_template.psd house style:
# dark horizontal gradient, rounded corners, icon + title + tagline left, screenshot right.
set -e
APP="$1"; SRC="/d/workspace/yundera/YunderaAppStore/Apps/$APP"; OUT="$2"
W=784; H=442; R=26
TITLE=$(yq -r '.["x-casaos"].title.en_us // ""' "$SRC/docker-compose.yml")
[ -z "$TITLE" ] && TITLE="$APP"
TAG=$(yq -r '.["x-casaos"].tagline.en_us // ""' "$SRC/docker-compose.yml")
F=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
FB=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
T=$(mktemp -d)

# 1. gradient base, matching the template's sampled colours
convert -size ${W}x${H} gradient:'#30333B'-'#1F2227' -rotate 90 -resize ${W}x${H}! "$T/bg.png"

# 2. right-hand panel: the app's own screenshot, rounded, inset (icon watermark if none)
if [ -f "$SRC/screenshot-1.png" ]; then
  convert "$SRC/screenshot-1.png" -resize 430x300^ -gravity center -extent 430x300 "$T/shot.png"
  convert -size 430x300 xc:black -fill white -draw "roundrectangle 0,0,429,299,14,14" "$T/m.png"
  convert "$T/shot.png" "$T/m.png" -alpha off -compose CopyOpacity -composite "$T/panel.png"
  composite -gravity east -geometry +34+0 "$T/panel.png" "$T/bg.png" "$T/bg2.png"
else
  convert "$SRC/icon.png" -resize 260x260 -alpha set -channel A -evaluate multiply 0.13 +channel "$T/wm.png"
  composite -gravity east -geometry +60+0 "$T/wm.png" "$T/bg.png" "$T/bg2.png"
fi

# 3. left column: icon / title / tagline stacked vertically, then centred as one
#    block. Stacking rather than fixed offsets is what keeps a two-line title
#    (DocmostMCP, "TINC - Settlers of Catan") from landing on top of the tagline.
# Pick the largest size at which the LONGEST WORD still fits the 258px column.
# A pure character count cannot see this: "Docusaurus" is only 10 chars but is
# 297px wide at 40pt, so caption: broke it mid-word into "Docusauru / s".
# Measuring instead means multi-word titles still wrap at their spaces (which
# looks fine - "Stirling PDF", "TINC - Settlers of Catan") while a single long
# word steps down a size rather than being cut in half.
LONGEST=$(printf '%s\n' $TITLE | awk '{ if (length($0) > length(m)) m = $0 } END { print m }')
# Two constraints, both needed: the longest word must fit the column width (or
# it is split mid-word), AND the wrapped block must stay within ~2 lines (or a
# long multi-word title like "TINC - Settlers of Catan" grows to four lines and
# collides with the tagline).
for TPS in 40 33 27 22; do
  WW=$(convert -background none -font "$FB" -pointsize $TPS label:"$LONGEST" -format '%w' info: 2>/dev/null || echo 999)
  TH=$(convert -background none -font "$FB" -pointsize $TPS -size 258x caption:"$TITLE" -format '%h' info: 2>/dev/null || echo 999)
  [ "$WW" -le 258 ] && [ "$TH" -le 100 ] && break
done
convert "$SRC/icon.png" -resize 72x72 -background none -gravity west -extent 258x72 "$T/ico.png"
convert -background none -fill '#FFFFFF' -font "$FB" -pointsize $TPS -size 258x caption:"$TITLE" \
        -background none -gravity west -extent 258x "$T/title.png"
convert -background none -fill '#AEB4BF' -font "$F" -pointsize 18 -interline-spacing 5 -size 258x caption:"$TAG" \
        -background none -gravity west -extent 258x "$T/tag.png"
convert -background none -size 258x18 xc:none "$T/gap1.png"
convert -background none -size 258x12 xc:none "$T/gap2.png"
convert "$T/ico.png" "$T/gap1.png" "$T/title.png" "$T/gap2.png" "$T/tag.png" \
        -background none -append "$T/col.png"
composite -gravity west -geometry +44+0 "$T/col.png" "$T/bg2.png" "$T/bg5.png"

# 4. rounded-corner mask, per the spec ("784x442 with rounded corner mask")
convert -size ${W}x${H} xc:black -fill white -draw "roundrectangle 0,0,$((W-1)),$((H-1)),$R,$R" "$T/mask.png"
convert "$T/bg5.png" "$T/mask.png" -alpha off -compose CopyOpacity -composite "$OUT"
rm -rf "$T"
