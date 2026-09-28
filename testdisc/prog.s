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
        .equ    SYS_BUP_INIT,      0x06000358
        .equ    SYS_BUP_WORK,      0x06000354

        ! Backup RAM test buffers (all above this program)
        .equ    BUP_LIB,    0x06010000      ! 16 KB library area
        .equ    BUP_WORK,   0x06014000      ! 8 KB work area
        .equ    BUP_CONF,   0x06016000      ! BupConfig[3]
        .equ    BUP_STAT,   0x06016010      ! BupStat
        .equ    BUP_DIRENT, 0x06016040      ! BupDir to write
        .equ    BUP_DATE,   0x06016080      ! BupDate
        .equ    BUP_DIRTAB, 0x06016100      ! BupDir[8] from Dir
        .equ    BUP_DATA,   0x06017000      ! 3000 bytes to save
        .equ    BUP_BUF,    0x06018000      ! 3000 bytes read back
        .equ    SAVE_SIZE,  3000
        .equ    SAVE_BLOCKS, 53             ! 1 + (3000 + 29) / 58

! BUPCALL off: call backup RAM library function at work area + off
! (r13 = work area, set by t_bupinit)
        .macro  BUPCALL off
        mov.l   @(\off, r13), r0
        jsr     @r0
        nop
        .endm

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
3:      cmp/eq  #2, r0                  ! 2: not applicable (no device)
        bf      5f
        mova    s_none, r0
        bra     4f
        nop
5:      add     #1, r10
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
        bsr     play_audio
        nop
6:      bra     6b
        nop

! play_audio: on the BIN/CUE test disc, play from track 2 to the end of the
! disc on repeat (track 2: 440 Hz / 660 Hz, track 3: 330 Hz / 550 Hz tones)
! through the CD block, leaving the sound mixer as the BIOS
! set it up. Clicks or crackling then come from that setup, not from a
! game's sound driver. Prints whether the CD block took the command.
play_audio:
        sts.l   pr, @-r15
        mova    s_audio, r0
        mov     r0, r4
        mov     #2, r5
        bsr     puts
        mov     #20, r6
        mov.l   c_cd_hirq, r2
        mov.l   c_cd_cr1, r1
        mov.w   c_not_cmok, r0
        mov.w   r0, @r2                 ! HIRQ bits written as 0 are cleared
        mov.w   c_play_cr1, r0          ! Play, track mode
        mov.w   r0, @(0, r1)
        mov.w   c_track2, r0            ! from track 2 index 1
        mov.w   r0, @(4, r1)
        mov.w   c_play_cr3, r0          ! repeat forever, end: 0 = end of
        mov.w   r0, @(8, r1)            ! the disc
        mov     #0, r0
        mov.w   r0, @(12, r1)
        mov.l   c_cd_wait, r3
1:      mov.w   @r2, r0
        tst     #1, r0                  ! CMOK
        bf      2f
        dt      r3
        bf      1b
        bra     3f
        mova    s_fail, r0
2:      mova    s_ok, r0
3:      mov     r0, r4
        mov     #28, r5
        bsr     puts
        mov     #20, r6
        lds.l   @r15+, pr
        rts
        nop

        .align  2
c_cd_hirq:      .long   0x25890008
c_cd_cr1:       .long   0x25890018
c_cd_wait:      .long   0x00400000
c_not_cmok:     .word   0xFFFE
c_play_cr1:     .word   0x1000
c_track2:       .word   0x0201
c_play_cr3:     .word   0x0F00
        .align  2
s_audio:        .asciz  "CD AUDIO TRACKS 2+3"

        .align  2
c_sysbase:      .long   0x06000200
c_back:         .long   BACK
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
        .long   n_bupi,   t_bupinit
        .long   n_bupw,   t_bupwrite
        .long   n_bupr,   t_bupread
        .long   n_bupd,   t_bupdir
        .long   n_bupx,   t_bupdelete
        .long   n_date,   t_date
        .long   n_cart,   t_bupcart
        .long   0

        .align  2
s_title:        .asciz  "TEST DISC: BIOS SERVICES"
        .align  2
s_ok:           .asciz  "OK"
        .align  2
s_fail:         .asciz  "FAIL"
        .align  2
s_none:         .asciz  "NONE"
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
n_bupi:         .asciz  "BUP INIT + STAT"
        .align  2
n_bupw:         .asciz  "BUP WRITE 3000 BYTES"
        .align  2
n_bupr:         .asciz  "BUP READ + VERIFY"
        .align  2
n_bupd:         .asciz  "BUP DIRECTORY"
        .align  2
n_bupx:         .asciz  "BUP DELETE"
        .align  2
n_date:         .asciz  "BUP SET/GET DATE"
        .align  2
n_cart:         .asciz  "BUP CARTRIDGE"

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

        .align  2
c_flag:         .long   0x06016F00
c_count:        .long   0x06016F04
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
        .align  2
prio_tab:
        .long   0x00F0FFFF, 0x00E0FFFE, 0x00D0FFFC, 0x00C0FFF8
        .long   0x00B0FFF0, 0x00A0FFE0, 0x0090FFC0, 0x0080FF80
        .long   0x0080FF80, 0x0070FE00, 0x0070FE00, 0x0070FE00
        .long   0x0070FE00, 0x0070FE00, 0x0070FE00, 0x0070FE00
        .rept   16
        .long   0x0070FE00
        .endr

! ---- backup RAM -----------------------------------------------------------

! BUP_Init, check the work pointer and the device table; format the internal
! backup RAM only if it reports unformatted; then Stat must succeed.
t_bupinit:
        sts.l   pr, @-r15
        mov.l   c_bup_lib, r4
        mov.l   c_bup_work, r5
        mov.l   c_bup_conf, r6
        SYSCALL SYS_BUP_INIT
        mov.l   c_bup_work, r13
        mov.l   c_sys_bup_work, r1
        mov.l   @r1, r0
        cmp/eq  r13, r0
        bf      9f
        mov.l   c_bup_conf, r1
        mov.w   @r1, r0
        cmp/eq  #1, r0
        bf      9f
        bsr     bup_stat
        mov     #0, r5
        cmp/eq  #2, r0
        bf      1f
        mov     #0, r4
        BUPCALL 0x08                    ! Format
        bsr     bup_stat
        mov     #0, r5
1:      tst     r0, r0
        bf      9f
        mov.l   c_bup_stat, r1
        mov.l   @r1, r0                 ! total size 32768
        mov.l   c_32k, r2
        cmp/eq  r2, r0
        bf      9f
        mov.l   @(4, r1), r0            ! 512 blocks of 64 bytes
        mov.l   c_512, r2
        cmp/eq  r2, r0
        bf      9f
        mov.l   @(8, r1), r0
        cmp/eq  #64, r0
        bf      9f
        bra     pass
        nop
9:      bra     fail
        nop

! bup_stat: Stat(0, r5, BUP_STAT) -> r0
bup_stat:
        sts.l   pr, @-r15
        mov     #0, r4
        mov.l   c_bup_stat, r6
        BUPCALL 0x0C
        lds.l   @r15+, pr
        rts
        nop

! Write a 3000-byte save; the free block count must drop by 53, and a
! second write with "do not overwrite" must report that it exists (6).
t_bupwrite:
        sts.l   pr, @-r15
        mov     #0, r4                  ! remove a leftover from an earlier run
        mova    save_name, r0
        mov     r0, r5
        BUPCALL 0x18
        bsr     bup_stat
        mov     #0, r5
        mov.l   c_bup_stat, r1
        mov.l   @(16, r1), r12          ! r12 = free blocks before
        mov.l   c_bup_dirent, r1        ! directory entry
        mov     #36, r2
        mov     #0, r0
1:      mov.b   r0, @r1
        dt      r2
        bf/s    1b
        add     #1, r1
        mov.l   c_bup_dirent, r1
        mova    save_name, r0
        mov     r0, r2
2:      mov.b   @r2+, r0
        tst     r0, r0
        bt      3f
        mov.b   r0, @r1
        bra     2b
        add     #1, r1
3:      mov.l   c_bup_dirent, r1
        add     #12, r1
        mova    save_comment, r0
        mov     r0, r2
4:      mov.b   @r2+, r0
        tst     r0, r0
        bt      5f
        mov.b   r0, @r1
        bra     4b
        add     #1, r1
5:      mov.l   c_bup_dirent, r1
        mov     #3, r0                  ! language
        mov     r1, r2
        add     #23, r2
        mov.b   r0, @r2
        mov.l   c_date_val, r0
        mov.l   r0, @(24, r1)
        mov.l   c_save_size, r0
        mov.l   r0, @(28, r1)
        mov.l   c_bup_data, r1          ! data: byte i = i * 7 + 3
        mov.l   c_save_size, r2
        mov     #3, r0
6:      mov.b   r0, @r1
        add     #7, r0
        dt      r2
        bf/s    6b
        add     #1, r1
        mov     #0, r4
        mov.l   c_bup_dirent, r5
        mov.l   c_bup_data, r6
        mov     #1, r7
        BUPCALL 0x10                    ! Write
        tst     r0, r0
        bf      9f
        bsr     bup_stat
        mov     #0, r5
        mov.l   c_bup_stat, r1
        mov.l   @(16, r1), r0
        mov     #SAVE_BLOCKS, r2
        add     r2, r0
        cmp/eq  r12, r0
        bf      9f
        mov     #0, r4
        mov.l   c_bup_dirent, r5
        mov.l   c_bup_data, r6
        mov     #1, r7
        BUPCALL 0x10                    ! again, must not overwrite
        cmp/eq  #6, r0
        bf      9f
        mov.l   c_free_before, r1
        mov.l   r12, @r1
        bra     pass
        nop
9:      bra     fail
        nop

! Read the save back and compare; Verify must pass, and fail (7) once one
! byte of the reference data is changed.
t_bupread:
        sts.l   pr, @-r15
        mov.l   c_bup_buf, r1
        mov.l   c_save_size, r2
        mov     #0, r0
1:      mov.b   r0, @r1
        dt      r2
        bf/s    1b
        add     #1, r1
        mov     #0, r4
        mova    save_name, r0
        mov     r0, r5
        mov.l   c_bup_buf, r6
        BUPCALL 0x14                    ! Read
        tst     r0, r0
        bf      9f
        mov.l   c_bup_data, r1
        mov.l   c_bup_buf, r2
        mov.l   c_save_size, r3
2:      mov.b   @r1+, r0
        mov.b   @r2+, r4
        cmp/eq  r4, r0
        bf      9f
        dt      r3
        bf      2b
        mov     #0, r4
        mova    save_name, r0
        mov     r0, r5
        mov.l   c_bup_data, r6
        BUPCALL 0x20                    ! Verify
        tst     r0, r0
        bf      9f
        mov.l   c_bup_data, r1          ! change one byte
        mov.l   c_1500, r0
        add     r0, r1
        mov.b   @r1, r0
        not     r0, r0
        mov.b   r0, @r1
        mov     #0, r4
        mova    save_name, r0
        mov     r0, r5
        mov.l   c_bup_data, r6
        BUPCALL 0x20
        mov     r0, r12
        mov.l   c_bup_data, r1          ! restore it
        mov.l   c_1500, r0
        add     r0, r1
        mov.b   @r1, r0
        not     r0, r0
        mov.b   r0, @r1
        mov     r12, r0
        cmp/eq  #7, r0
        bf      9f
        bra     pass
        nop
9:      bra     fail
        nop

! Directory: the save must be listed with its size, block count, date and
! language; a table of 0 entries must return minus the number of saves.
t_bupdir:
        sts.l   pr, @-r15
        mov     #0, r4
        mova    save_name, r0
        mov     r0, r5
        mov     #8, r6
        mov.l   c_bup_dirtab, r7
        BUPCALL 0x1C
        cmp/eq  #1, r0
        bf      9f
        mov.l   c_bup_dirtab, r1
        mova    save_name, r0
        mov     r0, r2
1:      mov.b   @r2+, r0
        mov.b   @r1+, r3
        cmp/eq  r3, r0
        bf      9f
        tst     r0, r0
        bf      1b
        mov.l   c_bup_dirtab, r1
        mov.l   @(24, r1), r0
        mov.l   c_date_val, r2
        cmp/eq  r2, r0
        bf      9f
        mov.l   @(28, r1), r0
        mov.l   c_save_size, r2
        cmp/eq  r2, r0
        bf      9f
        mov     r1, r2
        add     #32, r2
        mov.w   @r2, r0
        cmp/eq  #SAVE_BLOCKS, r0
        bf      9f
        add     #-9, r2                 ! language at 23
        mov.b   @r2, r0
        cmp/eq  #3, r0
        bf      9f
        mov     #0, r4
        mova    save_name, r0
        mov     r0, r5
        mov     #0, r6
        mov.l   c_bup_dirtab, r7
        BUPCALL 0x1C
        cmp/eq  #-1, r0
        bf      9f
        bra     pass
        nop
9:      bra     fail
        nop

! Delete: afterwards Read reports not found (5) and the free block count is
! back to what it was before the write.
t_bupdelete:
        sts.l   pr, @-r15
        mov     #0, r4
        mova    save_name, r0
        mov     r0, r5
        BUPCALL 0x18
        tst     r0, r0
        bf      9f
        mov     #0, r4
        mova    save_name, r0
        mov     r0, r5
        mov.l   c_bup_buf, r6
        BUPCALL 0x14
        cmp/eq  #5, r0
        bf      9f
        bsr     bup_stat
        mov     #0, r5
        mov.l   c_bup_stat, r1
        mov.l   @(16, r1), r0
        mov.l   c_free_before, r1
        mov.l   @r1, r1
        cmp/eq  r1, r0
        bf      9f
        bra     pass
        nop
9:      bra     fail
        nop

! Dates: SetDate and GetDate against values computed independently
! (minutes since 1980-01-01 00:00; week 0 = Sunday).
! Backup RAM cartridge (device 1), if BUP_Init reported one: format it if
! needed, check its geometry, write the 3000-byte save from t_bupwrite,
! read it back, delete it; the free block count must return to where it
! was. Returns 2 (NONE) without a cartridge.
t_bupcart:
        sts.l   pr, @-r15
        mov.l   c_bup_conf, r1
        mov.w   @(4, r1), r0            ! device 1 unit: 2 = cartridge
        cmp/eq  #2, r0
        bt      1f
        lds.l   @r15+, pr
        rts
        mov     #2, r0
1:      bsr     cart_stat
        nop
        cmp/eq  #2, r0
        bf      2f
        mov     #1, r4
        BUPCALL 0x08                    ! Format
        bsr     cart_stat
        nop
2:      tst     r0, r0
        bf      9f
        mov.l   c_bup_stat, r1
        mov.l   @(8, r1), r0            ! blocks of 512 or 1024 bytes
        mov.w   c_cart_512, r2
        cmp/eq  r2, r0
        bt      3f
        shll    r2
        cmp/eq  r2, r0
        bf      9f
3:      mov.l   @(4, r1), r0            ! at least 1024 blocks
        mov.w   c_cart_1024, r2
        cmp/hs  r2, r0
        bf      9f
        mov     #1, r4                  ! remove a leftover
        mova    save_name, r0
        mov     r0, r5
        BUPCALL 0x18
        bsr     cart_stat
        nop
        mov.l   c_bup_stat, r1
        mov.l   @(16, r1), r12          ! r12 = free blocks before
        mov     #1, r4
        mov.l   c_bup_dirent, r5
        mov.l   c_bup_data, r6
        mov     #1, r7
        BUPCALL 0x10                    ! Write
        tst     r0, r0
        bf      9f
        mov.l   c_bup_buf, r1           ! Read back and compare
        mov.l   c_save_size, r2
        mov     #0, r0
4:      mov.b   r0, @r1
        dt      r2
        bf/s    4b
        add     #1, r1
        mov     #1, r4
        mova    save_name, r0
        mov     r0, r5
        mov.l   c_bup_buf, r6
        BUPCALL 0x14
        tst     r0, r0
        bf      9f
        mov.l   c_bup_data, r1
        mov.l   c_bup_buf, r2
        mov.l   c_save_size, r3
5:      mov.b   @r1+, r0
        mov.b   @r2+, r4
        cmp/eq  r4, r0
        bf      9f
        dt      r3
        bf      5b
        mov     #1, r4                  ! Delete: free count back
        mova    save_name, r0
        mov     r0, r5
        BUPCALL 0x18
        tst     r0, r0
        bf      9f
        bsr     cart_stat
        nop
        mov.l   c_bup_stat, r1
        mov.l   @(16, r1), r0
        cmp/eq  r12, r0
        bf      9f
        mov.l   @r1, r4                 ! show the total size found
        mov     #18, r5                 ! (r9 = this test's row)
        bsr     puthex
        mov     r9, r6
        bra     pass
        nop
9:      bra     fail
        nop

! cart_stat: Stat(1, 3000, BUP_STAT) -> r0
cart_stat:
        sts.l   pr, @-r15
        mov     #1, r4
        mov.l   c_save_size, r5
        mov.l   c_bup_stat, r6
        BUPCALL 0x0C
        lds.l   @r15+, pr
        rts
        nop

        .align  2
c_cart_512:     .word   512
c_cart_1024:    .word   1024

        .align  2
t_date:
        sts.l   pr, @-r15
        mova    date_cases, r0
        mov     r0, r12
        mov     #4, r11
1:      mov     r12, r4                 ! SetDate(fields) == minutes
        BUPCALL 0x28
        mov.l   @(8, r12), r1
        cmp/eq  r1, r0
        bf      9f
        mov     r0, r4                  ! GetDate(minutes) == fields
        mov.l   c_bup_date, r5
        BUPCALL 0x24
        mov.l   c_bup_date, r1
        mov     r12, r2
        mov     #6, r3
2:      mov.b   @r1+, r0
        mov.b   @r2+, r4
        cmp/eq  r4, r0
        bf      9f
        dt      r3
        bf      2b
        dt      r11
        bf/s    1b
        add     #12, r12
        bra     pass
        nop
9:      bra     fail
        nop

        .align  2
date_cases:     ! year-1980, month, day, hour, minute, week, pad; minutes
        .byte   46, 9, 27, 12, 5, 0, 0, 0
        .long   24582965                ! 2026-09-27 12:05, Sunday
        .byte   44, 2, 29, 23, 59, 4, 0, 0
        .long   23228639                ! 2024-02-29 23:59, Thursday
        .byte   0, 12, 31, 0, 0, 3, 0, 0
        .long   525600                  ! 1980-12-31 00:00, Wednesday
        .byte   47, 3, 1, 6, 30, 1, 0, 0
        .long   24805830                ! 2027-03-01 06:30, Monday
        .align  2
save_name:      .asciz  "OPENBIOSTST"
        .align  2
save_comment:   .asciz  "TEST SAVE"

        .align  2
c_bup_lib:      .long   BUP_LIB
c_bup_work:     .long   BUP_WORK
c_bup_conf:     .long   BUP_CONF
c_bup_stat:     .long   BUP_STAT
c_bup_dirent:   .long   BUP_DIRENT
c_bup_date:     .long   BUP_DATE
c_bup_dirtab:   .long   BUP_DIRTAB
c_bup_data:     .long   BUP_DATA
c_bup_buf:      .long   BUP_BUF
c_sys_bup_work: .long   SYS_BUP_WORK
c_free_before:  .long   0x06016F08
c_date_val:     .long   0x01234567
c_32k:          .long   32768
c_512:          .long   512
c_save_size:    .long   SAVE_SIZE
c_1500:         .long   1500

        .align  2
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

! puthex: r4 as 8 hex digits at column r5, row r6. Clobbers r0-r3, r5, r6.
puthex:
        mov.l   c_map, r1
        shll8   r6
        shlr    r6
        add     r6, r1
        shll    r5
        add     r5, r1
        mov     #8, r3
1:      rotl    r4
        rotl    r4
        rotl    r4
        rotl    r4
        mov     r4, r0
        and     #15, r0
        mov     #10, r2
        cmp/hs  r2, r0
        bf      2f
        add     #7, r0
2:      add     #0x30, r0
        mov.w   r0, @r1
        dt      r3
        bf/s    1b
        add     #2, r1
        rts
        nop

        .align  2
c_map:          .long   MAP
c_vdp2:         .long   0x25F80000
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


