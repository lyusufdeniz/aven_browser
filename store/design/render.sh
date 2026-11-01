#!/bin/bash
# Renders store/design/studio.html into store/graphics with headless Chrome.
# Usage: store/design/render.sh [asset ...]       (default: every asset)
#        LANGS="de-DE fr-FR" store/design/render.sh p1 t1
set -e
cd "$(dirname "$0")"
python build_i18n.py >/dev/null
CHROME="${CHROME:-/c/Program Files/Google/Chrome/Application/chrome.exe}"
OUT=../graphics
STUDIO="file:///$(pwd -W 2>/dev/null || pwd)/studio.html"
LANGS="${LANGS:-en-US tr-TR es-ES pt-BR de-DE fr-FR it-IT ru-RU id hi-IN ar ja-JP}"
ALL="p1 p2 p3 p4 p5 p6 p7 p8 t1 t2 t3 t4 t5 fg banner icon iconLight"

jobs_file=$(mktemp)
for a in ${@:-$ALL}; do
  for l in $LANGS; do
    case $a in
      p*) echo "$a $l $OUT/phone/$l/${a#p}.png 1080 1920" ;;
      t*) echo "$a $l $OUT/tv/$l/${a#t}.png 1920 1080" ;;
      fg) echo "$a $l $OUT/feature-graphic/$l.png 1024 500" ;;
      banner) [ $l = en-US ] && echo "$a $l $OUT/tv-banner.png 1280 720" ;;
      icon) [ $l = en-US ] && echo "$a $l $OUT/icon-512.png 512 512" ;;
      iconLight) [ $l = en-US ] && echo "$a $l $OUT/icon-512-light.png 512 512" ;;
    esac
  done
done >"$jobs_file"

shot() { # asset lang out width height
  mkdir -p "$(dirname "$3")"
  local dir; dir="$(cd "$(dirname "$3")" && (pwd -W 2>/dev/null || pwd))"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --user-data-dir="$TMP/aven-studio-$$-$RANDOM" \
    --default-background-color=00000000 --virtual-time-budget=10000 --window-size="$4,$5" \
    --screenshot="$dir/$(basename "$3")" "$STUDIO?a=$1&l=$2" >/dev/null 2>&1
  echo "$3"
}
export -f shot; export CHROME STUDIO
xargs -P "${JOBS:-6}" -L 1 bash -c 'shot $0 $1 $2 $3 $4' <"$jobs_file"
rm -f "$jobs_file"

# Play wants the app icon as 32-bit PNG; Chrome writes 24-bit.
python -c "
from PIL import Image
import os
for f in ['$OUT/icon-512.png', '$OUT/icon-512-light.png']:
    if os.path.exists(f): Image.open(f).convert('RGBA').save(f)
"
