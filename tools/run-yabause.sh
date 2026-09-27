#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Boot build/saturn-open-bios.bin in Yabause under a virtual display and save a screenshot.
# Usage: tools/run-yabause.sh [disc.iso] [out.png]   (needs yabause, xvfb, x11-apps, imagemagick)
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ISO=${1:-$ROOT/test/dummy.iso}
OUT=${2:-$ROOT/build/screen.png}
TMP=$(mktemp -d)
timeout 40 xvfb-run -a -s "-screen 0 800x600x24" sh -c \
  "yabause -a -ns -b '$ROOT/build/saturn-open-bios.bin' -i '$ISO' >'$TMP/log' 2>&1 & sleep 12; xwd -root -silent >'$TMP/shot.xwd'; kill \$! 2>/dev/null || true"
convert "$TMP/shot.xwd" -crop 640x426+0+54 "$OUT"
echo "screenshot: $OUT"
convert "$OUT" -format "%c" histogram:info:- | sort -rn | head -3
