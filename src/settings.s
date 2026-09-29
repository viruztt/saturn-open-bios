! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - system settings page (clean-room)
!
! settings_main: shows the language kept in the SMPC's battery-backed
! memory (SMEM byte 3, low nibble: 0 English, 1 German, 2 French,
! 3 Spanish, 4 Italian, 5 Japanese; games read it with INTBACK) and the
! SMPC clock. Left/Right change the language, which is written at once
! with SETSMEM (the other SMEM bits are kept); B or Start return.
! One SMPC request per frame: a pad read, a status read (every 30 frames)
! or the SETSMEM, each just after VBlank-out. Preserves r8-r14.

        .section .text
        .global settings_main

        .equ    SMPC_IREG0, 0x20100001
        .equ    SMPC_COMREG, 0x2010001F
        .equ    SMPC_OREG0, 0x20100021
        .equ    SMPC_SF,    0x20100063
        .equ    TVSTAT,     0x25F80004

        .equ    PAD_RIGHT,  0x8000
        .equ    PAD_LEFT,   0x4000
        .equ    PAD_START,  0x0800
        .equ    PAD_B,      0x0100

        .equ    S_V,        0x20206100      ! variables (Low Work RAM)
        .equ    S_PREV,     0               ! pad state last frame
        .equ    S_FRAMES,   4               ! frames since the last status read
        .equ    S_LANG,     8               ! language shown
        .equ    S_OK,       12              ! 1 if the last status read worked
        .equ    S_PEND,     16              ! 1 if a SETSMEM is due
        .equ    S_ST,       20              ! OREG0..15 of the last status read
        .equ    S_TXT,      40              ! clock text

        .equ    NLANG,      6
        .equ    LANG_ROW,   4
        .equ    CLOCK_ROW,  6
        .equ    VAL_COL,    12

! PUTS str, col, row
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

        .align  2
settings_main:
        sts.l   pr, @-r15
        mov.l   r14, @-r15
        mov.l   r13, @-r15
        mov.l   c_s_v, r14
        mov.l   c_s_all, r0             ! ignore buttons already held
        mov.l   r0, @(S_PREV, r14)
        mov     #0, r0
        mov.l   r0, @(S_FRAMES, r14)
        mov.l   r0, @(S_PEND, r14)
        mov.l   p_vdp2_init_s, r0       ! fresh screen
        jsr     @r0
        nop
        PUTS    s_title, 1, 1
        PUTS    s_lang, 1, LANG_ROW
        PUTS    s_clock, 1, CLOCK_ROW
        PUTS    s_help, 1, 24
        bsr     style
        nop
        bsr     vbl_end
        nop
        bsr     status_read
        nop
        mov     r14, r1                 ! language from SMEM byte 3
        add     #S_ST + 15, r1
        mov.b   @r1, r0
        and     #0x0F, r0
        mov     #NLANG, r1
        cmp/hs  r1, r0
        bf      1f
        mov     #0, r0
1:      mov.l   r0, @(S_LANG, r14)
        bsr     draw_lang
        nop
        bsr     draw_clock
        nop

sloop:
        mov.l   p_vbl_wait_s, r0
        jsr     @r0
        nop
        mov.l   @(S_PEND, r14), r0      ! a new language to store?
        tst     r0, r0
        bt      1f
        mov     #0, r0
        mov.l   r0, @(S_PEND, r14)
        bsr     vbl_end
        nop
        bsr     setsmem
        nop
        bra     sloop
        nop
1:      mov.l   @(S_FRAMES, r14), r0    ! the clock, twice a second
        add     #1, r0
        mov.l   r0, @(S_FRAMES, r14)
        mov     #30, r1
        cmp/hs  r1, r0
        bf      2f
        mov     #0, r0
        mov.l   r0, @(S_FRAMES, r14)
        bsr     vbl_end
        nop
        bsr     status_read
        nop
        bsr     draw_clock
        nop
        bra     sloop
        nop
2:      mov.l   p_pad_read_s, r0
        jsr     @r0
        nop
        .ifdef  MENUSCRIPT              ! (test builds: add scripted buttons)
        mov.l   r0, @-r15
        mov.l   p_script_s, r0
        jsr     @r0
        nop
        mov.l   @r15+, r1
        or      r1, r0
        .endif
        mov.l   @(S_PREV, r14), r1
        mov.l   r0, @(S_PREV, r14)
        not     r1, r1
        and     r0, r1
        mov     r1, r13                 ! r13 = pressed this frame
        mov.w   c_s_back, r1            ! B or Start: back
        tst     r1, r13
        bf      9f
        mov.l   @(S_LANG, r14), r0
        mov.w   c_s_left, r1
        tst     r1, r13
        bt      3f
        tst     r0, r0                  ! left: previous language
        bf/s    4f
        add     #-1, r0
        bra     4f
        mov     #NLANG - 1, r0
3:      mov.w   c_s_right, r1
        tst     r1, r13
        bt      sloop
        add     #1, r0                  ! right: next language
        cmp/eq  #NLANG, r0
        bf      4f
        mov     #0, r0
4:      mov.l   r0, @(S_LANG, r14)
        mov     r0, r2
        mov     r14, r1                 ! SMEM byte 3: keep the high nibble
        add     #S_ST + 15, r1
        mov.b   @r1, r0
        and     #0xF0, r0
        or      r2, r0
        mov.b   r0, @r1
        mov     #1, r0
        mov.l   r0, @(S_PEND, r14)
        bsr     draw_lang
        nop
        bra     sloop
        nop
9:      mov.l   @r15+, r13
        mov.l   @r15+, r14
        lds.l   @r15+, pr
        rts
        nop

        .align  2
c_s_v:          .long   S_V
c_s_all:        .long   0x0000FFFF
p_vdp2_init_s:  .long   vdp2_init
p_vbl_wait_s:   .long   vbl_wait
p_pad_read_s:   .long   pad_read
        .ifdef  MENUSCRIPT
p_script_s:     .long   script_pad
        .endif
c_s_back:       .word   PAD_B | PAD_START
c_s_left:       .word   PAD_LEFT
c_s_right:      .word   PAD_RIGHT

! style: colours and rules for the page (as the backup RAM manager's).
        .align  2
style:
        sts.l   pr, @-r15
        mov     #1, r4                  ! title: accent
        mov     #1, r5
        mov     #1, r6
        bsr     s_paint
        mov     #15, r7
        mov     #3, r4                  ! labels and help: grey
        mov     #1, r5
        mov     #LANG_ROW, r6
        bsr     s_paint
        mov     #8, r7
        mov     #3, r4
        mov     #1, r5
        mov     #CLOCK_ROW, r6
        bsr     s_paint
        mov     #8, r7
        mov     #3, r4
        mov     #1, r5
        mov     #24, r6
        bsr     s_paint
        mov     #38, r7
        mov     #2, r6                  ! rules
        bsr     s_rule
        nop
        mov     #23, r6
        bsr     s_rule
        nop
        lds.l   @r15+, pr
        rts
        nop

s_paint:
        mov.l   p_s_color, r0
        jmp     @r0
        nop

s_rule:
        mov.w   c_s_rule, r4
        mov     #1, r5
        mov.l   p_s_fill, r0
        jmp     @r0
        mov     #38, r7

        .align  2
p_s_color:      .long   con_color
p_s_fill:       .long   con_fill
c_s_rule:       .word   0x6061

! draw_lang: the language name at (VAL_COL, LANG_ROW).
        .align  2
draw_lang:
        mov.l   @(S_LANG, r14), r0
        shll2   r0
        mov.l   p_lang_names, r1
        mov.l   @(r0, r1), r4
        mov     #VAL_COL, r5
        mov.l   p_con_puts_s, r0
        jmp     @r0                     ! (returns to our caller)
        mov     #LANG_ROW, r6

! draw_clock: "YYYY-MM-DD HH:MM:SS" from the last status read, or
! "UNAVAILABLE"; " (NOT SET)" when the SMPC says the clock was never set.
        .align  2
draw_clock:
        mov.l   @(S_OK, r14), r0
        tst     r0, r0
        bf      1f
        mov.l   p_s_unavail, r4
        mov     #VAL_COL, r5
        mov.l   p_con_puts_s, r0
        jmp     @r0
        mov     #CLOCK_ROW, r6
1:      sts.l   pr, @-r15
        mov     r14, r3
        add     #S_ST, r3               ! r3 = status bytes
        mov     r14, r1
        add     #S_TXT, r1              ! r1 = text
        mov.b   @(1, r3), r0            ! year
        bsr     put2
        mov     r0, r4
        mov.b   @(2, r3), r0
        bsr     put2
        mov     r0, r4
        bsr     putc
        mov     #'-', r4
        mov.b   @(3, r3), r0            ! month (binary 1-12) as BCD
        and     #0x0F, r0
        cmp/eq  #10, r0
        bt      2f
        cmp/eq  #11, r0
        bt      2f
        cmp/eq  #12, r0
        bf      3f
2:      add     #6, r0
3:      bsr     put2
        mov     r0, r4
        bsr     putc
        mov     #'-', r4
        mov.b   @(4, r3), r0            ! day
        bsr     put2
        mov     r0, r4
        bsr     putc
        mov     #' ', r4
        mov.b   @(5, r3), r0            ! hour
        bsr     put2
        mov     r0, r4
        bsr     putc
        mov     #':', r4
        mov.b   @(6, r3), r0            ! minute
        bsr     put2
        mov     r0, r4
        bsr     putc
        mov     #':', r4
        mov.b   @(7, r3), r0            ! second
        bsr     put2
        mov     r0, r4
        mov.b   @r3, r0                 ! STE: clock set?
        tst     #0x80, r0
        bf      4f
        mov.l   p_s_notset, r2
5:      mov.b   @r2+, r0
        mov.b   r0, @r1
        tst     r0, r0
        bf/s    5b
        add     #1, r1
        bra     6f
        nop
4:      mov     #0, r0
        mov.b   r0, @r1
6:      mov     r14, r4
        add     #S_TXT, r4
        mov     #VAL_COL, r5
        mov.l   p_con_puts_s, r0
        jsr     @r0
        mov     #CLOCK_ROW, r6
        lds.l   @r15+, pr
        rts
        nop

! put2: two digits of the BCD byte r4 at r1 (r1 += 2). Clobbers r0.
put2:
        mov     r4, r0
        shlr2   r0
        shlr2   r0
        and     #0x0F, r0
        add     #0x30, r0
        mov.b   r0, @r1
        add     #1, r1
        mov     r4, r0
        and     #0x0F, r0
        add     #0x30, r0
        mov.b   r0, @r1
        rts
        add     #1, r1

! putc: the character r4 at r1 (r1 += 1).
putc:
        mov.b   r4, @r1
        rts
        add     #1, r1

        .align  2
p_lang_names:   .long   lang_names
p_con_puts_s:   .long   con_puts
p_s_unavail:    .long   s_unavail
p_s_notset:     .long   s_notset

! vbl_end: wait until the display is outside VBlank (VBlank-out has
! passed), with a loop bound. Clobbers r0-r2.
        .align  2
vbl_end:
        mov.l   c_s_tvstat, r1
        mov.l   c_s_wait, r2
1:      mov.w   @r1, r0
        tst     #8, r0
        bt      2f
        dt      r2
        bf      1b
2:      rts
        nop

! smpc_idle: T = 1 once SF is clear (T = 0 if it stays set). r1 = SF.
! Clobbers r0, r2.
smpc_idle:
        mov.l   c_s_sf, r1
        mov.l   c_s_wait, r2
1:      mov.b   @r1, r0
        tst     #1, r0
        bt      2f
        dt      r2
        bf      1b
        clrt
2:      rts
        nop

! status_read: INTBACK for the SMPC status only (no peripheral data, so
! no continue/break); copies OREG0..15 to S_ST, S_OK = 1 if it answered.
! Clobbers r0-r3.
        .align  2
status_read:
        sts.l   pr, @-r15
        bsr     smpc_idle
        nop
        bf      9f
        mov.l   c_s_ireg0, r3
        mov     #1, r0
        mov.b   r0, @r3                 ! IREG0: status
        mov     #0, r0
        mov.b   r0, @(2, r3)            ! IREG1: no peripheral data
        mov     #0xF0, r0
        mov.b   r0, @(4, r3)            ! IREG2: 0xF0
        mov     #1, r0
        mov.b   r0, @r1                 ! SF = 1
        mov.l   c_s_comreg, r3
        mov     #0x10, r0
        mov.b   r0, @r3                 ! INTBACK
        bsr     smpc_idle
        nop
        bf      9f
        mov.l   c_s_oreg0, r3
        mov     r14, r1
        add     #S_ST, r1
        mov     #16, r2
1:      mov.b   @r3, r0
        mov.b   r0, @r1
        add     #2, r3
        dt      r2
        bf/s    1b
        add     #1, r1
        mov     #1, r0
        bra     8f
        nop
9:      mov     #0, r0
8:      mov.l   r0, @(S_OK, r14)
        lds.l   @r15+, pr
        rts
        nop

! setsmem: SETSMEM with S_ST+12..15 (SMEM bytes 1-4). Clobbers r0-r3.
        .align  2
setsmem:
        sts.l   pr, @-r15
        bsr     smpc_idle
        nop
        bf      9f
        mov.l   c_s_ireg0, r3
        mov     r14, r2
        add     #S_ST + 12, r2
        mov.b   @r2+, r0
        mov.b   r0, @r3                 ! IREG0-3: SMEM
        mov.b   @r2+, r0
        mov.b   r0, @(2, r3)
        mov.b   @r2+, r0
        mov.b   r0, @(4, r3)
        mov.b   @r2+, r0
        mov.b   r0, @(6, r3)
        mov     #1, r0
        mov.b   r0, @r1                 ! SF = 1
        mov.l   c_s_comreg, r3
        mov     #0x17, r0
        mov.b   r0, @r3                 ! SETSMEM
        bsr     smpc_idle
        nop
9:      lds.l   @r15+, pr
        rts
        nop

        .align  2
c_s_tvstat:     .long   TVSTAT
c_s_wait:       .long   0x00100000
c_s_sf:         .long   SMPC_SF
c_s_ireg0:      .long   SMPC_IREG0
c_s_comreg:     .long   SMPC_COMREG
c_s_oreg0:      .long   SMPC_OREG0

        .align  2
lang_names:     .long   l_en, l_de, l_fr, l_es, l_it, l_ja
l_en:           .asciz  "ENGLISH "
l_de:           .asciz  "DEUTSCH "
l_fr:           .asciz  "FRANCAIS"
l_es:           .asciz  "ESPANOL "
l_it:           .asciz  "ITALIANO"
l_ja:           .asciz  "JAPANESE"
s_title:        .asciz  "SYSTEM SETTINGS"
s_lang:         .asciz  "LANGUAGE"
s_clock:        .asciz  "CLOCK"
s_help:         .asciz  "LEFT/RIGHT LANGUAGE  B BACK"
s_unavail:      .asciz  "UNAVAILABLE"
s_notset:       .asciz  " (NOT SET)"
        .align  2
