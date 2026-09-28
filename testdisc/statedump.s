! SPDX-License-Identifier: GPL-2.0-or-later
! Post-BIOS state dump: a first read program that, before doing anything
! else, records CPU registers and a list of hardware registers exactly as
! the BIOS (and the disc's IP.BIN code) left them, then brings up its own
! text screen and shows them, two per row. Used to compare what different
! BIOSes hand over, by observation only.
!
! Linked with the BIOS's console.o and font.o at the disc's first read
! address (DUMP_ADDR, see the Makefile rule).

        .section .text
        .global _start

        .equ    BUF,        0x26080000      ! captured values (cache-through)
        .equ    SBUF,       0x26081000      ! slave's: flag, then values

_start:
        mov.l   c_buf, r14              ! r14 = buffer; no stack use until
        stc     sr, r0                  ! everything is captured
        mov.l   r0, @r14
        stc     vbr, r0
        mov.l   r0, @(4, r14)
        stc     gbr, r0
        mov.l   r0, @(8, r14)
        mov.l   r15, @(12, r14)
        add     #16, r14
        mova    regs, r0                ! (address, size) pairs
        mov     r0, r13
1:      mov.l   @r13+, r1               ! address (0 = end)
        tst     r1, r1
        bt      5f
        mov.l   @r13+, r0               ! size 1, 2 or 4
        add     #4, r13                 ! (skip the label)
        cmp/eq  #1, r0
        bf      2f
        mov.b   @r1, r2
        bra     4f
        extu.b  r2, r2
2:      cmp/eq  #2, r0
        bf      3f
        mov.w   @r1, r2
        bra     4f
        extu.w  r2, r2
3:      mov.l   @r1, r2
4:      mov.l   r2, @r14
        bra     1b
        add     #4, r14

5:      mov.l   p_vdp2_init, r0         ! now our own screen
        jsr     @r0
        nop
        mov.l   p_title, r4
        mov     #1, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     #0, r6
        mov.l   c_buf, r12              ! r12 = value, r13 = label table,
        mova    cpu_labels, r0          ! r10 = entry number
        mov     r0, r13
        mov     #0, r10
6:      mov.l   @r13+, r4               ! the four CPU values first
        tst     r4, r4
        bt      7f
        bsr     show
        nop
        bra     6b
        nop
7:      mova    regs, r0
        mov     r0, r13
8:      mov.l   @r13+, r0
        tst     r0, r0
        bt      9f
        add     #4, r13
        mov.l   @r13+, r4               ! label
        bsr     show
        nop
        bra     8b
        nop

! Page 2: start the slave the way games do (entry at 0x06000250, SMPC
! SSHOFF then SSHON) and show the state the BIOS gives it; the slave
! records it itself in slave_dump.
9:      mov.w   c_page_wait, r8         ! about 6 s of VBlanks first
10:     bsr     vblank
        nop
        dt      r8
        bf      10b
        mov.l   c_sbuf, r1              ! clear the "slave done" flag
        mov     #0, r0
        mov.l   r0, @r1
        mov.l   c_sentry, r1            ! slave entry point
        mov.l   p_slave_dump, r0
        mov.l   r0, @r1
        mov.l   c_sstack, r1            ! slave stack (both usual places)
        mov.l   c_sstack_val, r0
        mov.l   r0, @r1
        bsr     smpc
        mov     #0x03, r4               ! SSHOFF
        bsr     smpc
        mov     #0x02, r4               ! SSHON
        mov.l   c_slave_wait, r8        ! wait for the slave's flag
11:     mov.l   c_sbuf, r1
        mov.l   @r1, r0
        tst     r0, r0
        bf      12f
        dt      r8
        bf      11b
12:     mov.l   p_vdp2_init, r0
        jsr     @r0
        nop
        mov.l   p_title2, r4
        mov     #1, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     #0, r6
        mov.l   c_sbuf, r12             ! flag first, then the values
        mova    slave_labels, r0
        mov     r0, r13
        mov     #0, r10
13:     mov.l   @r13+, r4
        tst     r4, r4
        bt      14f
        bsr     show
        nop
        bra     13b
        nop
14:     mova    sregs, r0
        mov     r0, r13
15:     mov.l   @r13+, r0
        tst     r0, r0
        bt      16f
        add     #4, r13
        mov.l   @r13+, r4
        bsr     show
        nop
        bra     15b
        nop
16:     bra     16b
        nop

! vblank: wait for the start of the next VBlank. Clobbers r0, r1.
vblank:
        mov.l   c_tvstat, r1
1:      mov.w   @r1, r0
        tst     #8, r0
        bf      1b
2:      mov.w   @r1, r0
        tst     #8, r0
        bt      2b
        rts
        nop

! smpc: r4 = command; wait for SF clear, issue, wait for SF clear.
! Clobbers r0-r2.
smpc:
        mov.l   c_sf, r1
1:      mov.b   @r1, r0
        tst     #1, r0
        bf      1b
        mov     #1, r0
        mov.b   r0, @r1
        mov.l   c_comreg, r2
        mov.b   r4, @r2
2:      mov.b   @r1, r0
        tst     #1, r0
        bf      2b
        rts
        nop

! slave_dump: runs on the slave. Records SR, VBR, GBR, R15 and the sregs
! list at SBUF + 4, then sets the flag at SBUF and stops.
        .align  2
slave_dump:
        mov.l   c_sbuf2, r14
        add     #4, r14
        stc     sr, r0
        mov.l   r0, @r14
        stc     vbr, r0
        mov.l   r0, @(4, r14)
        stc     gbr, r0
        mov.l   r0, @(8, r14)
        mov.l   r15, @(12, r14)
        add     #16, r14
        mova    sregs, r0
        mov     r0, r13
1:      mov.l   @r13+, r1
        tst     r1, r1
        bt      5f
        mov.l   @r13+, r0
        add     #4, r13
        cmp/eq  #1, r0
        bf      2f
        mov.b   @r1, r2
        bra     4f
        extu.b  r2, r2
2:      cmp/eq  #2, r0
        bf      3f
        mov.w   @r1, r2
        bra     4f
        extu.w  r2, r2
3:      mov.l   @r1, r2
4:      mov.l   r2, @r14
        bra     1b
        add     #4, r14
5:      mov.l   c_sbuf2, r1
        mov     #1, r0
        mov.l   r0, @r1
6:      bra     6b
        nop

        .align  2
c_sbuf2:        .long   SBUF
c_sbuf:         .long   SBUF
p_title2:       .long   s_title2
c_sentry:       .long   0x26000250
c_sstack:       .long   0x260002AC
c_sstack_val:   .long   0x06001000
p_slave_dump:   .long   slave_dump
c_slave_wait:   .long   0x01000000
c_tvstat:       .long   0x25F80004
c_sf:           .long   0x20100063
c_comreg:       .long   0x2010001F
c_page_wait:    .word   360

        .align  2
slave_labels:   .long   l_flag, l_sr, l_vbr, l_gbr, l_r15, 0

! slave's own on-chip registers (address, size, label)
        .align  2
sregs:
        .long   0xFFFFFFE0, 4, l_bcr1
        .long   0xFFFFFFE4, 4, l_bcr2
        .long   0xFFFFFFE8, 4, l_wcr
        .long   0xFFFFFFEC, 4, l_mcr
        .long   0xFFFFFFF0, 4, l_rtcsr
        .long   0xFFFFFFF8, 4, l_rtcor
        .long   0xFFFFFE92, 1, l_ccr
        .long   0xFFFFFEE0, 2, l_icr
        .long   0xFFFFFEE2, 2, l_ipra
        .long   0xFFFFFE60, 2, l_iprb
        .long   0xFFFFFE62, 2, l_vcra
        .long   0xFFFFFE64, 2, l_vcrb
        .long   0xFFFFFE66, 2, l_vcrc
        .long   0xFFFFFE68, 2, l_vcrd
        .long   0xFFFFFEE4, 2, l_vcrwdt
        .long   0xFFFFFE10, 1, l_tier
        .long   0xFFFFFE11, 1, l_ftcsr
        .long   0xFFFFFE16, 1, l_tcr
        .long   0xFFFFFE80, 1, l_wtcsr
        .long   0xFFFFFFB0, 4, l_dmaor
        .long   0xFFFFFF0C, 4, l_vcrdiv
        .long   0xFFFFFFA0, 4, l_vdma0
        .long   0xFFFFFFA8, 4, l_vdma1
        .long   0

! show: label r4 and value @r12 (r12 += 4) at entry r10 (two per row from
! row 2: column 0 or 20). Clobbers r0-r7, r11.
show:
        sts.l   pr, @-r15
        mov     r10, r11
        shlr    r11
        add     #2, r11                 ! r11 = row
        mov     r10, r0
        tst     #1, r0
        bt/s    1f
        mov     #0, r7
        mov     #20, r7                 ! r7 = column
1:      mov     r7, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     r11, r6
        mov.l   @r12+, r4
        mov     r7, r5
        add     #8, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     r11, r6
        add     #1, r10
        lds.l   @r15+, pr
        rts
        nop

        .align  2
c_buf:          .long   BUF
p_title:        .long   s_title
p_vdp2_init:    .long   vdp2_init
p_con_puts:     .long   con_puts
p_con_puthex:   .long   con_puthex

        .align  2
cpu_labels:     .long   l_sr, l_vbr, l_gbr, l_r15, 0

! (address, size, label)
        .align  2
regs:
        .long   0xFFFFFFE0, 4, l_bcr1
        .long   0xFFFFFFE4, 4, l_bcr2
        .long   0xFFFFFFE8, 4, l_wcr
        .long   0xFFFFFFEC, 4, l_mcr
        .long   0xFFFFFFF0, 4, l_rtcsr
        .long   0xFFFFFFF8, 4, l_rtcor
        .long   0xFFFFFE92, 1, l_ccr
        .long   0xFFFFFEE0, 2, l_icr
        .long   0xFFFFFEE2, 2, l_ipra
        .long   0xFFFFFE60, 2, l_iprb
        .long   0xFFFFFE62, 2, l_vcra
        .long   0xFFFFFE64, 2, l_vcrb
        .long   0xFFFFFE66, 2, l_vcrc
        .long   0xFFFFFE68, 2, l_vcrd
        .long   0xFFFFFEE4, 2, l_vcrwdt
        .long   0xFFFFFE10, 1, l_tier
        .long   0xFFFFFE11, 1, l_ftcsr
        .long   0xFFFFFE16, 1, l_tcr
        .long   0xFFFFFE80, 1, l_wtcsr
        .long   0xFFFFFFB0, 4, l_dmaor
        .long   0xFFFFFF8C, 4, l_chcr0
        .long   0xFFFFFF9C, 4, l_chcr1
        .long   0xFFFFFF0C, 4, l_vcrdiv
        .long   0x25FE00A0, 4, l_ims
        .long   0x25FE00A4, 4, l_ist
        .long   0x25FE00B0, 4, l_asr0
        .long   0x25FE00B4, 4, l_asr1
        .long   0x25FE00B8, 4, l_aref
        .long   0x25FE00C4, 4, l_rsel
        .long   0x25FE00C8, 4, l_ver
        .long   0x25FE007C, 4, l_dsta
        .long   0x25FE0098, 4, l_t1md
        .long   0x25D00010, 2, l_edsr
        .long   0x25D00016, 2, l_modr
        .long   0x25F80000, 2, l_tvmd
        .long   0x25F80004, 2, l_tvstat
        .long   0x25F8000E, 2, l_ramctl
        .long   0x20100061, 1, l_smpcsr
        .long   0x20100063, 1, l_sf
        .long   0x25B00400, 2, l_mvol
        .long   0x25B00216, 2, l_mix16
        .long   0x25B00236, 2, l_mix17
        .long   0x25890008, 2, l_hirq
        .long   0x2589000C, 2, l_hmask
        .long   0x25890018, 2, l_cr1
        .long   0x2589001C, 2, l_cr2
        .long   0x26000348, 4, l_mask
        .long   0x26000324, 4, l_clock
        .long   0

        .align  2
s_title:        .asciz  "POST-BIOS STATE"
        .align  2
s_title2:       .asciz  "SLAVE STATE AFTER SSHON"
        .align  2
l_flag:         .asciz  "STARTED"
        .align  2
l_vdma0:        .asciz  "VDMA0"
        .align  2
l_vdma1:        .asciz  "VDMA1"
        .align  2
l_sr:           .asciz  "SR"
        .align  2
l_vbr:          .asciz  "VBR"
        .align  2
l_gbr:          .asciz  "GBR"
        .align  2
l_r15:          .asciz  "R15"
        .align  2
l_bcr1:         .asciz  "BCR1"
        .align  2
l_bcr2:         .asciz  "BCR2"
        .align  2
l_wcr:          .asciz  "WCR"
        .align  2
l_mcr:          .asciz  "MCR"
        .align  2
l_rtcsr:        .asciz  "RTCSR"
        .align  2
l_rtcor:        .asciz  "RTCOR"
        .align  2
l_ccr:          .asciz  "CCR"
        .align  2
l_icr:          .asciz  "ICR"
        .align  2
l_ipra:         .asciz  "IPRA"
        .align  2
l_iprb:         .asciz  "IPRB"
        .align  2
l_vcra:         .asciz  "VCRA"
        .align  2
l_vcrb:         .asciz  "VCRB"
        .align  2
l_vcrc:         .asciz  "VCRC"
        .align  2
l_vcrd:         .asciz  "VCRD"
        .align  2
l_vcrwdt:       .asciz  "VCRWDT"
        .align  2
l_tier:         .asciz  "TIER"
        .align  2
l_ftcsr:        .asciz  "FTCSR"
        .align  2
l_tcr:          .asciz  "TCR"
        .align  2
l_wtcsr:        .asciz  "WTCSR"
        .align  2
l_dmaor:        .asciz  "DMAOR"
        .align  2
l_chcr0:        .asciz  "CHCR0"
        .align  2
l_chcr1:        .asciz  "CHCR1"
        .align  2
l_vcrdiv:       .asciz  "VCRDIV"
        .align  2
l_ims:          .asciz  "SCUIMS"
        .align  2
l_ist:          .asciz  "SCUIST"
        .align  2
l_asr0:         .asciz  "ASR0"
        .align  2
l_asr1:         .asciz  "ASR1"
        .align  2
l_aref:         .asciz  "AREF"
        .align  2
l_rsel:         .asciz  "RSEL"
        .align  2
l_ver:          .asciz  "SCUVER"
        .align  2
l_dsta:         .asciz  "DSTA"
        .align  2
l_t1md:         .asciz  "T1MD"
        .align  2
l_edsr:         .asciz  "EDSR"
        .align  2
l_modr:         .asciz  "MODR"
        .align  2
l_tvmd:         .asciz  "TVMD"
        .align  2
l_tvstat:       .asciz  "TVSTAT"
        .align  2
l_ramctl:       .asciz  "RAMCTL"
        .align  2
l_smpcsr:       .asciz  "SMPCSR"
        .align  2
l_sf:           .asciz  "SMPCSF"
        .align  2
l_mvol:         .asciz  "MVOL"
        .align  2
l_mix16:        .asciz  "MIX16"
        .align  2
l_mix17:        .asciz  "MIX17"
        .align  2
l_hirq:         .asciz  "HIRQ"
        .align  2
l_hmask:        .asciz  "HMASK"
        .align  2
l_cr1:          .asciz  "CR1"
        .align  2
l_cr2:          .asciz  "CR2"
        .align  2
l_mask:         .asciz  "MASK348"
        .align  2
l_clock:        .asciz  "CLK324"
