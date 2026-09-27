! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - compatibility diagnostics (debug builds only: make diag)
!
! Records how a game uses the BIOS, from behaviour only:
!   - a call counter per system call (the call table points at counting
!     wrappers that then jump to the real service),
!   - VBlank-IN interrupts that pass through the dispatcher, with the PC, PR
!     and SR the game was interrupted at and the last 8 PCs kept in a ring,
!   - how many times the slave SH-2 was started.
! After DIAG_VBLANKS VBlank interrupts it takes over the screen and shows the
! numbers: page 1 (calls), then about 5 s later page 2 (PCs and a snapshot
! of CD block, SCU, SMPC and VDP status). Variables live at 0x06000C80..

        .section .text

        .ifdef  DIAG

        .global diag_irq
        .global DIAG_SLAVE

        .equ    DIAG,       0x26000C80      ! variables, cache-through
        .equ    DIAG_COUNT, DIAG + 0x00     ! VBlank-IN interrupts seen
        .equ    DIAG_PC,    DIAG + 0x04     ! last interrupted PC
        .equ    DIAG_PR,    DIAG + 0x08     ! last interrupted PR
        .equ    DIAG_SR,    DIAG + 0x0C     ! last interrupted SR
        .equ    DIAG_SLAVE, DIAG + 0x10     ! slave SH-2 starts
        .equ    DIAG_RINGI, DIAG + 0x14     ! next PC ring slot (0-7)
        .equ    DIAG_CALLS, DIAG + 0x20     ! one longword per system call
        .equ    DIAG_RING,  DIAG + 0x60     ! last 8 VBlank PCs
        .equ    DIAG_VBLANKS, 900           ! about 15 s at 60 Hz

! DIAGWRAP n, service: count call n, then continue in the service
        .macro  DIAGWRAP n, service
        .global diag_w_\service
        .align  2
diag_w_\service:
        mov.l   .Lc\@, r1
        mov.l   @r1, r0
        add     #1, r0
        mov.l   r0, @r1
        mov.l   .Lf\@, r0
        jmp     @r0
        nop
        .align  2
.Lc\@:  .long   DIAG_CALLS + \n * 4
.Lf\@:  .long   \service
        .endm

        DIAGWRAP 0,  sc_power_clear
        DIAGWRAP 1,  sc_cd_player
        DIAGWRAP 2,  sc_mpeg_check
        DIAGWRAP 3,  sc_change_prio
        DIAGWRAP 4,  sc_cd_init2
        DIAGWRAP 5,  sc_cd_init1
        DIAGWRAP 6,  sc_set_scu_int
        DIAGWRAP 7,  sc_get_scu_int
        DIAGWRAP 8,  sc_set_sh2_int
        DIAGWRAP 9,  sc_get_sh2_int
        DIAGWRAP 10, sc_change_clock
        DIAGWRAP 11, sc_get_sem
        DIAGWRAP 12, sc_clear_sem
        DIAGWRAP 13, sc_set_scu_mask
        DIAGWRAP 14, sc_change_scu_mask
        DIAGWRAP 15, bup_init

! diag_irq: called by the SCU dispatcher with r0 = vector, r1 = the
! interrupted PC, r2 = SR, r3 = PR. May clobber r0-r3 only. Counts the
! vector; for VBlank-IN also samples the PC and shows the report once
! enough VBlanks have been seen.
        .align  2
diag_irq:
        cmp/eq  #0x40, r0               ! VBlank-IN only
        bf      9f
        mov.l   c_diag, r0
        mov.l   r1, @(4, r0)
        mov.l   r3, @(8, r0)
        mov.l   r2, @(12, r0)
        mov.l   @(20, r0), r2           ! ring[i] = PC, i = (i + 1) & 7
        mov     r2, r3
        shll2   r3
        add     r0, r3
        add     #0x60, r3
        mov.l   r1, @r3
        add     #1, r2
        mov     #7, r3
        and     r3, r2
        mov.l   r2, @(20, r0)
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        mov.w   c_limit, r2
        cmp/hs  r2, r1
        bt      report
9:      rts
        nop

report:
        mov     #0xF0, r0
        extu.b  r0, r0
        ldc     r0, sr
        mov.l   p_vdp2_init, r0
        jsr     @r0
        nop
        mova    t_title, r0
        mov     r0, r4
        mov     #2, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     #1, r6
        mova    rows, r0                ! (label, address) pairs
        mov     r0, r8
        mov     #3, r9
1:      mov.l   @r8+, r4
        tst     r4, r4
        bt      2f
        mov     #2, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     r9, r6
        mov.l   @r8+, r1
        mov.l   @r1, r4
        mov     #24, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     r9, r6
        bra     1b
        add     #1, r9
2:      mov.l   c_delay, r0             ! about 5 s, then page 2
3:      dt      r0
        bf      3b
        mov.l   p_vdp2_init, r0
        jsr     @r0
        nop
        mova    t_title2, r0
        mov     r0, r4
        mov     #2, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     #1, r6
        mova    t_ring, r0              ! 8 PCs, 3 per row
        mov     r0, r4
        mov.l   c_ring, r10
        mov     #8, r11
        mov     #3, r9
        bsr     grid
        nop
        add     #1, r9                  ! hardware snapshot: (label, address,
        mova    snap, r0                ! 0 = word / 1 = long / 2 = byte)
        mov     r0, r8
5:      mov.l   @r8+, r4
        tst     r4, r4
        bt      4f
        mov     #2, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     r9, r6
        mov.l   @r8+, r1
        mov.l   @r8+, r0
        cmp/eq  #1, r0
        bt/s    6f
        mov.l   @r1, r4
        cmp/eq  #2, r0
        bt/s    6f
        mov.b   @r1, r4
        mov.w   @r1, r4
6:      mov     #24, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     r9, r6
        bra     5b
        add     #1, r9
4:      bra     4b
        nop

! grid: label r4 at row r9, then r11 longwords from r10 as hex, 3 per row
! at columns 12, 21, 30 (r9 advances). Clobbers r0-r8, r10, r11.
grid:
        sts.l   pr, @-r15
        mov     #2, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     r9, r6
1:      mov     #12, r8
2:      mov.l   @r10+, r4
        mov     r8, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     r9, r6
        dt      r11
        bt      3f
        add     #9, r8
        mov     #39, r0
        cmp/hs  r0, r8
        bf      2b
        bra     1b
        add     #1, r9
3:      add     #1, r9
        lds.l   @r15+, pr
        rts
        nop

        .align  2
c_diag:         .long   DIAG
p_vdp2_init:    .long   vdp2_init
p_con_puts:     .long   con_puts
p_con_puthex:   .long   con_puthex
c_ring:         .long   DIAG_RING
c_delay:        .long   0x03000000
c_limit:        .word   DIAG_VBLANKS

        .align  2
snap:
        .long   s_hirq,  0x25890008, 0
        .long   s_hmask, 0x2589000C, 0
        .long   s_cr1,   0x25890018, 0
        .long   s_cr2,   0x2589001C, 0
        .long   s_cr3,   0x25890020, 0
        .long   s_cr4,   0x25890024, 0
        .long   s_ist,   0x25FE00A4, 1
        .long   s_sf,    0x20100063, 2
        .long   s_tvstat, 0x25F80004, 0
        .long   s_edsr,  0x25D00010, 0
        .long   s_shadow, 0x26000348, 1
        .long   s_sentry, 0x26000250, 1
        .long   s_sstack, 0x260002AC, 1
        .long   0

        .align  2
rows:
        .long   r_vbl,  DIAG_COUNT
        .long   r_pc,   DIAG_PC
        .long   r_pr,   DIAG_PR
        .long   r_sr,   DIAG_SR
        .long   r_slv,  DIAG_SLAVE
        .long   r_c0,   DIAG_CALLS + 0 * 4
        .long   r_c1,   DIAG_CALLS + 1 * 4
        .long   r_c2,   DIAG_CALLS + 2 * 4
        .long   r_c3,   DIAG_CALLS + 3 * 4
        .long   r_c4,   DIAG_CALLS + 4 * 4
        .long   r_c5,   DIAG_CALLS + 5 * 4
        .long   r_c6,   DIAG_CALLS + 6 * 4
        .long   r_c7,   DIAG_CALLS + 7 * 4
        .long   r_c8,   DIAG_CALLS + 8 * 4
        .long   r_c9,   DIAG_CALLS + 9 * 4
        .long   r_c10,  DIAG_CALLS + 10 * 4
        .long   r_c11,  DIAG_CALLS + 11 * 4
        .long   r_c12,  DIAG_CALLS + 12 * 4
        .long   r_c13,  DIAG_CALLS + 13 * 4
        .long   r_c14,  DIAG_CALLS + 14 * 4
        .long   r_c15,  DIAG_CALLS + 15 * 4
        .long   0

        .align  2
t_title:        .asciz  "Diagnostics"
        .align  2
t_title2:       .asciz  "Diagnostics 2"
        .align  2
t_ring:         .asciz  "Last PCs"
        .align  2
s_hirq:         .asciz  "CD HIRQ"
        .align  2
s_hmask:        .asciz  "CD HIRQ mask"
        .align  2
s_cr1:          .asciz  "CD CR1"
        .align  2
s_cr2:          .asciz  "CD CR2"
        .align  2
s_cr3:          .asciz  "CD CR3"
        .align  2
s_cr4:          .asciz  "CD CR4"
        .align  2
s_ist:          .asciz  "SCU IST"
        .align  2
s_sf:           .asciz  "SMPC SF"
        .align  2
s_tvstat:       .asciz  "VDP2 TVSTAT"
        .align  2
s_edsr:         .asciz  "VDP1 EDSR"
        .align  2
s_shadow:       .asciz  "Mask 06000348"
        .align  2
s_sentry:       .asciz  "Slave 06000250"
        .align  2
s_sstack:       .asciz  "Slave 060002AC"
        .align  2
r_vbl:          .asciz  "VBlank IRQs seen"
        .align  2
r_pc:           .asciz  "  last PC"
        .align  2
r_pr:           .asciz  "  last PR"
        .align  2
r_sr:           .asciz  "  last SR"
        .align  2
r_slv:          .asciz  "Slave starts"
        .align  2
r_c0:           .asciz  "0210 mem clear"
        .align  2
r_c1:           .asciz  "026C CD player"
        .align  2
r_c2:           .asciz  "0274 MPEG check"
        .align  2
r_c3:           .asciz  "0280 SCU prio"
        .align  2
r_c4:           .asciz  "029C CD init 2"
        .align  2
r_c5:           .asciz  "02DC CD init 1"
        .align  2
r_c6:           .asciz  "0300 set SCU int"
        .align  2
r_c7:           .asciz  "0304 get SCU int"
        .align  2
r_c8:           .asciz  "0310 set SH2 int"
        .align  2
r_c9:           .asciz  "0314 get SH2 int"
        .align  2
r_c10:          .asciz  "0320 clock"
        .align  2
r_c11:          .asciz  "0330 get sem"
        .align  2
r_c12:          .asciz  "0334 clear sem"
        .align  2
r_c13:          .asciz  "0340 set SCU mask"
        .align  2
r_c14:          .asciz  "0344 chg SCU mask"
        .align  2
r_c15:          .asciz  "0358 BUP init"

        .endif
