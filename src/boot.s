! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - minimal boot stage (clean-room, written from public hardware docs)
!
! Master SH-2 starts here after power-on: the ROM is mapped at 0x00000000 and the
! CPU fetches its initial PC and SP from the first two longwords of the vector table.
! Brings up the VDP2 text console and prints a banner.

        .section .text
        .global _start

! ---- Exception vector table (SH-2: 4 bytes per vector) ---------------------
vectors:
        .long   _start          ! 0: power-on reset PC
        .long   STACK_TOP       ! 1: power-on reset SP
        .long   _start          ! 2: manual reset PC
        .long   STACK_TOP       ! 3: manual reset SP
        .rept   60
        .long   unhandled       ! 4..63: CPU exceptions / traps
        .endr
        .rept   64
        .long   unhandled       ! 64..127: external interrupt vectors
        .endr

        .equ    STACK_TOP,  0x06100000   ! top of Work RAM High (1 MB at 0x06000000)

        .align  2
_start:
        ! Mask all interrupts (SR.I3-0 = 0xF)
        mov.l   sr_init, r0
        ldc     r0, sr

        mov.l   p_vdp2_init, r0
        jsr     @r0
        nop

        mova    msg_title, r0
        mov     r0, r4
        mov     #2, r5
        mov     #2, r6
        mov.l   p_con_puts, r0
        jsr     @r0
        nop

        mova    msg_stage, r0
        mov     r0, r4
        mov     #2, r5
        mov     #4, r6
        mov.l   p_con_puts, r0
        jsr     @r0
        nop

        ! Read something live from the hardware to prove the hex printer
        mova    msg_vdp2, r0
        mov     r0, r4
        mov     #2, r5
        mov     #6, r6
        mov.l   p_con_puts, r0
        jsr     @r0
        nop
        mov.l   reg_vrsize, r1
        mov.w   @r1, r4
        extu.w  r4, r4
        mov     #18, r5
        mov     #6, r6
        mov.l   p_con_puthex, r0
        jsr     @r0
        nop

idle:
        bra     idle
        nop

unhandled:
        bra     unhandled
        nop

        .align  2
sr_init:        .long   0x000000F0
p_vdp2_init:    .long   vdp2_init
p_con_puts:     .long   con_puts
p_con_puthex:   .long   con_puthex
reg_vrsize:     .long   0x25F80004      ! VDP2 VRSIZE (VRAM size + version)

        .align  2
msg_title:      .asciz  "Saturn Open BIOS"
        .align  2
msg_stage:      .asciz  "Stage 1: text console"
        .align  2
msg_vdp2:       .asciz  "VDP2 VRSIZE:"
