#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Turn a 2048-byte-sector test disc image into a BIN/CUE with a CD-DA track.

Usage: mkaudiodisc.py IN.ISO OUT.BIN OUT.CUE

Track 1 is the data (MODE1/2352 with sync, header, EDC and ECC). Track 2 is
a generated test tone: 2 seconds of silence (index 0), then 30 seconds of
a 440 Hz sine on the left channel and 660 Hz on the right. A clean tone
makes clicks and crackling easy to hear.
"""
import math
import os
import struct
import sys

RAW = 2352
TONE_SECONDS = 30
PREGAP = 150                                    # 2 seconds of silence


def edc_table():
    t = []
    for i in range(256):
        e = i
        for _ in range(8):
            e = (e >> 1) ^ (0xD8018001 if e & 1 else 0)
        t.append(e)
    return t


EDC = edc_table()
GF_EXP = [0] * 512
GF_LOG = [0] * 256
_x = 1
for _i in range(255):
    GF_EXP[_i] = _x
    GF_LOG[_x] = _i
    _x <<= 1
    if _x & 0x100:
        _x ^= 0x11D
for _i in range(255, 512):
    GF_EXP[_i] = GF_EXP[_i - 255]


def gf_mul(a, b):
    if a == 0 or b == 0:
        return 0
    return GF_EXP[GF_LOG[a] + GF_LOG[b]]


def edc(data):
    e = 0
    for b in data:
        e = (e >> 8) ^ EDC[(e ^ b) & 0xFF]
    return e


def ecc_compute(sector):
    """Fill P parity (0x81C, 172 bytes) and Q parity (0x8C8, 104 bytes),
    the ECMA-130 product code over bytes 12..0x8C7."""
    def block(major_count, minor_count, major_mult, minor_inc, dest):
        size = major_count * minor_count
        for major in range(major_count):
            index = (major >> 1) * major_mult + (major & 1)
            a = b = 0
            for _ in range(minor_count):
                t = sector[12 + index]
                index += minor_inc
                if index >= size:
                    index -= size
                a ^= t
                b ^= t
                a = gf_mul(a, 2)
            a = gf_mul(gf_mul(a, 2) ^ b, INV3)
            sector[dest + major] = a
            sector[dest + major + major_count] = a ^ b
    block(86, 24, 2, 86, 0x81C)
    block(52, 43, 86, 88, 0x8C8)


INV3 = GF_EXP[255 - GF_LOG[3]]


def bcd(v):
    return ((v // 10) << 4) | (v % 10)


def mode1_sector(lba, data):
    s = bytearray(RAW)
    s[0:12] = b"\x00" + b"\xff" * 10 + b"\x00"
    fad = lba + 150
    s[12] = bcd(fad // 4500)
    s[13] = bcd(fad // 75 % 60)
    s[14] = bcd(fad % 75)
    s[15] = 1
    s[16:2064] = data
    s[2064:2068] = struct.pack("<I", edc(s[0:2064]))
    ecc_compute(s)
    return bytes(s)


def tone_sectors():
    out = bytearray(RAW * PREGAP)
    frames = TONE_SECONDS * 44100
    for n in range(frames):
        left = int(8000 * math.sin(2 * math.pi * 440 * n / 44100))
        right = int(8000 * math.sin(2 * math.pi * 660 * n / 44100))
        out += struct.pack("<hh", left, right)
    out += bytes(-len(out) % RAW)
    return bytes(out)


def msf(sectors):
    return "%02d:%02d:%02d" % (sectors // 4500, sectors // 75 % 60, sectors % 75)


def main(iso_path, bin_path, cue_path):
    iso = open(iso_path, "rb").read()
    count = len(iso) // 2048
    with open(bin_path, "wb") as f:
        for lba in range(count):
            f.write(mode1_sector(lba, iso[lba * 2048:(lba + 1) * 2048]))
        f.write(tone_sectors())
    name = os.path.basename(bin_path)
    with open(cue_path, "w", newline="\r\n") as f:
        f.write('FILE "%s" BINARY\n' % name)
        f.write("  TRACK 01 MODE1/2352\n    INDEX 01 00:00:00\n")
        f.write("  TRACK 02 AUDIO\n    INDEX 00 %s\n    INDEX 01 %s\n"
                % (msf(count), msf(count + PREGAP)))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
