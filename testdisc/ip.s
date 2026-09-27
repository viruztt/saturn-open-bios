! SPDX-License-Identifier: GPL-2.0-or-later
! IP.BIN for the SaturnOpenBios test disc (our own content only).
!
! Header layout from the public disc format description. The security code
! area is a zero-filled placeholder: SaturnOpenBios only checks that the IP
! is large enough to contain it. No Sega code or data is included.

        .section .text
        .ascii  "SEGA SEGASATURN "      ! 0x00 hardware identifier
        .ascii  "OPENBIOS TEST   "      ! 0x10 maker ID
        .ascii  "T-00000   "            ! 0x20 product number
        .ascii  "V1.000"                ! 0x2A version
        .ascii  "20260927"              ! 0x30 release date
        .ascii  "CD-1/1  "              ! 0x38 device information
        .ascii  "JTUE      "            ! 0x40 area symbols
        .ascii  "      "                ! 0x4A
        .ascii  "J               "      ! 0x50 peripherals
        .ascii  "SATURNOPENBIOS TEST DISC"   ! 0x60 title (112 bytes, space padded)
        .org    0xD0, 0x20
        .org    0xE0, 0x20              ! 0xD0 reserved
        .long   0x1000                  ! 0xE0 IP size
        .long   0                       ! 0xE4 reserved
        .long   0                       ! 0xE8 master stack (0 = BIOS default)
        .long   0                       ! 0xEC slave stack
        .long   0x06004000              ! 0xF0 first read file load address
        .long   0                       ! 0xF4 first read size (BIOS uses the file size)
        .long   0, 0                    ! 0xF8 reserved

        ! 0x100-0xDFF: security code area (placeholder)
        .org    0xE00, 0

        ! 0xE00: where the BIOS starts executing. Jump to the first read file.
        mov.l   1f, r0
        jmp     @r0
        nop
        .align  2
1:      .long   0x06004000

        .org    0x1000, 0
