! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - VDP2 text console (clean-room)
!
! NBG0 in 16-colour cell mode, 1-word pattern names, 64x64-cell plane.
! Character patterns live at VRAM 0 with char number == ASCII code, so a
! pattern name word is just the character. Map (plane) lives in VRAM bank B0.

        .section .text
        .global vdp2_init
        .global con_puts
        .global con_puthex

        .equ    VDP2_VRAM,  0x25E00000
        .equ    VDP2_CRAM,  0x25F00000
        .equ    VDP2_REGS,  0x25F80000
        .equ    MAP_OFS,    0x40000         ! bank B0, map register value 0x20
        .equ    FONT_OFS,   0x20 * 32       ! first glyph is ' ' (0x20)
        .equ    BACK_OFS,   0x7FFFE         ! last VRAM word holds the back colour

! CELL_ADDR: r1 = map address of (r5 = column, r6 = row). Clobbers r5, r6.
        .macro  CELL_ADDR
        mov.l   c_map, r1
        shll2   r6
        shll2   r6
        shll2   r6
        shll    r6                      ! row * 64 cells * 2 bytes
        shll    r5                      ! column * 2 bytes
        add     r6, r1
        add     r5, r1
        .endm

! vdp2_init: reset VDP2 to a known state and bring up the text layer.
        .align  2
vdp2_init:
        ! Zero all registers 0x000-0x11E (display off while we set up)
        mov.l   c_regs, r1
        mov     #0, r0
        mov.w   c_nregs, r2
1:      mov.w   r0, @r1
        dt      r2
        bf/s    1b
        add     #2, r1

        ! Clear all 512 KB of VRAM
        mov.l   c_vram, r1
        mov.l   c_vram_longs, r2
2:      mov.l   r0, @r1
        dt      r2
        bf/s    2b
        add     #4, r1

        ! Copy the font into character pattern memory
        mov.l   c_font, r1
        mov.l   c_font_end, r2
        mov.l   c_font_dst, r3
3:      mov.l   @r1+, r0
        mov.l   r0, @r3
        cmp/hs  r2, r1
        bf/s    3b
        add     #4, r3

        ! Palette 0: index 1 = white ink (index 0 is transparent)
        mov.l   c_cram, r1
        mov.w   c_white, r0
        mov.w   r0, @(2, r1)

        ! Back screen colour
        mov.l   c_back, r1
        mov.w   c_backcol, r0
        mov.w   r0, @r1

        ! Apply (register offset, value) pairs until offset 0xFFFF
        mov.l   c_regs, r3
        mova    vdp2_tab, r0
        mov     r0, r1
4:      mov.w   @r1+, r0                ! sign-extends, as does c_end
        mov.w   c_end, r2
        cmp/eq  r2, r0
        bt      5f
        mov.w   @r1+, r2
        add     r3, r0
        bra     4b
        mov.w   r2, @r0
5:      rts
        nop

! con_puts: r4 = NUL-terminated string, r5 = column, r6 = row
        .align  2
con_puts:
        CELL_ADDR
        mov     #0x60, r2
1:      mov.b   @r4+, r0
        extu.b  r0, r0
        tst     r0, r0
        bt      9f
        cmp/hs  r2, r0                  ! fold lowercase to uppercase
        bf      2f
        add     #-0x20, r0
2:      mov.w   r0, @r1
        bra     1b
        add     #2, r1
9:      rts
        nop

! con_puthex: r4 = 32-bit value, r5 = column, r6 = row. Prints 8 hex digits.
        .align  2
con_puthex:
        CELL_ADDR
        mov     #8, r3
        mov     #10, r2
1:      rotl    r4
        rotl    r4
        rotl    r4
        rotl    r4
        mov     r4, r0
        and     #0x0F, r0
        cmp/hs  r2, r0
        bf      2f
        add     #7, r0                  ! 'A'-'9'-1
2:      add     #0x30, r0
        mov.w   r0, @r1
        dt      r3
        bf/s    1b
        add     #2, r1
        rts
        nop

        .align  2
c_regs:         .long   VDP2_REGS
c_vram:         .long   VDP2_VRAM
c_vram_longs:   .long   0x80000 / 4
c_font:         .long   font_data
c_font_end:     .long   font_end
c_font_dst:     .long   VDP2_VRAM + FONT_OFS
c_cram:         .long   VDP2_CRAM
c_back:         .long   VDP2_VRAM + BACK_OFS
c_map:          .long   VDP2_VRAM + MAP_OFS
c_nregs:        .word   0x120 / 2
c_white:        .word   0x7FFF
c_backcol:      .word   0x8000 | (14 << 10) | (4 << 5) | 2   ! dark blue
c_end:          .word   0xFFFF

        .align  2
vdp2_tab:
        .word   0x0010, 0x44FF          ! CYCA0L: T0,T1 = NBG0 character read
        .word   0x0012, 0xFFFF          ! CYCA0U
        .word   0x0014, 0xFFFF          ! CYCA1L
        .word   0x0016, 0xFFFF          ! CYCA1U
        .word   0x0018, 0x0FFF          ! CYCB0L: T0 = NBG0 pattern name read
        .word   0x001A, 0xFFFF          ! CYCB0U
        .word   0x001C, 0xFFFF          ! CYCB1L
        .word   0x001E, 0xFFFF          ! CYCB1U
        .word   0x0020, 0x0001          ! BGON: NBG0 on
        .word   0x0028, 0x0000          ! CHCTLA: NBG0 16 colours, 1x1 cells
        .word   0x0030, 0xC000          ! PNCN0: 1-word names, 12-bit char number
        .word   0x003A, 0x0000          ! PLSZ: 1x1 plane
        .word   0x0040, 0x2020          ! MPABN0: planes A,B at MAP_OFS
        .word   0x0042, 0x2020          ! MPCDN0: planes C,D at MAP_OFS
        .word   0x0078, 0x0001          ! ZMXIN0: 1.0 horizontal step
        .word   0x007C, 0x0001          ! ZMYIN0: 1.0 vertical step
        .word   0x00AC, BACK_OFS >> 17  ! BKTAU
        .word   0x00AE, (BACK_OFS >> 1) & 0xFFFF   ! BKTAL
        .word   0x00F8, 0x0007          ! PRINA: NBG0 priority 7
        .word   0x0000, 0x8100          ! TVMD: display on, 320x224 (last)
        .word   0xFFFF
