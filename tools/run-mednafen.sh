#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Boot the BIOS ($BIOS, default build/saturn-open-bios.bin) in Mednafen under a
# virtual display and save a screenshot.
# Usage: tools/run-mednafen.sh [disc image (.cue/.iso)] [out.png]
#        WAIT=seconds before the screenshot (default 12)
# Needs mednafen (1.29 or newer), xvfb, x11-apps, imagemagick.
# Mednafen only hash-checks BIOS files named like Sega's (sega_101.bin,
# mpr-17933.bin, ...), so the BIOS must keep another name.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DISC=${1:-$ROOT/build/testdisc.iso}
OUT=${2:-$ROOT/build/screen.png}
WAIT=${WAIT:-12}
BIOS=${BIOS:-$ROOT/build/saturn-open-bios.bin}
TMP=$(mktemp -d)
DISC=$(cd "$(dirname "$DISC")" && pwd)/$(basename "$DISC")
BIOS=$(cd "$(dirname "$BIOS")" && pwd)/$(basename "$BIOS")
# Mednafen needs a cue sheet for a plain .iso
case $DISC in
*.iso)
  printf 'FILE "%s" BINARY\n  TRACK 01 MODE1/2048\n    INDEX 01 00:00:00\n' "$DISC" >"$TMP/disc.cue"
  DISC=$TMP/disc.cue ;;
esac
# A fresh Mednafen home per run: no saves or settings carried over
mkdir "$TMP/home"
export DISC BIOS TMP
timeout $((WAIT + 28)) xvfb-run -a -s "-screen 0 1024x768x24" sh -c '
  MEDNAFEN_HOME="$TMP/home" mednafen -force_module ss -filesys.untrusted_fip_check 0 \
    -ss.bios_jp "$BIOS" -ss.bios_na_eu "$BIOS" -ss.cart auto -sound 0 -video.fs 0 \
    "$DISC" >"$TMP/log" 2>&1 &
  sleep '"$WAIT"'; xwd -root -silent >"$TMP/shot.xwd"; kill $! 2>/dev/null || true'
convert "$TMP/shot.xwd" -crop 906x720+0+0 +repage "$OUT"
echo "screenshot: $OUT"
convert "$OUT" -format "%c" histogram:info:- | sort -rn | head -3
