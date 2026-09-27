! SPDX-License-Identifier: GPL-2.0-or-later
! First read file of the SaturnOpenBios test disc, loaded to 0x06004000.
!
! Exercises the BIOS services a game uses, through the system call pointers
! at 0x06000xxx (the clock change first, since it resets the video chips),
! and prints one line per test. The screen turns green when
! every test passes and red otherwise. Text goes into the BIOS console's
! NBG0 map (its font maps character codes to ASCII); a real game would set
! up VDP2 itself.

        .section .text
        .global _start

        .equ    MAP,        0x25E40000
        .equ    BACK,       0x25E7FFFE
        .equ    SYS_SET_SCU_INT,   0x06000300
        .equ    SYS_GET_SCU_INT,   0x06000304
        .equ    SYS_SET_SH2_INT,   0x06000310
        .equ    SYS_GET_SH2_INT,   0x06000314
        .equ    SYS_CHANGE_CLOCK,  0x06000320
        .equ    SYS_CLOCK_MODE,    0x06000324
        .equ    SYS_GET_SEM,       0x06000330
        .equ    SYS_CLEAR_SEM,     0x06000334
        .equ    SYS_SET_SCU_MASK,  0x06000340
        .equ    SYS_CHANGE_SCU_MASK, 0x06000344
        .equ    SYS_MASK_SHADOW,   0x06000348
        .equ    SYS_CHANGE_PRIO,   0x06000280
        .equ    SCU_IST,    0x25FE00A4

! SYSCALL addr: call the BIOS service whose pointer is stored at addr.
! r14 holds 0x06000200 for the whole program (callee-saved, so the BIOS and
! interrupt handlers preserve it).
        .macro  SYSCALL addr
        mov     #((\addr - 0x06000200) / 4), r0
        shll2   r0
        mov.l   @(r0, r14), r0
        jsr     @r0
        nop
        .endm

_start:
        mov.l   c_sysbase, r14
        bsr     clear_map
        nop
        mova    s_title, r0
        mov     r0, r4
        mov     #2, r5
        bsr     puts
        mov     #1, r6

        mova    tests, r0               ! r8 = test table, r9 = row, r10 = fails
        mov     r0, r8
        mov     #3, r9
        mov     #0, r10
1:      mov.l   @r8+, r4
        tst     r4, r4
        bt      2f
        mov     #2, r5
        bsr     puts
        mov     r9, r6
        mov.l   @r8+, r0
        jsr     @r0
        nop
        tst     r0, r0
        bf      3f
        mova    s_ok, r0
        bra     4f
        nop
3:      add     #1, r10
        mova    s_fail, r0
4:      mov     r0, r4
        mov     #28, r5
        bsr     puts
        mov     r9, r6
        bra     1b
        add     #1, r9

2:      mov.l   c_back, r1              ! green if all passed, red otherwise
        mov.w   c_green, r0
        tst     r10, r10
        bt      5f
        mov.w   c_red, r0
5:      mov.w   r0, @r1
6:      bra     6b
        nop

        .align  2
c_sysbase:      .long   0x06000200
c_green:        .word   0x8000 | (4 << 10) | (20 << 5) | 4
c_red:          .word   0x8000 | (4 << 10) | (4 << 5) | 20
        .align  2
tests:
        .long   n_clock,  t_clock
        .long   n_sem,    t_sem
        .long   n_sh2,    t_sh2int
        .long   n_mask,   t_mask
        .long   n_prio,   t_prio
        .long   n_vbl,    t_vblank
        .long   0

        .align  2
s_title:        .asciz  "TEST DISC: BIOS SERVICES"
        .align  2
s_ok:           .asciz  "OK"
        .align  2
s_fail:         .asciz  "FAIL"
        .align  2
n_sem:          .asciz  "SEMAPHORE GET/CLEAR"
        .align  2
n_sh2:          .asciz  "SET/GET SH2 INT (TRAPA)"
        .align  2
n_mask:         .asciz  "SCU MASK SET/CHANGE"
        .align  2
n_prio:         .asciz  "SCU PRIORITY TABLE"
        .align  2
n_vbl:          .asciz  "SCU VBLANK IRQ X10"
        .align  2
n_clock:        .asciz  "CHANGE CLOCK 320"

        .align  2
! ---- tests: return r0 = 0 on pass --------------------------------------

! Semaphore 5: first get succeeds, second fails, after clear it succeeds.
t_sem:
        sts.l   pr, @-r15
        mov     #5, r4
        SYSCALL SYS_GET_SEM
        cmp/eq  #1, r0
        bf      9f
        mov     #5, r4
        SYSCALL SYS_GET_SEM
        cmp/eq  #0, r0
        bf      9f
        mov     #5, r4
        SYSCALL SYS_CLEAR_SEM
        mov     #5, r4
        SYSCALL SYS_GET_SEM
        cmp/eq  #1, r0
        bf      9f
        mov     #5, r4
        SYSCALL SYS_CLEAR_SEM
        bra     pass
        nop
9:      bra     fail
        nop

! SH-2 vector 32 (TRAPA #32): install a handler, trap, check it ran, then
! restore the default and check it is the BIOS "rte" stub.
t_sh2int:
        sts.l   pr, @-r15
        mov.l   c_flag, r1
        mov     #0, r0
        mov.l   r0, @r1
        mov     #32, r4
        mov.l   c_trap_handler, r5
        SYSCALL SYS_SET_SH2_INT
        trapa   #32
        mov.l   c_flag, r1
        mov.l   @r1, r0
        cmp/eq  #1, r0
        bf      9f
        mov     #32, r4
        SYSCALL SYS_GET_SH2_INT
        mov.l   c_trap_handler, r1
        cmp/eq  r1, r0
        bf      9f
        mov     #32, r4
        mov     #0, r5
        SYSCALL SYS_SET_SH2_INT
        mov     #32, r4
        SYSCALL SYS_GET_SH2_INT
        mov.l   c_rte_stub, r1
        cmp/eq  r1, r0
        bf      9f
        bra     pass
        nop
9:      bra     fail
        nop

trap_handler:
        mov.l   r0, @-r15
        mov.l   r1, @-r15
        mov.l   c_flag, r1
        mov     #1, r0
        mov.l   r0, @r1
        mov.l   @r15+, r1
        mov.l   @r15+, r0
        rte
        nop

! SCU mask: change through the AND/OR call and check the shadow copy.
! Uses bit 12 (DMA illegal), which never fires here.
t_mask:
        sts.l   pr, @-r15
        mov.l   c_mask_all, r4
        SYSCALL SYS_SET_SCU_MASK
        mov.l   c_not_bit12, r4
        mov     #0, r5
        SYSCALL SYS_CHANGE_SCU_MASK
        mov.l   c_shadow, r1
        mov.l   @r1, r0
        mov.l   c_mask_12on, r1
        cmp/eq  r1, r0
        bf      9f
        mov     #-1, r4
        mov.l   c_bit12, r5
        SYSCALL SYS_CHANGE_SCU_MASK
        mov.l   c_shadow, r1
        mov.l   @r1, r0
        mov.l   c_mask_all, r1
        cmp/eq  r1, r0
        bf      9f
        bra     pass
        nop
9:      bra     fail
        nop

! Priority table: load a copy of the defaults (the VBlank test runs next).
t_prio:
        sts.l   pr, @-r15
        mova    prio_tab, r0
        mov     r0, r4
        SYSCALL SYS_CHANGE_PRIO
        bra     pass
        nop

! SCU VBlank-IN (vector 0x40): install a handler, unmask it, wait for ten
! interrupts, mask it again, and check the dispatcher restored the mask.
t_vblank:
        sts.l   pr, @-r15
        mov.l   c_count, r1
        mov     #0, r0
        mov.l   r0, @r1
        mov     #0x40, r4
        mov.l   c_vblank_handler, r5
        SYSCALL SYS_SET_SCU_INT
        mov     #0x40, r4
        SYSCALL SYS_GET_SCU_INT
        mov.l   c_vblank_handler, r1
        cmp/eq  r1, r0
        bf      9f
        mov.l   c_mask_vbl, r4          ! only VBlank-IN unmasked
        SYSCALL SYS_SET_SCU_MASK
        mov.l   c_wait, r2
1:      mov.l   c_count, r1
        mov.l   @r1, r0
        cmp/hs  r3, r0                  ! r3 = 10 (set below)
        mov     #10, r3
        cmp/hs  r3, r0
        bt      2f
        dt      r2
        bf      1b
2:      mov.l   c_mask_all, r4
        SYSCALL SYS_SET_SCU_MASK
        mov     #0x40, r4
        mov     #0, r5
        SYSCALL SYS_SET_SCU_INT
        mov.l   c_count, r1
        mov.l   @r1, r0
        mov     #10, r3
        cmp/hs  r3, r0
        bf      9f
        mov.l   c_shadow, r1
        mov.l   @r1, r0
        mov.l   c_mask_all, r1
        cmp/eq  r1, r0
        bf      9f
        bra     pass
        nop
9:      bra     fail
        nop

vblank_handler:
        mov.l   c_count, r1
        mov.l   @r1, r0
        add     #1, r0
        mov.l   r0, @r1
        mov.l   c_scu_ist, r1           ! acknowledge VBlank-IN
        mov     #-2, r0
        rts
        mov.l   r0, @r1

! Clock change to 320 mode: the call must return and record the mode. The
! SMPC resets VDP1, VDP2, SCU and SCSP on a clock change (video RAM is kept),
! so, like a game, this sets up its VDP2 display again afterwards.
t_clock:
        sts.l   pr, @-r15
        mov     #0, r4
        SYSCALL SYS_CHANGE_CLOCK
        bsr     vdp2_setup
        nop
        mov.l   c_clock_mode, r1
        mov.l   @r1, r0
        tst     r0, r0
        bf      9f
        bra     pass
        nop
9:      bra     fail
        nop

pass:
        lds.l   @r15+, pr
        rts
        mov     #0, r0
fail:
        lds.l   @r15+, pr
        rts
        mov     #1, r0

        .align  2
! ---- screen output -------------------------------------------------------

! vdp2_setup: text layer NBG0 as the BIOS console left it (font and map
! are still in VRAM), back screen colour at the end of VRAM, display on.
vdp2_setup:
        mova    vdp2_regs, r0
        mov     r0, r1
        mov.l   c_vdp2, r2
1:      mov.w   @r1+, r0
        extu.w  r0, r0
        mov.w   c_end, r3
        extu.w  r3, r3
        cmp/eq  r3, r0
        bt      2f
        mov.w   @r1+, r3
        add     r2, r0
        bra     1b
        mov.w   r3, @r0
2:      rts
        nop

! clear_map: zero the NBG0 map (64 x 32 cells shown)
clear_map:
        mov.l   c_map, r1
        mov.w   c_map_longs, r2
        mov     #0, r0
1:      mov.l   r0, @r1
        dt      r2
        bf/s    1b
        add     #4, r1
        rts
        nop

! puts: r4 = string, r5 = column, r6 = row
puts:
        mov.l   c_map, r1
        shll8   r6
        shlr    r6                      ! row * 128
        add     r6, r1
        shll    r5
        add     r5, r1
1:      mov.b   @r4+, r0
        tst     r0, r0
        bt      2f
        mov.w   r0, @r1
        bra     1b
        add     #2, r1
2:      rts
        nop

        .align  2
c_map:          .long   MAP
c_vdp2:         .long   0x25F80000
c_back:         .long   BACK
c_flag:         .long   0x06004F00
c_count:        .long   0x06004F04
c_trap_handler: .long   trap_handler
c_vblank_handler: .long vblank_handler
c_rte_stub:     .long   0x06000600
c_shadow:       .long   SYS_MASK_SHADOW
c_clock_mode:   .long   SYS_CLOCK_MODE
c_scu_ist:      .long   SCU_IST
c_mask_all:     .long   0x0000BFFF
c_mask_vbl:     .long   0x0000BFFE
c_not_bit12:    .long   0xFFFFEFFF
c_bit12:        .long   0x00001000
c_mask_12on:    .long   0x0000AFFF
c_wait:         .long   0x00800000
c_map_longs:    .word   64 * 32 * 2 / 4
c_end:          .word   0xFFFF

        .align  2
vdp2_regs:                              ! (register offset, value)
        .word   0x0010, 0x44FF          ! CYCA0L: NBG0 character reads
        .word   0x0012, 0xFFFF
        .word   0x0014, 0xFFFF
        .word   0x0016, 0xFFFF
        .word   0x0018, 0x0FFF          ! CYCB0L: NBG0 pattern name reads
        .word   0x001A, 0xFFFF
        .word   0x001C, 0xFFFF
        .word   0x001E, 0xFFFF
        .word   0x0020, 0x0001          ! BGON: NBG0
        .word   0x0028, 0x0000          ! CHCTLA: 16 colours
        .word   0x0030, 0xC000          ! PNCN0: 1-word names
        .word   0x0040, 0x2020          ! MPABN0: map at VRAM 0x40000
        .word   0x0042, 0x2020          ! MPCDN0
        .word   0x0078, 0x0001          ! ZMXIN0
        .word   0x007C, 0x0001          ! ZMYIN0
        .word   0x00AC, 0x0003          ! BKTAU: back colour at VRAM 0x7FFFE
        .word   0x00AE, 0xFFFF          ! BKTAL
        .word   0x00F8, 0x0007          ! PRINA: NBG0 priority 7
        .word   0x0000, 0x8100          ! TVMD: display on, 320x224
        .word   0xFFFF

        .align  2
prio_tab:
        .long   0x00F0FFFF, 0x00E0FFFE, 0x00D0FFFC, 0x00C0FFF8
        .long   0x00B0FFF0, 0x00A0FFE0, 0x0090FFC0, 0x0080FF80
        .long   0x0080FF80, 0x0070FE00, 0x0070FE00, 0x0070FE00
        .long   0x0070FE00, 0x0070FE00, 0x0070FE00, 0x0070FE00
        .rept   16
        .long   0x0070FE00
        .endr

