! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - crash screen for fatal CPU exceptions (clean-room)
!
! Vectors 4 (illegal instruction), 6 (illegal slot instruction), 9 (CPU
! address error) and 10 (DMA address error) come here instead of returning.
! The console is brought up again and the exception is described:
!   vector, PC and SR pushed by the CPU, PR, SP, and the words just before
!   PR (the call that led here when a game jumped through a bad pointer).
! Then the CPU halts with interrupts masked.

        .section .text
        .global crash_entries
        .global CRASH_ENTRY_SIZE

        .equ    CRASH_ENTRY_SIZE, 8

! One 8-byte entry per fatal vector: save r0, load the vector number
        .align  2
crash_entries:
        .irp    v, 4, 6, 9, 10
        mov.l   r0, @-r15
        mov     #\v, r0
        bra     crash
        nop
        .endr

crash:
        mov     #0xF0, r1               ! mask interrupts
        extu.b  r1, r1
        ldc     r1, sr
        mov     r0, r8                  ! r8 = vector
        mov.l   @(4, r15), r9           ! r9 = PC pushed by the exception
        mov.l   @(8, r15), r10          ! r10 = SR pushed by the exception
        sts     pr, r11                 ! r11 = PR
        mov     r15, r12
        add     #12, r12                ! r12 = SP before the exception
        mov.l   p_vdp2_init, r0         ! console again (leaf, no stack)
        jsr     @r0
        nop
        mova    t_title, r0
        mov     r0, r4
        mov     #2, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     #2, r6
        mova    fields, r0              ! (label, register index) pairs
        mov     r0, r13
        mov     #4, r14                 ! r14 = row
1:      mov.l   @r13+, r4
        tst     r4, r4
        bt      2f
        mov     #2, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     r14, r6
        mov.l   @r13+, r0               ! value: 8 = vector, 9 = PC, ...
        cmp/eq  #8, r0
        bf      3f
        bra     5f
        mov     r8, r4
3:      cmp/eq  #9, r0
        bf      4f
        bra     5f
        mov     r9, r4
4:      cmp/eq  #10, r0
        bf      6f
        bra     5f
        mov     r10, r4
6:      cmp/eq  #11, r0
        bf      7f
        bra     5f
        mov     r11, r4
7:      cmp/eq  #12, r0
        bf      8f
        bra     5f
        mov     r12, r4
8:      mov     r11, r1                 ! 13: word at PR - 4 (the call), 14: PR - 8
        cmp/eq  #13, r0
        bt/s    9f
        add     #-4, r1
        add     #-4, r1
9:      mov     #1, r0                  ! only read inside Work RAM / ROM
        tst     r0, r1                  ! (must be word aligned)
        bf      10f
        mov.w   @r1, r4
        extu.w  r4, r4
        bra     5f
        nop
10:     mov     #-1, r4
5:      mov     #20, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     r14, r6
        bra     1b
        add     #1, r14
2:      add     #1, r14             ! code around PC: 32 bytes from the
        mova    t_code, r0              ! 16-byte boundary before it
        mov     r0, r4
        mov     #2, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     r14, r6
        mov     r9, r8
        add     #-16, r8
        mov     #-16, r0
        and     r0, r8                  ! r8 = start address
        mov     r8, r4
        mov     #20, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     r14, r6
        add     #1, r14
        mov     #8, r13                 ! 8 longwords, 4 per row
        mov     #2, r11
3:      mov.l   @r8+, r4
        mov     r11, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     r14, r6
        add     #9, r11
        mov     #38, r0
        cmp/hs  r0, r11
        bf      4f
        mov     #2, r11
        add     #1, r14
4:      dt      r13
        bf      3b
5:      bra     5b
        nop

        .align  2
p_vdp2_init:    .long   vdp2_init
p_con_puts:     .long   con_puts
p_con_puthex:   .long   con_puthex

        .align  2
fields:
        .long   t_vec, 8
        .long   t_pc, 9
        .long   t_sr, 10
        .long   t_pr, 11
        .long   t_sp, 12
        .long   t_call, 13
        .long   t_call2, 14
        .long   0

        .align  2
t_title:        .asciz  "Saturn Open BIOS: fatal exception"
        .align  2
t_vec:          .asciz  "Vector"
        .align  2
t_pc:           .asciz  "PC"
        .align  2
t_sr:           .asciz  "SR"
        .align  2
t_pr:           .asciz  "PR"
        .align  2
t_sp:           .asciz  "SP"
        .align  2
t_call:         .asciz  "Word at PR-4"
        .align  2
t_call2:        .asciz  "Word at PR-8"
        .align  2
t_code:         .asciz  "Code from"
