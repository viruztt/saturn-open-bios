! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - backup RAM manager and control pad input (clean-room)
!
! menu_main(r4 = 1 if a disc is ready to boot, 0 if not, 2 if there is no
! disc: then the drive is polled and the BIOS starts over once one is
! ready): lists the saves on
! the internal backup RAM and, if one is plugged in, the backup RAM
! cartridge, and lets the user delete a save, copy it to the other device
! or format a device (each asks for confirmation). Start leaves: back to
! the caller when a disc is ready, otherwise the BIOS starts over (to retry
! the disc). It works through the BIOS's own backup RAM library, with its
! work area in Low Work RAM, so a game already loaded is not touched.
! Preserves r8-r14 (C convention).
!
! pad_read: SMPC INTBACK peripheral read of control port 1; r0 = buttons
! held (1 = pressed, masks PAD_*), 0 if no standard pad is connected.

        .section .text
        .global menu_main
        .global pad_read

        ! Pad buttons (port 1 data bytes 1 and 2, inverted)
        .equ    PAD_RIGHT,  0x8000
        .equ    PAD_LEFT,   0x4000
        .equ    PAD_DOWN,   0x2000
        .equ    PAD_UP,     0x1000
        .equ    PAD_START,  0x0800
        .equ    PAD_A,      0x0400
        .equ    PAD_C,      0x0200
        .equ    PAD_B,      0x0100
        .equ    PAD_R,      0x0080
        .equ    PAD_X,      0x0040
        .equ    PAD_Y,      0x0020
        .equ    PAD_L,      0x0008

        .equ    SMPC_IREG0, 0x20100001
        .equ    SMPC_COMREG, 0x2010001F
        .equ    SMPC_OREG0, 0x20100021
        .equ    SMPC_SF,    0x20100063

        ! Work area in Low Work RAM (cache-through)
        .equ    M_LIB,      0x20200000      ! BUP library area (unused)
        .equ    M_WORK,     0x20204000      ! BUP work area, 8 KB
        .equ    M_CONF,     0x20206000      ! BupConfig[3]
        .equ    M_STAT,     0x20206020      ! BupStat
        .equ    M_NUM,      0x20206040      ! number text buffer
        .equ    M_V,        0x20206080      ! variables, see V_*
        .equ    M_PADRAW,   0x202060C0      ! pad_read: last OREG0..3
        .equ    M_DIR,      0x20208000      ! BupDir[MAXDIR], 36 bytes each
        .equ    M_BUF,      0x20210000      ! copy buffer
        .equ    MAXDIR,     64
        .equ    BUFMAX,     0x000F0000      ! (up to 0x202FFFFF)

        ! Variables (offsets from M_V, longwords)
        .equ    V_DEV,      0               ! device shown (0 or 1)
        .equ    V_SEL,      4               ! selected entry
        .equ    V_TOP,      8               ! first entry shown
        .equ    V_COUNT,    12              ! entries in M_DIR
        .equ    V_PREV,     16              ! pad state last frame
        .equ    V_PEND,     20              ! pending action (0, ACT_*)
        .equ    V_CART,     24              ! 1 if a cartridge is present
        .equ    V_DISC,     28              ! 1 if a disc is ready to boot
        .equ    V_SCR,      32              ! (MENUSCRIPT) next script entry
        .equ    V_SCRN,     36              ! (MENUSCRIPT) frames left in it
        .equ    V_POLL,     40              ! frames since the last drive poll

        .equ    DEV_ROW,    3
        .equ    LIST_ROW,   5               ! first list row
        .equ    LIST_ROWS,  16
        .equ    MSG_ROW,    22

        .equ    ACT_DELETE, 1
        .equ    ACT_COPY,   2
        .equ    ACT_FORMAT, 3

        ! BUP library table offsets in the work area
        .equ    F_FORMAT,   0x08
        .equ    F_STAT,     0x0C
        .equ    F_WRITE,    0x10
        .equ    F_READ,     0x14
        .equ    F_DELETE,   0x18
        .equ    F_DIR,      0x1C

! BUPCALL off: call the BUP library function at work area + off
        .macro  BUPCALL off
        mov.l   .Lw\@, r0
        bra     .Lb\@
        mov.l   @(\off, r0), r0
        .align  2
.Lw\@:     .long   M_WORK
.Lb\@:  jsr     @r0
        nop
        .endm

! PUTS str, col, row (row may be a register via PUTSR)
        .macro  PUTS str, col, row
        mov.l   .Ls\@, r4
        mov     #\col, r5
        mov.l   .Lp\@, r0
        jsr     @r0
        mov     #\row, r6
        bra     .Le\@
        nop
        .align  2
.Ls\@:  .long   \str
.Lp\@:  .long   con_puts
.Le\@:
        .endm

! ---- control pad ------------------------------------------------------------

! pad_read: INTBACK with peripheral data only (IREG0 0, IREG1 PEN + OPE,
! 15-byte port mode) issued right after VBlank-out, then a break. Port 1
! must report a directly connected device (status 0xF1, ID 0x0x or 0x1x).
! Takes up to one frame. Clobbers r1-r3.
        .align  2
pad_read:
        mov.l   c_pr_tvstat, r1         ! issue it just after VBlank-out, as
        mov.l   c_pad_wait, r2          ! the SMPC firmware drops or delays a
5:      mov.w   @r1, r0                 ! request made at VBlank-in: wait
        tst     #8, r0                  ! for a VBlank (or be in one) ...
        bf      6f
        dt      r2
        bf      5b
6:      mov.l   c_pad_wait, r2
7:      mov.w   @r1, r0                 ! ... then for its end
        tst     #8, r0
        bt      9f
        dt      r2
        bf      7b
9:      mov.l   c_sf, r1
        mov.l   c_pad_wait, r2
1:      mov.b   @r1, r0                 ! SMPC idle?
        tst     #1, r0
        bt      2f
        dt      r2
        bf      1b
        bra     10f                     ! (SMPC stayed busy)
        mov     #1, r0
2:      mov.l   c_ireg0, r3
        mov     #0, r0
        mov.b   r0, @r3                 ! IREG0: no status
        mov     #0x0A, r0
        mov.b   r0, @(2, r3)            ! IREG1: peripheral data, no wait
        mov     #0xF0, r0
        mov.b   r0, @(4, r3)            ! IREG2: 0xF0
        mov     #1, r0
        mov.b   r0, @r1                 ! SF = 1
        mov.l   c_comreg, r3
        mov     #0x10, r0
        mov.b   r0, @r3                 ! INTBACK
        mov.l   c_pad_wait, r2
3:      mov.b   @r1, r0
        tst     #1, r0
        bt      4f
        dt      r2
        bf      3b
        mov     #2, r0                  ! (no answer)
10:     mov.l   c_pad_err, r2           ! raw = EEEEEE01/02 on a timeout
        or      r0, r2
        mov.l   c_pad_raw, r1
        mov.l   r2, @r1
        bra     8f
        mov     #0, r2
4:      mov.l   c_oreg0, r3             ! raw = OREG0..3 (shown by the menu)
        mov.b   @r3, r0
        extu.b  r0, r2
        mov.b   @(2, r3), r0
        extu.b  r0, r0
        shll8   r2
        or      r0, r2
        mov.b   @(4, r3), r0
        extu.b  r0, r0
        shll8   r2
        or      r0, r2
        mov.b   @(6, r3), r0
        extu.b  r0, r0
        shll8   r2
        or      r0, r2
        mov.l   c_pad_raw, r1
        mov.l   r2, @r1
        mov.b   @r3, r0                 ! port 1 status (sign-extended, as
        mov     #0, r2                  ! is the immediate below)
        cmp/eq  #0xF1, r0
        bf      8f
        mov.b   @(2, r3), r0            ! peripheral ID: pad, 3D pad, wheel
        and     #0xE0, r0               ! or stick (0x0x/0x1x), buttons first
        tst     r0, r0
        bf      8f
        mov.b   @(4, r3), r0            ! buttons (active low)
        extu.b  r0, r2
        shll8   r2
        mov.b   @(6, r3), r0
        extu.b  r0, r0
        or      r0, r2
        not     r2, r2
        extu.w  r2, r2
8:      mov.l   c_ireg0, r3             ! break the INTBACK
        mov     #0x40, r0
        mov.b   r0, @r3
        rts
        mov     r2, r0

        .align  2
c_sf:           .long   SMPC_SF
c_ireg0:        .long   SMPC_IREG0
c_comreg:       .long   SMPC_COMREG
c_oreg0:        .long   SMPC_OREG0
c_pad_wait:     .long   0x00100000
c_pr_tvstat:    .long   0x25F80004
c_pad_err:      .long   0xEEEEEE00
c_pad_raw:      .long   M_PADRAW

! ---- the manager -------------------------------------------------------------

        .align  2
menu_main:
        sts.l   pr, @-r15
        mov.l   r14, @-r15
        mov.l   r13, @-r15
        mov.l   r12, @-r15
        mov.l   r11, @-r15
        mov.l   r10, @-r15
        mov.l   r9, @-r15
        mov.l   r8, @-r15
        mov.l   c_m_v, r14              ! r14 = variables
        mov.l   r4, @(V_DISC, r14)
        mov     #0, r0
        mov.l   r0, @(V_DEV, r14)
        mov.l   r0, @(V_SEL, r14)
        mov.l   r0, @(V_TOP, r14)
        mov.l   r0, @(V_PEND, r14)
        mov.l   r0, @(V_POLL, r14)
        .ifdef  MENUSCRIPT
        mov.l   r0, @(V_SCR, r14)
        .endif
        mov.l   c_m_allbits, r0         ! ignore buttons already held
        mov.l   r0, @(V_PREV, r14)
        bsr     scan_devs
        nop
        mov.l   p_vdp2_init_m, r0       ! fresh screen
        jsr     @r0
        nop
        bsr     draw_static
        nop
        bsr     refresh
        nop

! main loop: one pad read per frame; r13 = newly pressed buttons
loop:
        mov.l   p_vbl_wait, r0
        jsr     @r0
        nop
        mov.l   @(V_DISC, r14), r0      ! no disc: poll the drive about
        cmp/eq  #2, r0                  ! twice a second, start over when
        bf      30f                     ! a disc is in and spun up
        mov.l   @(V_POLL, r14), r0
        add     #1, r0
        mov.l   r0, @(V_POLL, r14)
        mov     #30, r1
        cmp/hs  r1, r0
        bf      30f
        mov     #0, r0
        mov.l   r0, @(V_POLL, r14)
        mov.l   p_cd_status_m, r0
        jsr     @r0
        nop
        cmp/eq  #1, r0                  ! PAUSE, STANDBY or PLAY
        bt      31f
        cmp/eq  #2, r0
        bt      31f
        cmp/eq  #3, r0
        bf      30f
31:     mov.l   p_start, r0
        jmp     @r0
        nop
30:
        bsr     pad_read
        nop
        mov.l   r0, @-r15
        .ifdef  MENUSCRIPT              ! (test builds: add scripted buttons)
        bsr     script_pad
        nop
        mov.l   @r15, r1
        or      r0, r1
        mov.l   r1, @r15
        .endif
        mov.l   @r15+, r0
        mov.l   @(V_PREV, r14), r1
        mov.l   r0, @(V_PREV, r14)
        not     r1, r1
        and     r0, r1
        mov     r1, r13                 ! r13 = pressed this frame
        tst     r13, r13
        bt      loop
        mov.l   @(V_PEND, r14), r0
        tst     r0, r0
        bt      10f
        mov.w   c_pad_a, r1             ! a question is open: A = yes
        tst     r1, r13
        bt      1f
        bra     do_action
        nop
1:      mov.w   c_pad_b, r1             ! B = no
        tst     r1, r13
        bt      loop
        mov     #0, r0
        mov.l   r0, @(V_PEND, r14)
        bsr     message
        mov     #0, r4
        bra     loop
        nop
10:     mov.w   c_pad_up, r1
        tst     r1, r13
        bt      11f
        mov.l   @(V_SEL, r14), r0       ! up
        tst     r0, r0
        bt      loop
        add     #-1, r0
        mov.l   r0, @(V_SEL, r14)
        bra     moved
        nop
11:     mov.w   c_pad_down, r1
        tst     r1, r13
        bt      12f
        mov.l   @(V_SEL, r14), r0       ! down
        add     #1, r0
        mov.l   @(V_COUNT, r14), r1
        cmp/hs  r1, r0
        bt      loop
        mov.l   r0, @(V_SEL, r14)
        bra     moved
        nop
12:     mov.w   c_pad_switch, r1        ! left/right/L/R: other device
        tst     r1, r13
        bt      13f
        mov.l   @(V_CART, r14), r0
        tst     r0, r0
        bf      20f
        bsr     scan_devs               ! none seen yet: look again (it may
        nop                             ! have been plugged in since)
        mov.l   @(V_CART, r14), r0
        tst     r0, r0
        bf      20f
        mov.l   p_s_nocart, r4
        bsr     message
        nop
        bra     loop
        nop
20:     mov.l   @(V_DEV, r14), r0
        xor     #1, r0
        mov.l   r0, @(V_DEV, r14)
        mov     #0, r0
        mov.l   r0, @(V_SEL, r14)
        mov.l   r0, @(V_TOP, r14)
        bsr     message
        mov     #0, r4
        bsr     refresh
        nop
        bra     loop
        nop
13:     mov.w   c_pad_a, r1             ! A: delete the selected save
        tst     r1, r13
        bt      14f
        mov.l   @(V_COUNT, r14), r0
        tst     r0, r0
        bt      loop
        mov     #ACT_DELETE, r0
        mov.l   r0, @(V_PEND, r14)
        mov.l   p_q_delete, r4
        bsr     message
        nop
        bra     loop
        nop
22:     bra     loop
        nop
14:     mov.w   c_pad_c, r1             ! C: copy it to the other device
        tst     r1, r13
        bt      15f
        mov.l   @(V_COUNT, r14), r0
        tst     r0, r0
        bt      22b
        mov.l   @(V_CART, r14), r0
        tst     r0, r0
        bt      22b
        mov     #ACT_COPY, r0
        mov.l   r0, @(V_PEND, r14)
        mov.l   p_q_copy, r4
        bsr     message
        nop
        bra     loop
        nop
15:     mov     #PAD_Y, r1              ! Y: format the device
        tst     r1, r13
        bt      16f
        mov     #ACT_FORMAT, r0
        mov.l   r0, @(V_PEND, r14)
        mov.l   p_q_format, r4
        bsr     message
        nop
        bra     loop
        nop
16:     mov     #PAD_X, r1              ! X: system settings page, then
        tst     r1, r13                 ! back to a freshly drawn manager
        bt      23f
        mov.l   p_settings, r0
        jsr     @r0
        nop
        mov.l   c_m_allbits, r0
        mov.l   r0, @(V_PREV, r14)
        mov.l   p_vdp2_init_m, r0
        jsr     @r0
        nop
        bsr     draw_static
        nop
        bsr     refresh
        nop
        bra     loop
        nop
23:     mov.w   c_pad_start, r1         ! Start: leave
        tst     r1, r13
        bf      19f
        bra     loop
        nop
19:
        mov.l   @(V_DISC, r14), r0
        cmp/eq  #2, r0
        bf      18f
        mov.l   p_s_nodisc, r4          ! no disc: say so, keep polling
        bsr     message
        nop
        bra     loop
        nop
18:     tst     r0, r0
        bf      17f
        mov.l   p_start, r0             ! disc failed: start over
        jmp     @r0
        nop
17:     mov.l   @r15+, r8               ! disc ready: back to the boot
        mov.l   @r15+, r9
        mov.l   @r15+, r10
        mov.l   @r15+, r11
        mov.l   @r15+, r12
        mov.l   @r15+, r13
        mov.l   @r15+, r14
        lds.l   @r15+, pr
        rts
        nop

        .ifdef  MENUSCRIPT
! script_pad: r0 = buttons from the script (frames, buttons) pairs, ending
! with 0 frames (then nothing is pressed any more).
! Also used by the settings page (it keeps its own r14).
        .align  2
        .global script_pad
script_pad:
        mov.l   r14, @-r15
        mov.l   p_script_v, r14
        mov.l   @(V_SCR, r14), r1
        tst     r1, r1
        bf      1f
        mov.l   p_script, r1
        mov.l   r1, @(V_SCR, r14)
        mov.w   @r1, r0
        mov.l   r0, @(V_SCRN, r14)
1:      mov.w   @r1, r0
        tst     r0, r0
        bt      9f
        mov.l   @(V_SCRN, r14), r0
        dt      r0
        bf/s    2f
        mov.l   r0, @(V_SCRN, r14)
        add     #4, r1                  ! next entry
        mov.l   r1, @(V_SCR, r14)
        mov.w   @r1, r0
        mov.l   r0, @(V_SCRN, r14)
        add     #-4, r1
2:      mov.w   @(2, r1), r0
        extu.w  r0, r0
        rts
        mov.l   @r15+, r14
9:      mov     #0, r0
        rts
        mov.l   @r15+, r14
        .align  2
p_script:       .long   script
p_script_v:     .long   M_V

        .endif

! scan_devs: (re)initialise the backup RAM library; V_CART = 1 if it found
! a cartridge (device 1 is then unit 2).
        .align  2
scan_devs:
        sts.l   pr, @-r15
        mov.l   c_m_lib, r4
        mov.l   c_m_work2, r5
        mov.l   c_m_conf, r6
        mov.l   p_bup_init, r0
        jsr     @r0
        nop
        mov.l   c_m_conf, r1
        mov.w   @(4, r1), r0
        cmp/eq  #2, r0
        movt    r0
        mov.l   r0, @(V_CART, r14)
        lds.l   @r15+, pr
        rts
        nop

! moved: keep the selection visible, redraw the list
moved:
        mov.l   @(V_SEL, r14), r0
        mov.l   @(V_TOP, r14), r1
        cmp/hs  r1, r0                  ! sel < top: top = sel
        bt      1f
        bra     2f
        mov.l   r0, @(V_TOP, r14)
1:      mov     r1, r2                  ! sel >= top + rows: top = sel - rows + 1
        add     #LIST_ROWS, r2
        cmp/hs  r2, r0
        bf      2f
        add     #-LIST_ROWS + 1, r0
        mov.l   r0, @(V_TOP, r14)
2:      bsr     draw_list
        nop
        bra     loop
        nop

        .align  2
c_m_v:          .long   M_V
c_m_lib:        .long   M_LIB
c_m_work2:      .long   M_WORK
c_m_conf:       .long   M_CONF
c_m_allbits:    .long   0x0000FFFF
p_bup_init:     .long   bup_init
p_vdp2_init_m:  .long   vdp2_init
p_vbl_wait:     .long   vbl_wait
p_cd_status_m:  .long   cd_status
p_s_nodisc:     .long   s_nodisc
p_s_nocart:     .long   s_nocart
p_start:        .long   _start
p_settings:     .long   settings_main
p_q_delete:     .long   s_q_delete
p_q_copy:       .long   s_q_copy
p_q_format:     .long   s_q_format
c_pad_a:        .word   PAD_A
c_pad_b:        .word   PAD_B
c_pad_c:        .word   PAD_C
c_pad_up:       .word   PAD_UP
c_pad_down:     .word   PAD_DOWN
c_pad_start:    .word   PAD_START
c_pad_switch:   .word   PAD_LEFT | PAD_RIGHT | PAD_L | PAD_R

! do_action: carry out the pending action (A pressed on the question), show
! the outcome, refresh the list and continue the loop.
        .align  2
do_action:
        mov.l   @(V_PEND, r14), r12     ! r12 = action
        mov     #0, r0
        mov.l   r0, @(V_PEND, r14)
        mov.l   @(V_SEL, r14), r0       ! r11 = selected entry
        mov     #36, r1
        mulu.w  r0, r1
        sts     macl, r11
        mov.l   c_m_dir, r0
        add     r0, r11
        mov.l   @(V_DEV, r14), r10      ! r10 = device
        mov     r12, r0
        cmp/eq  #ACT_DELETE, r0
        bf      2f
        mov     r10, r4                 ! Delete(device, name)
        mov     r11, r5
        BUPCALL F_DELETE
        tst     r0, r0
        bf      8f
        mov.l   p_s_deleted, r4
        bra     9f
        nop
2:      cmp/eq  #ACT_COPY, r0
        bf      4f
        mov     r11, r0                 ! data size must fit the buffer
        mov.l   @(28, r0), r1
        mov.l   c_bufmax, r2
        cmp/hi  r2, r1
        bf      3f
        mov.l   p_s_toolarge, r4
        bra     9f
        nop
3:      mov     r10, r4                 ! Read(device, name, buffer)
        mov     r11, r5
        mov.l   c_m_buf, r6
        BUPCALL F_READ
        tst     r0, r0
        bf      8f
        mov     r10, r4                 ! Write(other, dir entry, buffer, 1)
        mov     #1, r0
        xor     r0, r4
        mov     r11, r5
        mov.l   c_m_buf, r6
        mov     #1, r7
        BUPCALL F_WRITE
        tst     r0, r0
        bf      5f
        mov.l   p_s_copied, r4
        bra     9f
        nop
5:      cmp/eq  #4, r0
        bf      6f
        mov.l   p_s_nospace, r4
        bra     9f
        nop
6:      cmp/eq  #6, r0
        bf      7f
        mov.l   p_s_exists, r4
        bra     9f
        nop
7:      cmp/eq  #2, r0
        bf      8f
        mov.l   p_s_unformatted, r4
        bra     9f
        nop
4:      mov     r10, r4                 ! Format(device)
        BUPCALL F_FORMAT
        tst     r0, r0
        bf      8f
        mov     #0, r0
        mov.l   r0, @(V_SEL, r14)
        mov.l   r0, @(V_TOP, r14)
        mov.l   p_s_formatted, r4
        bra     9f
        nop
8:      mov     r0, r12                 ! failed: "FAILED" and the code
        mov.l   p_s_failed, r4
        bsr     message
        nop
        mov     r12, r4
        mov     #20, r5
        bsr     putdec
        mov     #MSG_ROW, r6
        bra     10f
        nop
9:      bsr     message
        nop
10:     bsr     refresh
        nop
        bra     loop
        nop

        .align  2
c_m_dir:        .long   M_DIR
c_m_buf:        .long   M_BUF
c_bufmax:       .long   BUFMAX
p_s_deleted:    .long   s_deleted
p_s_toolarge:   .long   s_toolarge
p_s_copied:     .long   s_copied
p_s_nospace:    .long   s_nospace
p_s_exists:     .long   s_exists
p_s_unformatted: .long  s_unformatted
p_s_formatted:  .long   s_formatted
p_s_failed:     .long   s_failed

! ---- screen ------------------------------------------------------------------

! draw_static: title and help lines
        .align  2
draw_static:
        sts.l   pr, @-r15
        PUTS    s_title, 1, 1
        PUTS    s_help1, 1, 24
        PUTS    s_help2, 1, 25
        mov     #1, r4                  ! title in the accent colour
        mov     #1, r5
        mov     #1, r6
        bsr     paint
        mov     #20, r7
        mov.l   p_ver_right, r0         ! version, top right
        jsr     @r0
        mov     #1, r6
        mov     #2, r6                  ! rules under the title, over the help
        bsr     rule
        nop
        mov     #23, r6
        bsr     rule
        nop
        mov     #3, r4                  ! help in grey
        mov     #1, r5
        mov     #24, r6
        bsr     paint
        mov     #39, r7
        mov     #3, r4
        mov     #1, r5
        mov     #25, r6
        bsr     paint
        mov     #39, r7
        lds.l   @r15+, pr
        rts
        nop

! paint: r4 = palette, r5 = column, r6 = row, r7 = cells (con_color).
paint:
        mov.l   p_con_color_m, r0
        jmp     @r0
        nop

! rule: r6 = row: a dim horizontal rule across the screen (con_fill).
rule:
        mov.w   c_rule_m, r4
        mov     #1, r5
        mov.l   p_con_fill_m, r0
        jmp     @r0
        mov     #38, r7

        .align  2
p_con_color_m:  .long   con_color
p_ver_right:    .long   ui_version_right
p_con_fill_m:   .long   con_fill
c_rule_m:       .word   0x6061          ! rule cell, palette 6 (dim)
        .align  2

! message: r4 = string for the message row, or 0 to clear it
        .align  2
message:
        sts.l   pr, @-r15
        mov.l   r4, @-r15
        mov     #MSG_ROW, r6
        bsr     clear_row
        nop
        mov.l   @r15+, r4
        tst     r4, r4
        bt      1f
        mov     #1, r5
        mov.l   p_con_puts_m, r0
        jsr     @r0
        mov     #MSG_ROW, r6
        mov     #2, r4                  ! messages in yellow
        mov     #1, r5
        mov     #MSG_ROW, r6
        bsr     paint
        mov     #39, r7
1:      lds.l   @r15+, pr
        rts
        nop

! clear_row: r6 = row (40 spaces). Clobbers r0-r5.
clear_row:
        mov.l   p_blank, r4
        mov     #0, r5
        mov.l   p_con_puts_m, r0
        jmp     @r0
        nop

! refresh: read the device's status and directory, then draw the header and
! the list.
        .align  2
refresh:
        sts.l   pr, @-r15
        mov     #DEV_ROW, r6
        bsr     clear_row
        nop
        mov.l   @(V_DEV, r14), r0
        tst     r0, r0
        bf      1f
        mov.l   p_s_internal, r4
        bra     2f
        nop
1:      mov.l   p_s_cartridge, r4
2:      mov     #1, r5
        mov.l   p_con_puts_m, r0
        jsr     @r0
        mov     #DEV_ROW, r6
        mov     #0, r0
        mov.l   r0, @(V_COUNT, r14)
        mov.l   @(V_DEV, r14), r4       ! Stat(device, 0, stat)
        mov     #0, r5
        mov.l   c_m_stat, r6
        BUPCALL F_STAT
        cmp/eq  #1, r0
        bf      3f
        mov.l   p_s_none, r4
        bra     6f
        nop
3:      cmp/eq  #2, r0
        bf      4f
        mov.l   p_s_notfmt, r4
        bra     6f
        nop
4:      mov.l   c_m_stat, r1            ! "FREE nnnnn OF nnnnn BLOCKS"
        mov.l   @(16, r1), r4
        mov     #18, r5
        bsr     putdec
        mov     #DEV_ROW, r6
        mov.l   c_m_stat, r1
        mov.l   @(4, r1), r4
        mov     #27, r5
        bsr     putdec
        mov     #DEV_ROW, r6
        PUTS    s_free, 13, DEV_ROW
        PUTS    s_of, 24, DEV_ROW
        PUTS    s_blocks, 33, DEV_ROW
        mov.l   @(V_DEV, r14), r4       ! Dir(device, "", MAXDIR, table)
        mov.l   p_s_empty, r5
        mov     #MAXDIR, r6
        mov.l   c_m_dir2, r7
        BUPCALL F_DIR
        cmp/pz  r0
        bt      5f
        mov.l   p_s_toomany, r4
        bra     6f
        nop
5:      tst     r0, r0
        bf      55f
        mov.l   p_s_nosaves, r4         ! empty device
        bra     6f
        nop
55:     mov.l   r0, @(V_COUNT, r14)
        mov.l   @(V_SEL, r14), r1       ! keep the selection in range
        cmp/hs  r0, r1
        bf      7f
        mov     #0, r1
        mov.l   r1, @(V_SEL, r14)
        mov.l   r1, @(V_TOP, r14)
        bra     7f
        nop
6:      mov.l   r4, @-r15               ! status line instead of the list
        mov     #LIST_ROW, r6
8:      mov.l   r6, @-r15
        bsr     clear_row
        nop
        mov.l   @r15+, r6
        add     #1, r6
        mov     #LIST_ROW + LIST_ROWS, r0
        cmp/hs  r0, r6
        bf      8b
        mov.l   @r15+, r4
        mov     #1, r5
        mov.l   p_con_puts_m, r0
        jsr     @r0
        mov     #LIST_ROW, r6
        bra     9f
        nop
7:      bsr     draw_list
        nop
9:      lds.l   @r15+, pr
        rts
        nop

        .align  2
p_con_puts_m:   .long   con_puts
p_blank:        .long   s_blank
p_s_internal:   .long   s_internal
p_s_cartridge:  .long   s_cartridge
p_s_none:       .long   s_none
p_s_notfmt:     .long   s_notfmt
p_s_toomany:    .long   s_toomany
p_s_nosaves:    .long   s_nosaves
p_s_empty:      .long   s_empty
c_m_stat:       .long   M_STAT
c_m_dir2:       .long   M_DIR

! draw_list: LIST_ROWS rows from entry V_TOP: cursor, name, comment, size in
! blocks. Preserves r8-r14.
        .align  2
draw_list:
        sts.l   pr, @-r15
        mov.l   r8, @-r15
        mov.l   r9, @-r15
        mov.l   r10, @-r15
        mov     #0, r8                  ! r8 = row offset
1:      mov     #LIST_ROW, r6
        add     r8, r6
        bsr     clear_row
        nop
        mov.l   @(V_TOP, r14), r9       ! r9 = entry index
        add     r8, r9
        mov.l   @(V_COUNT, r14), r0
        cmp/hs  r0, r9
        bt      3f
        mov     #36, r0                 ! r10 = entry
        mulu.w  r9, r0
        sts     macl, r10
        mov.l   c_m_dir3, r0
        add     r0, r10
        mov.l   @(V_SEL, r14), r0       ! cursor
        cmp/eq  r0, r9
        bf      2f
        mov.l   p_s_cursor, r4
        mov     #0, r5
        mov     #LIST_ROW, r6
        mov.l   p_con_puts_m2, r0
        jsr     @r0
        add     r8, r6
2:      mov     r10, r4                 ! name
        mov     #2, r5
        mov     #LIST_ROW, r6
        mov.l   p_con_puts_m2, r0
        jsr     @r0
        add     r8, r6
        mov     r10, r4                 ! comment
        add     #12, r4
        mov     #14, r5
        mov     #LIST_ROW, r6
        mov.l   p_con_puts_m2, r0
        jsr     @r0
        add     r8, r6
        mov     r10, r0                 ! size in blocks
        add     #32, r0
        mov.w   @r0, r0
        extu.w  r0, r4
        mov     #27, r5
        mov     #LIST_ROW, r6
        bsr     putdec
        add     r8, r6
        mov.l   @(V_SEL, r14), r0       ! the selected save in yellow
        cmp/eq  r0, r9
        bf      3f
        mov     #2, r4
        mov     #0, r5
        mov     #LIST_ROW, r6
        add     r8, r6
        bsr     paint
        mov     #40, r7
3:      add     #1, r8
        mov     #LIST_ROWS, r0
        cmp/hs  r0, r8
        bf      1b
        mov.l   @r15+, r10
        mov.l   @r15+, r9
        mov.l   @r15+, r8
        lds.l   @r15+, pr
        rts
        nop

! putdec: r4 (0-99999) as 5 characters, right-aligned, at column r5, row
! r6. Clobbers r0-r7.
        .align  2
putdec:
        mov.l   c_m_num, r7
        mova    powers, r0
        mov     r0, r3
        mov     #0, r2                  ! r2 = 1 once a digit was printed
1:      mov.l   @r3+, r1                ! r1 = power of ten
        tst     r1, r1
        bt      4f
        mov     #0x30, r0               ! count how often it fits
2:      cmp/hs  r1, r4
        bf      3f
        sub     r1, r4
        bra     2b
        add     #1, r0
3:      cmp/eq  #0x30, r0               ! leading zero: space (not the last)
        bf      5f
        tst     r2, r2
        bf      5f
        mov     #1, r0
        cmp/eq  r0, r1
        bt      6f
        mov     #0x20, r0
        mov.b   r0, @r7
        bra     1b
        add     #1, r7
6:      mov     #0x30, r0
5:      mov     #1, r2
        mov.b   r0, @r7
        bra     1b
        add     #1, r7
4:      mov     #0, r0
        mov.b   r0, @r7
        mov.l   c_m_num, r4
        mov.l   p_con_puts_m2, r0
        jmp     @r0
        nop

        .align  2
powers:         .long   10000, 1000, 100, 10, 1, 0
c_m_num:        .long   M_NUM
c_m_dir3:       .long   M_DIR
p_con_puts_m2:  .long   con_puts
p_s_cursor:     .long   s_cursor

! ---- text --------------------------------------------------------------------
        .align  2
s_title:        .asciz  "BACKUP RAM MANAGER"
        .align  2
s_help1:        .asciz  "UP/DOWN SELECT  L/R DEVICE  A DELETE"
        .align  2
s_help2:        .asciz  "C COPY  Y FORMAT  X SETUP  START EXIT"
        .align  2
s_internal:     .asciz  "INTERNAL"
        .align  2
s_cartridge:    .asciz  "CARTRIDGE"
        .align  2
s_free:         .asciz  "FREE"
        .align  2
s_of:           .asciz  "OF"
        .align  2
s_blocks:       .asciz  "BLK"
        .align  2
s_none:         .asciz  "NOT CONNECTED"
        .align  2
s_notfmt:       .asciz  "NOT FORMATTED - Y TO FORMAT"
        .align  2
s_toomany:      .asciz  "TOO MANY SAVES TO LIST"
        .align  2
s_nosaves:      .asciz  "NO SAVES"
        .align  2
s_empty:        .asciz  ""
        .align  2
s_cursor:       .asciz  ">"
        .align  2
s_q_delete:     .asciz  "DELETE THIS SAVE?  A YES  B NO"
        .align  2
s_q_copy:       .asciz  "COPY TO THE OTHER DEVICE?  A YES  B NO"
        .align  2
s_q_format:     .asciz  "FORMAT, ERASING ALL SAVES?  A YES  B NO"
s_nodisc:       .asciz  "NO DISC. INSERT ONE AND IT WILL BOOT"
s_nocart:       .asciz  "NO BACKUP RAM CARTRIDGE FOUND"
        .align  2
s_deleted:      .asciz  "DELETED"
        .align  2
s_copied:       .asciz  "COPIED"
        .align  2
s_formatted:    .asciz  "FORMATTED"
        .align  2
s_toolarge:     .asciz  "SAVE TOO LARGE TO COPY"
        .align  2
s_nospace:      .asciz  "NOT ENOUGH SPACE"
        .align  2
s_exists:       .asciz  "ALREADY ON THE OTHER DEVICE"
        .align  2
s_unformatted:  .asciz  "OTHER DEVICE NOT FORMATTED"
        .align  2
s_failed:       .asciz  "FAILED, CODE"
        .align  2
s_blank:        .asciz  "                                        "

        .ifdef  MENUSCRIPT              ! test scripts: (frames, buttons) pairs
        .align  2
        .if     MENUSCRIPT == 7         ! open the settings page
script:         .word   30, 0, 2, PAD_X, 30, 0, 0, 0
        .elseif MENUSCRIPT == 6         ! settings: Deutsch, back, boot
script:         .word   30, 0, 2, PAD_X, 60, 0, 2, PAD_RIGHT, 60, 0
                .word   2, PAD_B, 40, 0, 2, PAD_START, 10, 0, 0, 0
        .elseif MENUSCRIPT == 5         ! settings: two languages on, back,
script:         .word   30, 0, 2, PAD_X, 60, 0, 2, PAD_RIGHT, 40, 0 ! reopen
                .word   2, PAD_RIGHT, 40, 0, 2, PAD_B, 40, 0, 2, PAD_X, 60, 0
                .word   0, 0
        .elseif MENUSCRIPT == 4         ! L (look for a cartridge)
script:         .word   30, 0, 2, PAD_L, 30, 0, 0, 0
        .elseif MENUSCRIPT == 3         ! Start (leave)
script:         .word   30, 0, 2, PAD_START, 30, 0, 0, 0
        .elseif MENUSCRIPT == 2         ! cartridge: delete the first save
script:         .word   30, 0, 2, PAD_R, 20, 0, 2, PAD_A, 10, 0
                .word   2, PAD_A, 30, 0, 0, 0
        .else                           ! copy the first save to the
script:         .word   30, 0, 2, PAD_C, 10, 0, 2, PAD_A, 60, 0
                .word   2, PAD_R, 30, 0, 0, 0 ! cartridge, then show it
        .endif
        .endif
