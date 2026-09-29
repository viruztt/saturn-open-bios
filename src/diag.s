! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - compatibility diagnostics (debug builds only: make diag)
!
! Records how a game uses the BIOS, from behaviour only:
!   - a call counter per system call (the call table points at counting
!     wrappers that then jump to the real service),
!   - VBlank-IN interrupts that pass through the dispatcher, with the PC, PR
!     and SR the game was interrupted at and the last 8 PCs kept in a ring,
!   - how many times the slave SH-2 was started,
!   - a watchdog timer tick (interval mode, priority 15, every ~73 ms) started
!     at the hand-over, which samples the PC the same way even when the game
!     never enables VBlank interrupts.
! After DIAG_VBLANKS VBlank interrupts or DIAG_TICKS watchdog ticks (both
! about 30 s, so games reach their title music) it takes over the screen and shows the
! numbers: page 1 (calls), then about 5 s later page 2 (PCs and a snapshot
! of CD block, SCU, SMPC and VDP status). Variables live at 0x06000C80..
!
! A game that hangs with all interrupts masked never reaches either page.
! For that case there is a post-mortem page: if the machine is reset (Work
! RAM kept) after a game was started, the BIOS first shows the counters,
! the PC ring and the top 256 bytes of the game's master stack (from the
! IP.BIN header), whose return addresses show where the game was stuck.

        .section .text

        .ifdef  DIAG

        .global diag_irq
        .global diag_start_wdt
        .global diag_postmortem
        .global diag_start_swdt
        .global DIAG_SLAVE

        .equ    DIAG,       0x26000C80      ! variables, cache-through
        .equ    DIAG_COUNT, DIAG + 0x00     ! VBlank-IN interrupts seen
        .equ    DIAG_PC,    DIAG + 0x04     ! last interrupted PC
        .equ    DIAG_PR,    DIAG + 0x08     ! last interrupted PR
        .equ    DIAG_SR,    DIAG + 0x0C     ! last interrupted SR
        .equ    DIAG_SLAVE, DIAG + 0x10     ! slave SH-2 starts
        .equ    DIAG_RINGI, DIAG + 0x14     ! next PC ring slot (0-7)
        .equ    DIAG_TICKS, DIAG + 0x18     ! watchdog ticks
        .equ    DIAG_MAGIC, DIAG + 0x1C     ! "DIAG" once a game was started
        .equ    MAGIC,      0x44494147
        .equ    DIAG_SLV,   0x26000EF0      ! slave samples: PC, PR, SR, ticks
                                            ! (spare CD variable space)
        .equ    DIAG_TICKLIM, 410           ! ~30 s of 73 ms ticks
        .equ    WDT_VECTOR, 0x68            ! as set in VCRWDT by cpu_vectors
        .equ    DIAG_CALLS, DIAG + 0x20     ! one longword per system call
        .equ    DIAG_RING,  DIAG + 0x60     ! last 8 VBlank PCs
        .equ    DIAG_VBLANKS, 1800          ! about 30 s at 60 Hz

! DIAGWRAP n, service: count call n, set the watchdog priority in IPRA
! again, then continue in the service
        .macro  DIAGWRAP n, service
        .global diag_w_\service
        .align  2
diag_w_\service:
        mov.l   .Lc\@, r1
        mov.l   @r1, r0
        add     #1, r0
        mov.l   r0, @r1
        mov.l   .Li\@, r1              ! games may clear IPRA (Virtua Cop
        mov.w   @r1, r0                 ! does): give the watchdog tick its
        or      #0xF0, r0               ! priority back on every call
        mov.w   r0, @r1
        mov.l   .Lf\@, r0
        jmp     @r0
        nop
        .align  2
.Lc\@:  .long   DIAG_CALLS + \n * 4
.Li\@:  .long   0xFFFFFEE2
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

! Calls without a counter slot: straight through.
        .macro  DIAGPASS service
        .global diag_w_\service
        .align  2
diag_w_\service:
        mov.l   .Lf\@, r0
        jmp     @r0
        nop
        .align  2
.Lf\@:  .long   \service
        .endm

        DIAGPASS sc_loadcd_boot
        DIAGPASS sc_loadcd_read

! diag_start_swdt: on the slave, from slave_start: the slave's own
! watchdog in interval mode at priority 15, vector 0x68 in the slave table
! at 0x06000400, sampling into DIAG_SLV (shown on the post-mortem page).
! Clobbers r0, r1.
        .align  2
diag_start_swdt:
        mov.l   c_sw_vec, r1
        mov.l   p_diag_swdt, r0
        mov.l   r0, @r1
        mov.l   c_sw_ipra, r1
        mov.w   @r1, r0
        or      #0xF0, r0
        mov.w   r0, @r1
        mov.l   c_sw_wtcsr, r1
        mov.w   c_sw_cnt0, r0
        mov.w   r0, @r1
        mov.w   c_sw_go, r0
        rts
        mov.w   r0, @r1

! diag_swdt: slave watchdog tick: clear OVF, keep PC/PR/SR, count.
        .align  2
diag_swdt:
        mov.l   r0, @-r15
        mov.l   r1, @-r15
        mov.l   r2, @-r15               ! stack: r2 r1 r0 PC SR
        mov.l   c_sw_wtcsr, r1
        mov.b   @r1, r0
        and     #0x7F, r0
        mov.w   c_sw_key, r2
        or      r2, r0
        mov.w   r0, @r1
        mov.l   c_sw_slv, r1
        mov.l   @(12, r15), r0          ! PC
        mov.l   r0, @r1
        sts     pr, r0
        mov.l   r0, @(4, r1)
        mov.l   @(16, r15), r0          ! SR
        mov.l   r0, @(8, r1)
        mov.l   @(12, r1), r0
        add     #1, r0
        mov.l   r0, @(12, r1)
        mov.l   @r15+, r2
        mov.l   @r15+, r1
        mov.l   @r15+, r0
        rte
        nop

        .align  2
c_sw_vec:       .long   0x06000400 + WDT_VECTOR * 4
p_diag_swdt:    .long   diag_swdt
c_sw_ipra:      .long   0xFFFFFEE2
c_sw_wtcsr:     .long   0xFFFFFE80
c_sw_slv:       .long   DIAG_SLV
c_sw_cnt0:      .word   0x5A00
c_sw_go:        .word   0xA53F
c_sw_key:       .word   0xA500

! diag_postmortem: called at power-on/reset right after the console is up,
! before anything touches Work RAM. If a game had been started, show the
! post-mortem page (row 1: VBlanks, ticks, last sampled PC and PR; rows 2-3:
! PC ring; row 4: slave starts, slave entry and stack; rows 5-8: call
! counters in table order; row 9: the slave's last watchdog sample (PC,
! PR, SR) and tick count; rows 10-13: the 64 bytes at 0x060C8000 (Virtua
! Cop's master/slave variables; row 0 shows the IP.BIN master stack);
! rows 15-26: the 192 bytes below
! 0x060C8000, where Virtua Cop's main program puts its stack; 4 longwords
! per row, lowest address first) and halt.
! The marker is cleared first, so the next reset boots normally. Uses no
! stack (the game's may be where ours would go).
        .align  2
diag_postmortem:
        mov.l   c_pm_magic_at, r1
        mov.l   @r1, r0
        mov.l   c_pm_magic, r2
        cmp/eq  r2, r0
        bt      1f
        rts
        nop
1:      mov     #0, r0
        mov.l   r0, @r1
        mova    t_pm, r0
        mov     r0, r4
        mov     #2, r5
        mov.l   p_pm_puts, r0
        jsr     @r0
        mov     #0, r6
        mov.l   c_pm_diag, r8           ! row 1: VBlanks seen, watchdog ticks
        mov.l   @r8, r4
        mov     #2, r5
        mov.l   p_pm_puthex, r0
        jsr     @r0
        mov     #1, r6
        mov.l   @(24, r8), r4
        mov     #11, r5
        mov.l   p_pm_puthex, r0
        jsr     @r0
        mov     #1, r6
        mov.l   @(4, r8), r4            ! last sampled PC and PR
        mov     #20, r5
        mov.l   p_pm_puthex, r0
        jsr     @r0
        mov     #1, r6
        mov.l   @(8, r8), r4
        mov     #29, r5
        mov.l   p_pm_puthex, r0
        jsr     @r0
        mov     #1, r6
        mov.l   c_pm_ring, r8           ! rows 2-3: PC ring (8)
        mov     #8, r9
        mov     #2, r10
        bsr     pm_dump
        nop
        mov.l   c_pm_diag, r8           ! row 4: slave starts, slave entry
        mov.l   @(16, r8), r4           ! and stack as the game left them
        mov     #2, r5
        mov.l   p_pm_puthex, r0
        jsr     @r0
        mov     #4, r6
        mov.l   c_pm_sentry, r1
        mov.l   @r1, r4
        mov     #11, r5
        mov.l   p_pm_puthex, r0
        jsr     @r0
        mov     #4, r6
        mov.l   c_pm_sstack, r1
        mov.l   @r1, r4
        mov     #20, r5
        mov.l   p_pm_puthex, r0
        jsr     @r0
        mov     #4, r6
        mov.l   c_pm_calls, r8          ! rows 5-8: call counters (16)
        mov     #16, r9
        mov     #5, r10
        bsr     pm_dump
        nop
        mov.l   c_pm_slv, r8            ! row 9: slave PC, PR, SR, ticks
        mov     #4, r9
        mov     #9, r10
        bsr     pm_dump
        nop
        mov.l   c_pm_ip_sp, r1          ! row 0: the IP.BIN master stack
        mov.l   @r1, r8                 ! (0x06002000 if the header leaves
        tst     r8, r8                  ! it 0)
        bf      2f
        mov.l   c_pm_def_sp, r8
2:      mov     r8, r4
        mov     #25, r5
        mov.l   p_pm_puthex, r0
        jsr     @r0
        mov     #0, r6
        mov.l   c_pm_comm, r8           ! rows 10-13: 64 bytes at 0x060C8000,
        mov     #16, r9                 ! Virtua Cop's master/slave variables
        mov     #10, r10
        bsr     pm_dump
        nop
        mov.l   c_pm_sp2, r8            ! row 14: second window, the stack
        mov     r8, r4                  ! top Virtua Cop's main program sets
        mov     #25, r5                 ! for itself (0x060C8000); rows
        mov.l   p_pm_puthex, r0         ! 15-26: the 192 bytes below it
        jsr     @r0
        mov     #14, r6
        mov.w   c_pm_192, r0
        sub     r0, r8
        mov     #48, r9
        mov     #15, r10
        bsr     pm_dump
        nop
3:      bra     3b
        nop

! pm_dump: r8 = address, r9 = longword count, r10 = first row; 4 per row.
! PR is kept in r14 (no stack).
pm_dump:
        sts     pr, r14
        mov     #2, r11
1:      mov.l   @r8+, r4
        mov     r11, r5
        mov.l   p_pm_puthex, r0
        jsr     @r0
        mov     r10, r6
        add     #9, r11
        mov     #38, r0
        cmp/hs  r0, r11
        bf      2f
        mov     #2, r11
        add     #1, r10
2:      dt      r9
        bf      1b
        lds     r14, pr
        rts
        nop

        .align  2
c_pm_magic_at:  .long   DIAG_MAGIC
c_pm_magic:     .long   MAGIC
c_pm_diag:      .long   DIAG
c_pm_ring:      .long   DIAG_RING
c_pm_calls:     .long   DIAG_CALLS
c_pm_ip_sp:     .long   0x260020E8      ! IP.BIN master stack field
c_pm_def_sp:    .long   0x06002000
p_pm_puts:      .long   con_puts
c_pm_sp2:       .long   0x060C8000
c_pm_comm:      .long   0x260C8000
c_pm_slv:       .long   DIAG_SLV
c_pm_sentry:    .long   0x26000250
c_pm_sstack:    .long   0x260002AC
p_pm_puthex:    .long   con_puthex
c_pm_192:       .word   192
        .align  2
t_pm:           .asciz  "Post-mortem  stack top"
        .align  2

! diag_irq: called by the SCU dispatcher with r0 = vector, r1 = the
! interrupted PC, r2 = SR, r3 = PR. May clobber r0-r3 only. Counts the
! vector; for VBlank-IN also samples the PC and shows the report once
! enough VBlanks have been seen.
        .align  2
diag_irq:
        cmp/eq  #0x40, r0               ! VBlank-IN only
        bf      9f
        sts.l   pr, @-r15
        bsr     sample
        nop
        lds.l   @r15+, pr
        mov.l   c_diag, r0
        mov.l   @r0, r1
        add     #1, r1
        mov.l   r1, @r0
        mov.w   c_limit, r2
        cmp/hs  r2, r1
        bt      report
9:      rts
        nop

! sample: r1 = PC, r2 = SR, r3 = PR of the interrupted code: keep them and
! add the PC to the ring. Clobbers r0-r3.
sample:
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
        rts
        mov.l   r2, @(20, r0)

! diag_start_wdt: start the watchdog in interval mode (clock / 8192, about
! 73 ms per overflow at 28.6 MHz) at interrupt priority 15, with its master
! vector pointing at diag_wdt. Called at the hand-over. Clobbers r0, r1.
diag_start_wdt:
        mov.l   c_magic_at, r1          ! a game is starting: a reset from now
        mov.l   c_magic, r0             ! on shows the post-mortem page
        mov.l   r0, @r1
        mov.l   c_wdt_vec, r1           ! VBR table entry for vector 0x68
        mov.l   p_diag_wdt, r0
        mov.l   r0, @r1
        mov.l   c_ipra, r1              ! IPRA: WDT priority 15
        mov.w   @r1, r0
        or      #0xF0, r0
        mov.w   r0, @r1
        mov.l   c_wtcsr, r1
        mov.w   c_wtcnt0, r0            ! WTCNT = 0
        mov.w   r0, @r1
        mov.w   c_wtcsr_go, r0          ! interval mode, timer on, clock/8192
        rts
        mov.w   r0, @r1

! diag_wdt: watchdog interval interrupt. Clears the overflow flag, samples
! the interrupted PC/SR/PR, counts ticks, and shows the report after
! DIAG_TICKLIM ticks.
        .align  2
diag_wdt:
        mov.l   r0, @-r15
        mov.l   r1, @-r15
        mov.l   r2, @-r15
        mov.l   r3, @-r15
        sts.l   pr, @-r15               ! stack: pr r3 r2 r1 r0 PC SR
        mov.l   c_wtcsr, r1             ! clear OVF: write back without bit 7
        mov.b   @r1, r0
        and     #0x7F, r0
        mov.w   c_wtcsr_key, r2
        or      r2, r0
        mov.w   r0, @r1
        mov.l   @(20, r15), r1          ! PC
        mov.l   @(24, r15), r2          ! SR
        mov.l   @r15, r3                ! PR of the interrupted code
        bsr     sample
        nop
        mov.l   c_diag, r0
        mov.l   @(24, r0), r1           ! ticks
        add     #1, r1
        mov.l   r1, @(24, r0)
        mov.w   c_ticklim, r2
        cmp/hs  r2, r1
        bt      report
        lds.l   @r15+, pr
        mov.l   @r15+, r3
        mov.l   @r15+, r2
        mov.l   @r15+, r1
        mov.l   @r15+, r0
        rte
        nop

        .align  2
c_magic_at:     .long   DIAG_MAGIC
c_magic:        .long   MAGIC
c_wdt_vec:      .long   0x06000000 + WDT_VECTOR * 4
p_diag_wdt:     .long   diag_wdt
c_ipra:         .long   0xFFFFFEE2
c_wtcsr:        .long   0xFFFFFE80
c_wtcnt0:       .word   0x5A00
c_wtcsr_go:     .word   0xA53F          ! TME, interval, CKS = 7
c_wtcsr_key:    .word   0xA500
c_ticklim:      .word   DIAG_TICKLIM

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
        mova    cdq_tab, r0             ! ask the CD block: status (status,
        mov     r0, r8                  ! track, index, FAD), CD device
6:      mov.l   @r8+, r4                ! connection, buffer size; each row
        tst     r4, r4                  ! shows CR1:CR2 and CR3:CR4
        bt      8f
        mov     #2, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     r9, r6
        mov.l   @r8+, r10               ! CR1 of the command
        mov.l   c_p2_hirq, r1
        mov.w   c_p2_notcmok, r0
        mov.w   r0, @r1
        mov.l   c_p2_cr1, r2
        mov     r10, r0
        mov.w   r0, @r2
        mov     #0, r0
        mov.w   r0, @(4, r2)
        mov.w   r0, @(8, r2)
        mov.w   r0, @(12, r2)
        mov.l   c_p2_wait, r3
7:      mov.w   @r1, r0
        tst     #1, r0
        bf      9f
        dt      r3
        bf      7b
9:      mov.l   c_p2_cr1, r2
        mov.w   @r2, r4
        shll16  r4
        mov.w   @(4, r2), r0
        extu.w  r0, r0
        or      r0, r4
        mov     #16, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     r9, r6
        mov.l   c_p2_cr1, r2
        mov.w   @(8, r2), r0
        mov     r0, r4
        shll16  r4
        mov.w   @(12, r2), r0
        extu.w  r0, r0
        or      r0, r4
        mov     #25, r5
        mov.l   p_con_puthex, r0
        jsr     @r0
        mov     r9, r6
        bra     6b
        add     #1, r9
8:      add     #1, r9                  ! hardware snapshot: (label, address,
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
c_p2_notcmok:   .word   0xFFFE
        .align  2
c_p2_hirq:      .long   0x25890008
c_p2_cr1:       .long   0x25890018
c_p2_wait:      .long   0x00100000

        .align  2
cdq_tab:
        .long   s_q_stat, 0x0000        ! Get CD Status
        .long   s_q_conn, 0x3100        ! Get CD Device Connection
        .long   s_q_buf,  0x5000        ! Get Buffer Size
        .long   0

        .align  2
snap:
        .long   s_hirq,  0x25890008, 0
        .long   s_hmask, 0x2589000C, 0
        .long   s_ist,   0x25FE00A4, 1
        .long   s_sf,    0x20100063, 2
        .long   s_tvstat, 0x25F80004, 0
        .long   s_edsr,  0x25D00010, 0
        .long   s_shadow, 0x26000348, 1
        .long   s_sentry, 0x26000250, 1
        .long   s_sstack, 0x260002AC, 1
        .long   s_mvol,  0x25B00400, 0
        .long   s_mix16, 0x25B00216, 0
        .long   s_mix17, 0x25B00236, 0
        .long   s_rbp,   0x25B00402, 0
        .long   s_mpro,  0x25B00800, 1
        .long   0

        .align  2
rows:
        .long   r_vbl,  DIAG_COUNT
        .long   r_pc,   DIAG_PC
        .long   r_pr,   DIAG_PR
        .long   r_sr,   DIAG_SR
        .long   r_slv,  DIAG_SLAVE
        .long   r_tick, DIAG_TICKS
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
s_q_stat:       .asciz  "CD status"
        .align  2
s_q_conn:       .asciz  "CD dev conn"
        .align  2
s_q_buf:        .asciz  "CD buffer"
        .align  2
s_mvol:         .asciz  "SCSP MEM4MB/MVOL"
        .align  2
s_mix16:        .asciz  "SCSP slot16 mix"
        .align  2
s_mix17:        .asciz  "SCSP slot17 mix"
        .align  2
s_rbp:          .asciz  "SCSP RBL/RBP"
        .align  2
s_mpro:         .asciz  "SCSP DSP step 0"
        .align  2
s_hmask:        .asciz  "CD HIRQ mask"
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
r_tick:         .asciz  "Watchdog ticks"
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
