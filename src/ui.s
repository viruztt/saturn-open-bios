! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - boot splash and progress (clean-room)
!
! The boot screen: "SATURN" in large pixel letters drawn from the console
! font, "OPEN BIOS" under it, a progress bar with the name of the step
! running, and a hint that Start opens the backup RAM manager. These run
! before Work RAM is set up, so they use no stack: each keeps its return
! address in r13 (the boot code does not use r13 until the steps are done).
! Clobber r0-r7 and r13.

        .section .text
        .global ui_splash
        .global ui_step
        .global ui_status

        .equ    BAR_ROW,    20
        .equ    BAR_COL,    6
        .equ    BAR_LEN,    28
        .equ    STAT_ROW,   22

! ui_splash: draw the boot screen on a freshly initialised console.
        .align  2
ui_splash:
        sts     pr, r13
        mova    s_saturn, r0            ! SATURN, 6 x 6 columns, centred
        mov     r0, r4
        mov     #2, r5
        mov     #6, r6
        mov.w   c_pix_accent, r7
        mov.l   p_con_big, r0
        jsr     @r0
        nop
        mov     #0, r3                  ! its 7 rows fade (palettes 8-14)
1:      mov     r3, r4
        add     #8, r4
        mov     #2, r5
        mov     r3, r6
        add     #6, r6
        mov.l   p_con_color, r0
        jsr     @r0
        mov     #36, r7
        add     #1, r3
        mov     #7, r0
        cmp/eq  r0, r3
        bf      1b
        mova    s_openbios, r0
        mov     r0, r4
        mov     #11, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     #15, r6
        mov.w   c_rule_dim, r4          ! thin rule under the title
        mov     #BAR_COL, r5
        mov     #17, r6
        mov.l   p_con_fill, r0
        jsr     @r0
        mov     #BAR_LEN, r7
        mov.w   c_block_dim, r4         ! empty progress bar
        mov     #BAR_COL, r5
        mov     #BAR_ROW, r6
        mov.l   p_con_fill, r0
        jsr     @r0
        mov     #BAR_LEN, r7
        mova    s_hint, r0              ! Start: backup RAM manager
        mov     r0, r4
        mov     #8, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     #26, r6
        mov     #3, r4
        mov     #8, r5
        mov     #26, r6
        mov.l   p_con_color, r0
        jsr     @r0
        mov     #25, r7
        lds     r13, pr
        rts
        nop

! ui_step: r4 = number of steps done (0-13), r5 = name of the step about
! to run. Fills the bar up to r4 and shows the name. (The name stays in
! r3, which the console routines leave alone.)
        .align  2
ui_step:
        sts     pr, r13
        mov     r5, r3
        mov     r4, r7                  ! 2 cells per step done
        shll    r7
        tst     r7, r7
        bt      status
        mov.w   c_block_accent, r4
        mov     #BAR_COL, r5
        mov     #BAR_ROW, r6
        mov.l   p_con_fill, r0
        jsr     @r0
        nop
        bra     status
        nop

! ui_status: r4 = text for the status line under the bar.
ui_status:
        sts     pr, r13
        mov     r4, r3
status: mov.w   c_space, r4             ! clear the line
        mov     #BAR_COL, r5
        mov     #STAT_ROW, r6
        mov.l   p_con_fill, r0
        jsr     @r0
        mov     #BAR_LEN, r7
        mov     r3, r4
        mov     #BAR_COL, r5
        mov.l   p_con_puts, r0
        jsr     @r0
        mov     #STAT_ROW, r6
        mov     #3, r4                  ! in grey
        mov     #BAR_COL, r5
        mov     #STAT_ROW, r6
        mov.l   p_con_color, r0
        jsr     @r0
        mov     #BAR_LEN, r7
        lds     r13, pr
        rts
        nop

        .align  2
p_con_big:      .long   con_big
p_con_puts:     .long   con_puts
p_con_fill:     .long   con_fill
p_con_color:    .long   con_color
c_pix_accent:   .word   0x1062          ! pixel cell, palette 1
c_rule_dim:     .word   0x6061          ! rule, palette 6
c_block_dim:    .word   0x6060          ! block, palette 6
c_block_accent: .word   0x1060          ! block, palette 1
c_space:        .word   0x0020
        .align  2
s_saturn:       .asciz  "SATURN"
        .align  2
s_openbios:     .asciz  "O P E N   B I O S"
        .align  2
s_hint:         .asciz  "START: SAVES AND SETTINGS"
        .align  2
