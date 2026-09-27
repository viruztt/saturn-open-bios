#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Write test/dummy.iso: a placeholder disc whose sector 0 carries the Saturn
system ID so emulators accept it. The BIOS does not read the disc yet."""
import os
hdr = (b"SEGA SEGASATURN " b"SEGA TP OPENBIOS" + b"T-00000  V1.000".ljust(16)
       + b"20260927CD-1/1  " + b"JTUE      " + b"J               ")
data = bytearray(2048 * 300)
data[:len(hdr)] = hdr
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "test", "dummy.iso")
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, "wb").write(data)
