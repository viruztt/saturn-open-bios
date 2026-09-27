! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - minimal boot stage (clean-room, written from public hardware docs)
!
! Master SH-2 starts here after power-on: the ROM is mapped at 0x00000000 and the
! CPU fetches its initial PC and SP from the first two longwords of the vector table.
! Brings up the VDP2 text console, then runs the cold-boot init steps
! (src/init.s) and reports each one on screen.

        .section .text
        .global _start
        .global unhandled

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

        .equ    STACK_TOP,  0x06002000   ! below IP.BIN; the game's default master stack

        .align  2
_start:
        ! Mask all interrupts (SR.I3-0 = 0xF)
        mov.l   sr_init, r0
        ldc     r0, sr

        ! Both SH-2s start here. The slave (BCR1 bit 15 = MASTER pin set) is
        ! only started by a game, via SMPC SSHON: send it to slave_start
        ! instead of re-initialising the machine under the running game.
        mov.l   reg_bcr1, r1
        mov.l   @r1, r0
        mov.w   c_master_bit, r1
        tst     r1, r0
        bt      1f
        mov.l   p_slave_start, r0
        jmp     @r0
        nop
c_master_bit:   .word   0x8000
        .align  2
1:

        ! Cache: disable + purge, then enable (hardware is always accessed
        ! through the cache-through mirrors)
        mov.l   reg_ccr, r1
        mov     #0x10, r0               ! CP
        mov.b   r0, @r1
        mov     #0x01, r0               ! CE
        mov.b   r0, @r1

        ! Console first, so every later step can report on screen
        mov.l   p_vdp2_init, r0
        jsr     @r0
        nop
        .ifdef  DIAG                    ! after a reset: where did the game hang?
        mov.l   p_diag_postmortem, r0
        jsr     @r0
        nop
        .endif

        mova    msg_title, r0
        mov     r0, r4
        mov     #2, r5
        mov     #0, r6
        mov.l   p_con_puts, r0
        jsr     @r0
        nop

        ! Run the init steps: print the name, call it, print OK or FAIL.
        ! Later steps depend on earlier ones, so stop at the first failure.
        ! r8 = step table, r9 = screen row, r10 = nonzero once a step failed
        mova    steps, r0
        mov     r0, r8
        mov     #2, r9
        mov     #0, r10
step:
        mov.l   @r8+, r4
        tst     r4, r4
        bt      steps_done
        mov     #2, r5
        mov     r9, r6
        mov.l   p_con_puts, r0
        jsr     @r0
        nop
        mov.l   @r8+, r0
        jsr     @r0
        nop
        tst     r0, r0
        bf      1f
        mova    msg_ok, r0
        bra     2f
        nop
1:      mov     #1, r10
        mova    msg_fail, r0
2:      mov     r0, r4
        mov     #24, r5
        mov     r9, r6
        mov.l   p_con_puts, r0
        jsr     @r0
        nop
        tst     r10, r10
        bf/s    steps_done
        add     #1, r9
        bra     step
        nop

steps_done:
        mov     r9, r13                 ! blank row between steps and readouts
        ! Read back a few live values: (label, address, 0 = word / 1 = long /
        ! 2 = NUL-terminated string)
        add     #1, r9
        mova    readouts, r0
        mov     r0, r8
show:
        mov.l   @r8+, r4
        tst     r4, r4
        bt      readouts_done
        mov     #2, r5
        mov     r9, r6
        mov.l   p_con_puts, r0
        jsr     @r0
        nop
        mov.l   @r8+, r1
        mov.l   @r8+, r0
        mov     #24, r5
        mov     r9, r6
        cmp/eq  #2, r0
        bt      3f
        tst     r0, r0
        bf/s    1f
        mov.l   @r1, r4
        mov.w   @r1, r4
        extu.w  r4, r4
1:      mov.l   p_con_puthex, r0
2:      jsr     @r0
        nop
        bra     show
        add     #1, r9
3:      mov.l   p_con_puts, r0          ! string (no PC-relative load in a delay slot)
        bra     2b
        mov     r1, r4

readouts_done:
        ! Boot the disc only if every step passed; otherwise stay on this screen
        ! and show 16 raw bytes (hex) on the last row: FAD 150 as first read if the
        ! IP.BIN header was wrong, else the start of the last sector read
        tst     r10, r10
        bt      20f
        mov.l   p_raw0, r8              ! FAD 150 if IP.BIN was the problem,
        mov.l   p_hdr, r1               ! else the last sector read
        mov.l   @r1, r0
        mov.l   c_sega, r1
        cmp/eq  r1, r0
        bf      22f
        mov.l   p_last16, r8
22:     mov.l   p_sirej, r1             ! blank row: Get Sector Info rejected,
        mov.l   @r1, r4                 ! sectors dropped, free buffer blocks
        mov     #2, r5                  ! and HIRQ when a read gave up
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     r13, r6
        mov.l   p_dropped, r1
        mov.l   @r1, r4
        mov     #11, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     r13, r6
        mov.l   p_freeblk, r1
        mov.l   @r1, r4
        mov     #20, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     r13, r6
        mov.l   p_freeblk, r1
        mov.l   @(4, r1), r4
        mov     #29, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     r13, r6
        mov.l   p_toc, r12              ! row 25: TOC entries for tracks 1-3
        mov     #2, r11                 ! and the lead-out (control/ADR, FAD)
23:     mov.l   @r12+, r4
        mov     r11, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     #25, r6
        add     #9, r11
        mov     #29, r0
        cmp/hs  r0, r11
        bf      23b
        mov.l   p_leadout, r1
        mov.l   @r1, r4
        mov     #29, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     #25, r6
        mov     #2, r11
21:     mov.l   @r8+, r4
        mov     r11, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     #27, r6
        add     #9, r11
        mov     #38, r0
        cmp/hs  r0, r11
        bf      21b
        bra     idle
        nop
20:
        add     #1, r9
        mova    msg_boot, r0
        mov     r0, r4
        mov     #2, r5
        mov     r9, r6
        mov.l   p_con_puts, r0
        jsr     @r0
        nop
        .ifdef  NOBOOT                  ! debug builds: stop before the hand-over
        bra     idle
        nop
        .endif
        mov.l   p_handover_check, r0
        jsr     @r0
        nop
        mov.l   p_boot_game, r0
        jmp     @r0
        nop

idle:
        bra     idle
        nop

! Fatal exceptions end up here: mask interrupts and halt
unhandled:
        mov.l   sr_init, r0
        ldc     r0, sr
1:      bra     1b
        nop

        .align  2
sr_init:        .long   0x000000F0
reg_bcr1:       .long   0xFFFFFFE0      ! bus control register 1
p_slave_start:  .long   slave_start
reg_ccr:        .long   0xFFFFFE92      ! SH-2 cache control register
p_vdp2_init:    .long   vdp2_init
p_con_puts:     .long   con_puts
p_con_puthex:   .long   con_puthex
p_boot_game:    .long   boot_game
p_handover_check: .long handover_check
        .ifdef  DIAG
p_diag_postmortem: .long diag_postmortem
        .endif
p_raw0:         .long   CD_RAW0
p_last16:       .long   CD_LAST16
p_sirej:        .long   CD_SIREJ
p_dropped:      .long   CD_DROPPED
p_freeblk:      .long   CD_FREEBLK
p_hdr:          .long   CD_HDR
p_toc:          .long   CD_TOC
p_leadout:      .long   CD_TOC + 101 * 4
c_sega:         .long   0x53454741      ! "SEGA"

! Boot steps in order: (name, routine). wram_clear must come before any step
! that uses the stack, and vbr_init before sys_init.
        .align  2
steps:
        .long   msg_cpu,  cpu_init
        .long   msg_wram, wram_clear
        .long   msg_vbr,  vbr_init
        .long   msg_sys,  sys_init
        .long   msg_smpc, smpc_init
        .long   msg_scu,  scu_init
        .long   msg_scsp, scsp_init
        .long   msg_vdp1, vdp1_init
        .long   msg_cdi,  cd_init
        .long   msg_cda,  cd_auth
        .long   msg_cdt,  cd_toc
        .long   msg_cdr,  cd_read_ip
        .long   msg_ipl,  ip_load
        .long   msg_frd,  first_read
        .long   0

        .align  2
readouts:
        .long   msg_cau,  CD_AUTH, 0        ! CD authentication status
        .long   msg_cerr, CD_ERR, 1         ! last CD failure (0 = none)
        .long   msg_cfad, CD_FAD, 1         ! last CD read: next FAD
        .long   msg_cleft, CD_LEFT, 1       !   and sectors still to read
        .long   msg_ip,   CD_HDR, 2         ! first 16 bytes of IP.BIN
        .long   msg_area, IP_AREA, 2        ! area symbols (shown, not enforced)
        .long   msg_fra,  FR_ADDR, 1        ! first read file: load address
        .long   msg_frs,  FR_SIZE, 1        !   and size in bytes
        .long   0

        .align  2
msg_title:      .asciz  "Saturn Open BIOS"
        .align  2
msg_cpu:        .asciz  "SH-2 on-chip"
        .align  2
msg_wram:       .asciz  "Work RAM clear"
        .align  2
msg_vbr:        .asciz  "Vectors at 06000000"
        .align  2
msg_sys:        .asciz  "System calls"
        .align  2
msg_smpc:       .asciz  "SMPC slave+68K off"
        .align  2
msg_scu:        .asciz  "SCU DMA/IRQ off"
        .align  2
msg_scsp:       .asciz  "SCSP silence"
        .align  2
msg_vdp1:       .asciz  "VDP1 reset"
        .align  2
msg_ok:         .asciz  "OK"
        .align  2
msg_fail:       .asciz  "FAIL"
        .align  2
msg_cdi:        .asciz  "CD block init"
        .align  2
msg_cda:        .asciz  "CD authenticate"
        .align  2
msg_cdt:        .asciz  "CD read TOC"
        .align  2
msg_cdr:        .asciz  "CD read FAD 150"
        .align  2
msg_cerr:       .asciz  "CD error"
        .align  2
msg_cfad:       .asciz  "CD next FAD"
        .align  2
msg_cleft:      .asciz  "  sectors left"
        .align  2
msg_cau:        .asciz  "CD auth"
        .align  2
msg_ip:         .asciz  "IP.BIN"
        .align  2
msg_ipl:        .asciz  "IP.BIN load+check"
        .align  2
msg_frd:        .asciz  "1st read file"
        .align  2
msg_area:       .asciz  "Area"
        .align  2
msg_fra:        .asciz  "1st read addr"
        .align  2
msg_frs:        .asciz  "1st read size"
        .align  2
msg_boot:       .asciz  "Booting disc..."

        .align  2
! handover_check: MiSTer bring-up aid. Shows what is in memory where the
! game will run (16 bytes each at IP.BIN +0000/+0800/+0E00/+1000 and at the
! first read address) and the CD sector checks, for about 5 s.
        .align  2
handover_check:
        sts.l   pr, @-r15
        mov.l   ph_vdp2_init, r0
        jsr     @r0
        nop
        mova    msg_hocheck, r0
        mov     r0, r4
        mov     #2, r5
        mov.l   ph_con_puts, r0
        jsr     @r0
        mov     #0, r6
        mova    ho_rows, r0             ! (label, address, 1 = address of a pointer)
        mov     r0, r8
        mov     #2, r9
1:      mov.l   @r8+, r4
        tst     r4, r4
        bt      3f
        mov     #2, r5
        mov.l   ph_con_puts, r0
        jsr     @r0
        mov     r9, r6
        mov.l   @r8+, r10
        mov.l   @r8+, r0
        tst     r0, r0
        bt      4f
        mov.l   @r10, r10               ! dereference, read cache-through
        mov.l   c_uncached, r0
        or      r0, r10
4:      add     #1, r9
        mov     #2, r11
        mov     #4, r12
2:      mov.l   @r10+, r4
        mov     r11, r5
        mov.l   ph_con_puthex, r0
        jsr     @r0
        mov     r9, r6
        add     #9, r11
        dt      r12
        bf      2b
        bra     1b
        add     #2, r9
3:      mov.w   c_hold, r8              ! hold for about 5 s
5:      mov.l   p_vbl_wait, r0
        jsr     @r0
        nop
        dt      r8
        bf      5b
        lds.l   @r15+, pr
        rts
        nop

        .align  2
ho_rows:
        .long   msg_ho0,  0x26002000, 0
        .long   msg_ho1,  0x26002800, 0
        .long   msg_ho2,  0x26002E00, 0
        .long   msg_ho3,  0x26003000, 0
        .long   msg_ho4,  FR_ADDR, 1
        .long   msg_ho5,  CD_SIREJ, 0
        .long   msg_ho6,  CD_DROPPED - 4, 0
        .long   0
p_vbl_wait:     .long   vbl_wait
ph_vdp2_init:   .long   vdp2_init
ph_con_puts:    .long   con_puts
ph_con_puthex:  .long   con_puthex
c_uncached:     .long   0x20000000
c_hold:         .word   300
        .align  2
msg_hocheck:    .asciz  "Hand-over check"
        .align  2
msg_ho0:        .asciz  "IP.BIN +0000"
        .align  2
msg_ho1:        .asciz  "IP.BIN +0800 (2nd sector)"
        .align  2
msg_ho2:        .asciz  "IP.BIN +0E00 (entry code)"
        .align  2
msg_ho3:        .asciz  "IP.BIN +1000 (3rd sector)"
        .align  2
msg_ho4:        .asciz  "1st read file start"
        .align  2
msg_ho5:        .asciz  "CD: SI rejected, error, FAD, left"
        .align  2
msg_ho6:        .asciz  "CD: chunk, dropped, width, -"
