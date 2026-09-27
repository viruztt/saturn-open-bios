! SPDX-License-Identifier: GPL-2.0-or-later
! First read file of the SaturnOpenBios test disc, loaded to 0x06004000.
!
! Proves the BIOS handed over: turns the back screen green and writes a line
! into the BIOS console's NBG0 map (its font maps character codes to ASCII).
! A real game would set up VDP2 itself.

        .section .text
        .global _start
_start:
        mov.l   c_back, r1
        mov.w   c_green, r0
        mov.w   r0, @r1

        mov.l   c_map, r1
        mova    msg, r0
        mov     r0, r2
1:      mov.b   @r2+, r0
        tst     r0, r0
        bt      2f
        mov.w   r0, @r1
        bra     1b
        add     #2, r1
2:      bra     2b
        nop

        .align  2
c_back:         .long   0x25E7FFFE              ! BIOS back screen colour word
c_map:          .long   0x25E40000 + 26 * 128 + 2 * 2   ! row 26, column 2
c_green:        .word   0x8000 | (4 << 10) | (20 << 5) | 4
        .align  2
msg:            .asciz  "DISC PROGRAM RUNNING"
