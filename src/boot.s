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

        .equ    STACK_TOP,  0x06100000   ! top of Work RAM High (1 MB at 0x06000000)

        .align  2
_start:
        ! Mask all interrupts (SR.I3-0 = 0xF)
        mov.l   sr_init, r0
        ldc     r0, sr

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

        mova    msg_title, r0
        mov     r0, r4
        mov     #2, r5
        mov     #2, r6
        mov.l   p_con_puts, r0
        jsr     @r0
        nop

        ! Run the init steps: print the name, call it, print OK or FAIL.
        ! r8 = step table, r9 = screen row
        mova    steps, r0
        mov     r0, r8
        mov     #4, r9
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
1:      mova    msg_fail, r0
2:      mov     r0, r4
        mov     #24, r5
        mov     r9, r6
        mov.l   p_con_puts, r0
        jsr     @r0
        nop
        bra     step
        add     #1, r9

steps_done:
        ! Read back a few live values: (label, address, 0 = word / 1 = long /
        ! 2 = NUL-terminated string)
        add     #1, r9
        mova    readouts, r0
        mov     r0, r8
show:
        mov.l   @r8+, r4
        tst     r4, r4
        bt      idle
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
reg_ccr:        .long   0xFFFFFE92      ! SH-2 cache control register
p_vdp2_init:    .long   vdp2_init
p_con_puts:     .long   con_puts
p_con_puthex:   .long   con_puthex

! Boot steps in order: (name, routine). wram_clear must come before any step
! that uses the stack (smpc_init), and before vbr_init.
        .align  2
steps:
        .long   msg_cpu,  cpu_init
        .long   msg_wram, wram_clear
        .long   msg_vbr,  vbr_init
        .long   msg_smpc, smpc_init
        .long   msg_scu,  scu_init
        .long   msg_scsp, scsp_init
        .long   msg_vdp1, vdp1_init
        .long   msg_cdi,  cd_init
        .long   msg_cda,  cd_auth
        .long   msg_cdt,  cd_toc
        .long   msg_cdr,  cd_read_ip
        .long   0

        .align  2
readouts:
        .long   msg_vdp2, 0x25F80004, 0     ! VDP2 VRSIZE (VRAM size + version)
        .long   msg_vec4, 0x26000010, 1     ! master vector 4 in Work RAM
        .long   msg_edsr, 0x25D00010, 0     ! VDP1 EDSR (list end status)
        .long   msg_cst,  CD_STAT, 1        ! CD status report CR1:CR2
        .long   msg_cau,  CD_AUTH, 0        ! CD authentication status
        .long   msg_tr1,  CD_TOC, 1         ! TOC entry for track 1
        .long   msg_tlo,  CD_TOC + 101*4, 1 ! TOC lead-out
        .long   msg_ip,   CD_HDR, 2         ! first 16 bytes of IP.BIN
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
msg_vdp2:       .asciz  "VDP2 VRSIZE"
        .align  2
msg_vec4:       .asciz  "Vector 4 (RAM)"
        .align  2
msg_edsr:       .asciz  "VDP1 EDSR"
        .align  2
msg_cdi:        .asciz  "CD block init"
        .align  2
msg_cda:        .asciz  "CD authenticate"
        .align  2
msg_cdt:        .asciz  "CD read TOC"
        .align  2
msg_cdr:        .asciz  "CD read FAD 150"
        .align  2
msg_cst:        .asciz  "CD status"
        .align  2
msg_cau:        .asciz  "CD auth"
        .align  2
msg_tr1:        .asciz  "TOC track 1"
        .align  2
msg_tlo:        .asciz  "TOC lead-out"
        .align  2
msg_ip:         .asciz  "IP.BIN"
