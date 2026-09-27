#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Boot the BIOS ($BIOS, default build/saturn-open-bios.bin) in Yabause under a
# virtual display and save a screenshot.
# Usage: tools/run-yabause.sh [disc image (.iso/.cue)] [out.png]
#        WAIT=seconds before the screenshot (default 12)
# Needs yabause, xvfb, x11-apps, imagemagick.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ISO=${1:-$ROOT/build/testdisc.iso}
OUT=${2:-$ROOT/build/screen.png}
WAIT=${WAIT:-12}
BIOS=${BIOS:-$ROOT/build/saturn-open-bios.bin}
TMP=$(mktemp -d)
timeout $((WAIT + 28)) xvfb-run -a -s "-screen 0 800x600x24" sh -c \
  "yabause -a -ns -b '$BIOS' -i '$ISO' >'$TMP/log' 2>&1 & sleep $WAIT; xwd -root -silent >'$TMP/shot.xwd'; kill \$! 2>/dev/null || true"
convert "$TMP/shot.xwd" -crop 640x426+0+54 "$OUT"
echo "screenshot: $OUT"
convert "$OUT" -format "%c" histogram:info:- | sort -rn | head -3
