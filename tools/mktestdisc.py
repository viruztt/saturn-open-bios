#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build a minimal Saturn test disc image (2048-byte sectors, ISO 9660).

Usage: mktestdisc.py IP.BIN PROGRAM.BIN OUT.ISO

Sectors 0-15 hold IP.BIN, 16 the primary volume descriptor, 17 the set
terminator, 18/19 the L/M path tables, 20 the root directory, and the
program ("0.BIN", the first file in the root directory) starts at 21.
"""
import sys

SECTOR = 2048
PVD, TERM, PATH_L, PATH_M, ROOT, FILE = 16, 17, 18, 19, 20, 21
MIN_SECTORS = 300


def both16(v):
    return v.to_bytes(2, "little") + v.to_bytes(2, "big")


def both32(v):
    return v.to_bytes(4, "little") + v.to_bytes(4, "big")


def text(s, n):
    return s.encode("ascii").ljust(n, b" ")


def dir_record(name, lba, size, is_dir):
    rec = bytearray(33)
    rec[2:10] = both32(lba)
    rec[10:18] = both32(size)
    rec[18:25] = bytes([126, 9, 27, 0, 0, 0, 0])   # 2026-09-27 00:00:00 GMT
    rec[25] = 2 if is_dir else 0
    rec[28:32] = both16(1)
    rec[32] = len(name)
    rec += name
    if len(rec) % 2:
        rec += b"\0"
    rec[0] = len(rec)
    return bytes(rec)


def path_table(big_endian):
    order = "big" if big_endian else "little"
    return bytes([1, 0]) + ROOT.to_bytes(4, order) + (1).to_bytes(2, order) + b"\0\0"


def main(ip_path, prog_path, out_path):
    ip = open(ip_path, "rb").read()
    prog = open(prog_path, "rb").read()
    if len(ip) > 16 * SECTOR:
        sys.exit("IP.BIN larger than 16 sectors")
    prog_sectors = (len(prog) + SECTOR - 1) // SECTOR
    total = max(FILE + prog_sectors, MIN_SECTORS)
    img = bytearray(total * SECTOR)

    def put(lba, data):
        img[lba * SECTOR:lba * SECTOR + len(data)] = data

    put(0, ip)

    root = (dir_record(b"\0", ROOT, SECTOR, True) + dir_record(b"\1", ROOT, SECTOR, True)
            + dir_record(b"0.BIN;1", FILE, len(prog), False))
    pt = path_table(False)

    pvd = bytearray(SECTOR)
    pvd[0] = 1
    pvd[1:6] = b"CD001"
    pvd[6] = 1
    pvd[8:40] = text("SEGA SEGASATURN", 32)
    pvd[40:72] = text("OPENBIOS_TEST", 32)
    pvd[80:88] = both32(total)
    pvd[120:124] = both16(1)
    pvd[124:128] = both16(1)
    pvd[128:132] = both16(SECTOR)
    pvd[132:140] = both32(len(pt))
    pvd[140:144] = PATH_L.to_bytes(4, "little")
    pvd[148:152] = PATH_M.to_bytes(4, "big")
    pvd[156:190] = dir_record(b"\0", ROOT, SECTOR, True)
    pvd[190:813] = b" " * (813 - 190)
    for i in range(4):                          # creation/modification/expiry/effective
        pvd[813 + 17 * i:813 + 17 * i + 17] = b"0" * 16 + b"\0"
    pvd[881] = 1
    put(PVD, pvd)
    put(TERM, b"\xffCD001\x01")
    put(PATH_L, pt)
    put(PATH_M, path_table(True))
    put(ROOT, root)
    put(FILE, prog)
    open(out_path, "wb").write(img)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
