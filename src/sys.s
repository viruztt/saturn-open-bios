! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - system calls and SCU interrupt dispatch (clean-room)
!
! Games reach BIOS services through function pointers at fixed addresses in
! the system area (Work RAM High 0x06000000-0x06001FFF). Addresses and
! behaviour follow Yabause's HLE BIOS (bios.c, GPL-2.0-or-later), used as a
! behavioural reference; the code here is our own.
!
! System area layout used here:
!   0x06000000-0x060001FF  master vector table (VBR)
!   0x06000200-0x060003FF  system call pointers and variables
!   0x06000400-0x060005FF  slave vector table
!   0x06000600             "rte" stub (default CPU vector)
!   0x06000610             "rts" stub (default SCU user handler)
!   0x06000900 + 4*vector  SCU user handlers, vectors 0x40-0x5F
!   0x06000B00-0x06000B1F  semaphores (one byte each)
!   0x06000C00-0x06000C7F  SCU interrupt priority table (32 longwords:
!                          SR value << 16 | SCU mask bits)
!   0x06000D00-0x060017FF  BIOS boot work area (cd.s, disc.s), free after boot
!   below 0x06002000       boot stack (the game's default master stack)

        .section .text
        .global sys_init
        .global sys_default_vector
        .global sc_power_clear, sc_cd_player, sc_mpeg_check, sc_cd_init2
        .global sc_cd_init1, sc_change_prio, sc_set_scu_int, sc_get_scu_int
        .global sc_set_sh2_int, sc_get_sh2_int, sc_change_clock, sc_get_sem
        .global sc_clear_sem, sc_set_scu_mask, sc_change_scu_mask

! CALL address, service: one call table entry. Diagnostic builds point it at
! a counting wrapper (diag.s) instead.
        .macro  CALL addr, service
        .ifdef  DIAG
        .long   \addr, diag_w_\service
        .else
        .long   \addr, \service
        .endif
        .endm

        .equ    SYS,        0x26000000      ! system area, cache-through
        .equ    RTE_STUB,   0x06000600
        .equ    RTS_STUB,   0x06000610
        .equ    USER_TAB,   SYS + 0xA00     ! = 0x06000900 + 4 * 0x40
        .equ    SEMAPHORES, SYS + 0xB00
        .equ    PRIO_TAB,   SYS + 0xC00
        .equ    MASK_SHADOW, SYS + 0x348
        .equ    CLOCK_MODE, SYS + 0x324
        .equ    SCU_IMS,    0x25FE00A0
        .equ    SCU_IST,    0x25FE00A4
        .equ    SCU_AIACK,  0x25FE00A8
        .equ    SMPC_COMREG, 0x2010001F
        .equ    SMPC_SF,    0x20100063

! sys_init: boot step. Fill the system call table, the SCU user handler and
! priority tables, and point the SCU vectors (0x40-0x4D, 0x50-0x5F) of the
! master vector table at the dispatcher. Must run after vbr_init.
        .align  2
sys_init:
        sts.l   pr, @-r15
        mova    call_tab, r0            ! (address, value) pairs
        mov     r0, r1
1:      mov.l   @r1+, r2
        tst     r2, r2
        bt      2f
        mov.l   @r1+, r0
        bra     1b
        mov.l   r0, @r2
2:      mov.l   c_rts_stub_w, r1        ! rts stub
        mov.l   c_rts_nop, r0
        mov.l   r0, @r1
        mov.l   c_user_tab, r1          ! user handlers default to the rts stub
        mov.l   c_rts_stub, r0
        mov     #32, r2
3:      mov.l   r0, @r1
        dt      r2
        bf/s    3b
        add     #4, r1
        mova    prio_default, r0        ! default priorities
        mov     r0, r1
        mov.l   c_prio_tab, r2
        mov     #32, r3
4:      mov.l   @r1+, r0
        mov.l   r0, @r2
        dt      r3
        bf/s    4b
        add     #4, r2
        mov     #0x40, r4               ! SCU vectors -> dispatcher entries
5:      bsr     sys_default_vector
        nop
        mov.l   c_sys, r1
        mov     r4, r2
        shll2   r2
        add     r2, r1
        mov.l   r0, @r1
        add     #1, r4
        mov     #0x60, r0
        cmp/eq  r0, r4
        bf      5b
        lds.l   @r15+, pr
        rts
        mov     #0, r0

! sys_default_vector: r4 = CPU vector number; returns in r0 the handler the
! BIOS installs there by default. Clobbers r1.
        .align  2
sys_default_vector:
        mov     r4, r0
        cmp/eq  #4, r0                  ! fatal CPU exceptions halt
        bt      8f
        cmp/eq  #6, r0
        bt      8f
        cmp/eq  #9, r0
        bt      8f
        cmp/eq  #10, r0
        bt      8f
        mov     #0x40, r1               ! SCU vectors 0x40-0x4D, 0x50-0x5F
        cmp/hs  r1, r4
        bf      9f
        mov     #0x60, r1
        cmp/hs  r1, r4
        bt      9f
        cmp/eq  #0x4E, r0
        bt      9f
        cmp/eq  #0x4F, r0
        bt      9f
        mov.l   c_entries, r1           ! dispatcher entry: 8 bytes per vector
        add     #-0x40, r0
        shll2   r0
        shll    r0
        rts
        add     r1, r0
8:      mov.l   c_crash, r1             ! crash screen entry for this vector
        cmp/eq  #4, r0
        bt      1f
        add     #8, r1
        cmp/eq  #6, r0
        bt      1f
        add     #8, r1
        cmp/eq  #9, r0
        bt      1f
        add     #8, r1
1:      rts
        mov     r1, r0
9:      mov.l   c_rte_stub, r0
        rts
        nop

! ---- System calls (C calling convention: args r4-r7, result r0) ---------

! 0x06000300 SetScuInterrupt(r4 = vector 0x40-0x5F, r5 = handler or 0)
        .align  2
sc_set_scu_int:
        tst     r5, r5
        bf      1f
        mov.l   c_rts_stub, r5
1:      shll2   r4
        mov.l   c_user_base, r0         ! 0x06000900 (cache-through)
        add     r0, r4
        rts
        mov.l   r5, @r4

! 0x06000304 GetScuInterrupt(r4 = vector) -> r0
        .align  2
sc_get_scu_int:
        shll2   r4
        mov.l   c_user_base, r0
        add     r0, r4
        rts
        mov.l   @r4, r0

! 0x06000310 SetSh2Interrupt(r4 = vector, r5 = handler or 0 for the default)
        .align  2
sc_set_sh2_int:
        sts.l   pr, @-r15
        tst     r5, r5
        bf      1f
        bsr     sys_default_vector
        nop
        mov     r0, r5
1:      stc     vbr, r0
        shll2   r4
        add     r0, r4
        mov.l   r5, @r4
        lds.l   @r15+, pr
        rts
        nop

! 0x06000314 GetSh2Interrupt(r4 = vector) -> r0
        .align  2
sc_get_sh2_int:
        stc     vbr, r0
        shll2   r4
        add     r0, r4
        rts
        mov.l   @r4, r0

! 0x06000340 SetScuInterruptMask(r4 = mask)
        .align  2
sc_set_scu_mask:
        mov.l   c_mask_shadow, r1
        mov.l   r4, @r1
        mov.l   c_scu_ims, r1
        mov.l   r4, @r1
        bra     ack_abus
        nop

! 0x06000344 ChangeScuInterruptMask(r4 = AND mask, r5 = OR mask)
        .align  2
sc_change_scu_mask:
        mov.l   c_mask_shadow, r1
        mov.l   @r1, r0
        and     r4, r0
        or      r5, r0
        mov.l   r0, @r1
        mov.l   c_scu_ims, r1
        mov.l   r0, @r1
        mov.l   c_scu_ist, r1           ! drop pending bits being masked
        exts.w  r4, r0
        mov.l   r0, @r1
        ! fall through
! A-bus interrupts need an acknowledge whenever they are unmasked (bit 15)
ack_abus:
        mov.l   c_mask_shadow, r1
        mov.l   @r1, r0
        mov.l   c_abus_bit, r1
        tst     r1, r0
        bf      1f
        mov.l   c_scu_aiack, r1
        mov     #1, r0
        mov.l   r0, @r1
1:      rts
        nop

! 0x06000330 GetSemaphore(r4 = number) -> r0 = 1 if acquired, else 0
        .align  2
sc_get_sem:
        mov.l   c_semaphores, r0
        add     r0, r4
        tas.b   @r4                     ! atomic: T = (byte was 0), set bit 7
        rts
        movt    r0

! 0x06000334 ClearSemaphore(r4 = number)
        .align  2
sc_clear_sem:
        mov.l   c_semaphores, r0
        add     r0, r4
        mov     #0, r0
        rts
        mov.b   r0, @r4

! 0x06000280 ChangeScuInterruptPriority(r4 = table of 32 longwords)
        .align  2
sc_change_prio:
        mov.l   c_prio_tab, r1
        mov     #32, r2
1:      mov.l   @r4+, r0
        mov.l   r0, @r1
        dt      r2
        bf/s    1b
        add     #4, r1
        rts
        nop

! 0x06000320 ChangeSystemClock(r4 = 0: 320 mode / 26.8 MHz, else 352 mode /
! 28.6 MHz). Issues SMPC CKCHG320/CKCHG352 and puts the SCU back as the
! BIOS left it. TODO: standby/NMI handshake as on real hardware.
        .align  2
sc_change_clock:
        mov.l   c_clock_mode, r1
        mov.l   r4, @r1
        mov.l   c_smpc_sf, r1           ! wait for the SMPC to be idle
        mov.l   c_timeout, r2
1:      mov.b   @r1, r0
        tst     #1, r0
        bt      2f
        dt      r2
        bf      1b
2:      mov     #1, r0
        mov.b   r0, @r1
        tst     r4, r4
        mov     #0x0F, r0               ! CKCHG320
        bt      3f
        mov     #0x0E, r0               ! CKCHG352
3:      mov.l   c_smpc_comreg, r3
        mov.b   r0, @r3
        mov.l   c_timeout, r2
4:      mov.b   @r1, r0
        tst     #1, r0
        bt      5f
        dt      r2
        bf      4b
5:      mova    clock_scu_tab, r0
        mov     r0, r1
6:      mov.l   @r1+, r2
        tst     r2, r2
        bt      7f
        mov.l   @r1+, r0
        bra     6b
        mov.l   r0, @r2
7:      mov.l   c_mask_shadow, r1
        mov.l   @r1, r0
        mov.l   c_scu_ims, r1
        mov.l   r0, @r1
        bra     ack_abus
        nop

! Services that exist but have nothing to do here yet
        .align  2
sc_nop:
sc_power_clear:
sc_cd_player:
sc_mpeg_check:
sc_cd_init2:
sc_cd_init1:
        rts
        mov     #0, r0

! ---- SCU interrupt dispatch ---------------------------------------------
! One 8-byte entry per vector 0x40-0x5F pushes r0, loads the vector number
! and joins the common dispatcher, which:
!   saves r1-r7, PR, GBR, MACH, MACL and the SCU mask shadow on the stack,
!   looks up the vector's priority entry (SR value, extra SCU mask bits),
!   masks the SCU and lowers SR to the entry's level,
!   calls the user handler at 0x06000900 + 4 * vector as a normal function,
!   then restores everything and returns with rte.
        .align  2
scu_entries:
        .irp    v, 0x40,0x41,0x42,0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4A,0x4B,0x4C,0x4D,0x4E,0x4F,0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5A,0x5B,0x5C,0x5D,0x5E,0x5F
        mov.l   r0, @-r15
        mov     #\v, r0
        bra     scu_dispatch
        nop
        .endr

scu_dispatch:
        mov.l   r1, @-r15
        .ifdef  DIAG                    ! count the vector, sample PC, SR, PR
        sts.l   pr, @-r15
        mov.l   r0, @-r15
        mov.l   r2, @-r15
        mov.l   r3, @-r15               ! stack: r3 r2 r0 pr r1 r0' PC SR
        mov.l   @(24, r15), r1
        mov.l   @(28, r15), r2
        mov.l   @(12, r15), r3
        mov.l   p_diag_irq, r0
        jsr     @r0
        mov.l   @(8, r15), r0           ! vector
        mov.l   @r15+, r3
        mov.l   @r15+, r2
        mov.l   @r15+, r0
        lds.l   @r15+, pr
        .endif
        mov.l   r2, @-r15
        mov.l   r3, @-r15
        mov.l   r4, @-r15
        mov.l   r5, @-r15
        mov.l   r6, @-r15
        mov.l   r7, @-r15
        sts.l   pr, @-r15
        stc.l   gbr, @-r15
        sts.l   mach, @-r15
        sts.l   macl, @-r15
        mov.l   c_mask_shadow, r1
        mov.l   @r1, r2
        mov.l   r2, @-r15               ! old mask
        add     #-0x40, r0
        shll2   r0                      ! r0 = (vector - 0x40) * 4
        mov.l   c_prio_tab, r3
        mov.l   @(r0, r3), r3
        mov     r3, r4
        shlr16  r4                      ! SR while the handler runs
        exts.w  r3, r3                  ! SCU mask bits (bit 15 extends)
        or      r3, r2
        mov.l   r2, @r1
        mov.l   c_scu_ims, r1
        mov.l   r2, @r1
        mov.l   c_user_tab, r5
        mov.l   @(r0, r5), r5
        ldc     r4, sr
        jsr     @r5
        nop
        mov     #0xF0, r0               ! mask CPU interrupts while restoring
        extu.b  r0, r0
        ldc     r0, sr
        mov.l   @r15+, r2
        mov.l   c_mask_shadow, r1
        mov.l   r2, @r1
        mov.l   c_scu_ims, r1
        mov.l   r2, @r1
        lds.l   @r15+, macl
        lds.l   @r15+, mach
        ldc.l   @r15+, gbr
        lds.l   @r15+, pr
        mov.l   @r15+, r7
        mov.l   @r15+, r6
        mov.l   @r15+, r5
        mov.l   @r15+, r4
        mov.l   @r15+, r3
        mov.l   @r15+, r2
        mov.l   @r15+, r1
        mov.l   @r15+, r0
        rte
        nop

        .align  2
c_sys:          .long   SYS
c_rts_stub_w:   .long   SYS + 0x610
c_rts_nop:      .long   0x000B0009      ! rts; nop
c_rts_stub:     .long   RTS_STUB
c_rte_stub:     .long   RTE_STUB
c_crash:        .long   crash_entries
c_entries:      .long   scu_entries
c_user_tab:     .long   USER_TAB
c_user_base:    .long   SYS + 0x900
c_prio_tab:     .long   PRIO_TAB
c_semaphores:   .long   SEMAPHORES
c_mask_shadow:  .long   MASK_SHADOW
c_clock_mode:   .long   CLOCK_MODE
c_scu_ims:      .long   SCU_IMS
c_scu_ist:      .long   SCU_IST
c_scu_aiack:    .long   SCU_AIACK
c_smpc_sf:      .long   SMPC_SF
c_smpc_comreg:  .long   SMPC_COMREG
c_timeout:      .long   0x00100000
c_abus_bit:     .long   0x8000
        .ifdef  DIAG
p_diag_irq:     .long   diag_irq
        .endif

! System call pointers and system variables: (address, value)
        .align  2
call_tab:
        CALL    SYS + 0x210, sc_power_clear   ! power-on memory clear
        CALL    SYS + 0x26C, sc_cd_player   ! execute CD player
        CALL    SYS + 0x274, sc_mpeg_check   ! check MPEG card
        CALL    SYS + 0x280, sc_change_prio   ! change SCU interrupt priority
        CALL    SYS + 0x29C, sc_cd_init2   ! CD init 2
        CALL    SYS + 0x2DC, sc_cd_init1   ! CD init 1
        CALL    SYS + 0x300, sc_set_scu_int   ! set SCU interrupt
        CALL    SYS + 0x304, sc_get_scu_int   ! get SCU interrupt
        CALL    SYS + 0x310, sc_set_sh2_int   ! set SH-2 interrupt
        CALL    SYS + 0x314, sc_get_sh2_int   ! get SH-2 interrupt
        CALL    SYS + 0x320, sc_change_clock   ! change system clock
        .long   SYS + 0x324, 0                  ! clock mode: 320 (26.8 MHz)
        CALL    SYS + 0x330, sc_get_sem   ! get semaphore
        CALL    SYS + 0x334, sc_clear_sem   ! clear semaphore
        CALL    SYS + 0x340, sc_set_scu_mask   ! set SCU interrupt mask
        CALL    SYS + 0x344, sc_change_scu_mask   ! change SCU interrupt mask
        .long   SYS + 0x348, 0xFFFFFFFF         ! SCU interrupt mask shadow
        .long   SYS + 0x354, 0
        CALL    SYS + 0x358, bup_init   ! backup RAM library init (bup.s)
        .long   0

! Default priorities for SCU vectors 0x40-0x5F: SR while the handler runs,
! and the SCU interrupts masked meanwhile (same order as Yabause's HLE BIOS).
        .align  2
prio_default:
        .long   0x00F0FFFF, 0x00E0FFFE, 0x00D0FFFC, 0x00C0FFF8
        .long   0x00B0FFF0, 0x00A0FFE0, 0x0090FFC0, 0x0080FF80
        .long   0x0080FF80, 0x0070FE00, 0x0070FE00, 0x0070FE00
        .long   0x0070FE00, 0x0070FE00, 0x0070FE00, 0x0070FE00
        .rept   16
        .long   0x0070FE00
        .endr

! SCU state restored after a clock change
        .align  2
clock_scu_tab:
        .long   0x25FE0010, 0                   ! D0EN
        .long   0x25FE0030, 0                   ! D1EN
        .long   0x25FE0050, 0                   ! D2EN
        .long   0x25FE0060, 0                   ! DSTP
        .long   0x25FE0080, 0                   ! PPAF: DSP stopped
        .long   0x25FE00B0, 0x1FF01FF0          ! ASR0
        .long   0x25FE00B4, 0x1FF01FF0          ! ASR1
        .long   0x25FE00B8, 0x1F                ! AREF
        .long   0x25FE0090, 0x3FF               ! T0C
        .long   0x25FE0094, 0x1FF               ! T1S
        .long   0x25FE0098, 0                   ! T1MD
        .long   0
