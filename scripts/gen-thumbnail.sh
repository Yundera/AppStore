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
CH=${#TITLE}
if   [ "$CH" -gt 22 ]; then TPS=27
elif [ "$CH" -gt 13 ]; then TPS=33
else TPS=40; fi
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
