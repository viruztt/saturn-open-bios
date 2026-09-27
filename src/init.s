! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - cold-boot hardware init (clean-room, from public hardware manuals)
!
! Each *_init routine is one boot step: it may clobber r0-r7 and must preserve
! r8-r15. It returns r0 = 0 on success, nonzero on failure (boot.s prints the
! result). Hardware is accessed through the cache-through mirrors (0x2xxxxxxx).

        .section .text
        .global cpu_init
        .global wram_clear
        .global vbr_init
        .global smpc_init
        .global scu_init
        .global scsp_init
        .global vdp1_init

        .equ    WRAM_LOW,   0x20200000      ! 1 MB Work RAM Low, cache-through
        .equ    WRAM_HIGH,  0x26000000      ! 1 MB Work RAM High, cache-through
        .equ    SND_RAM,    0x25A00000      ! 512 KB sound RAM
        .equ    SCSP,       0x25B00000
        .equ    VDP1_VRAM,  0x25C00000
        .equ    VDP1_REGS,  0x25D00000
        .equ    SCU,        0x25FE0000
        .equ    SMPC_COMREG, 0x2010001F
        .equ    SMPC_SF,    0x20100063

        .equ    SMPC_SSHOFF, 0x03           ! hold the slave SH-2 in reset
        .equ    SMPC_SNDOFF, 0x07           ! hold the sound 68000 in reset

! cpu_init: quiesce the master SH-2 on-chip peripherals (interrupt priorities,
! DMAC, serial port, watchdog).
! TODO: bus state controller (BCR1/2, WCR, MCR, refresh) and SDRAM mode setup.
! Emulators ignore it, real hardware and MiSTer need it; values must come from
! the SH7604 manual and the Saturn memory map, not guessed.
        .align  2
cpu_init:
        mova    cpu_tab, r0
        mov     r0, r4
        mov.l   c_wtcsr, r1
        mov.w   c_wdt_stop, r0
        mov.w   r0, @r1                 ! WTCSR = 0x18: watchdog timer stopped
        mov.l   c_scr, r1
        mov     #0, r0
        mov.b   r0, @r1                 ! SCR = 0: serial port off
        bra     poke_w
        nop

! wram_clear: zero both 1 MB Work RAM banks. Must run before anything is
! pushed on the stack (stack lives at the top of Work RAM High).
        .align  2
wram_clear:
        mov     #0, r0
        mov.l   c_wram_low, r1
        mov.l   c_wram_longs, r2
1:      mov.l   r0, @r1
        dt      r2
        bf/s    1b
        add     #4, r1
        mov.l   c_wram_high, r1
        mov.l   c_wram_longs, r2
2:      mov.l   r0, @r1
        dt      r2
        bf/s    2b
        add     #4, r1
        rts
        nop

! vbr_init: copy the ROM vector table to the start of Work RAM High and point
! VBR at it, where games expect to find (and patch) the master's vectors.
        .align  2
vbr_init:
        mov     #0, r1
        mov.l   c_wram_high, r2
        mov     #64, r3
        shll    r3                      ! 128 vectors
1:      mov.l   @r1+, r0
        mov.l   r0, @r2
        dt      r3
        bf/s    1b
        add     #4, r2
        mov.l   c_vbr, r0
        ldc     r0, vbr
        rts
        mov     #0, r0

! smpc_init: make sure the slave SH-2 and the sound CPU are held in reset.
        .align  2
smpc_init:
        sts.l   pr, @-r15
        bsr     smpc_cmd
        mov     #SMPC_SSHOFF, r4
        tst     r0, r0
        bf      9f
        bsr     smpc_cmd
        mov     #SMPC_SNDOFF, r4
9:      lds.l   @r15+, pr
        rts
        nop

! smpc_cmd: r4 = command. Waits for SF clear, issues it, waits for completion.
! Returns r0 = 0, or 1 if the SMPC stayed busy.
        .align  2
smpc_cmd:
        mov.l   c_smpc_sf, r1
        mov.l   c_timeout, r2
1:      mov.b   @r1, r0
        tst     #1, r0
        bt      2f
        dt      r2
        bf      1b
        rts
        mov     #1, r0
2:      mov     #1, r0
        mov.b   r0, @r1                 ! SF = 1: command pending
        mov.l   c_smpc_comreg, r3
        mov.b   r4, @r3
        mov.l   c_timeout, r2
3:      mov.b   @r1, r0
        tst     #1, r0
        bt      4f
        dt      r2
        bf      3b
        rts
        mov     #1, r0
4:      rts
        mov     #0, r0

! scu_init: stop SCU DMA and timers, mask and clear all SCU interrupts.
! TODO: A-bus set/refresh (ASR0, ASR1, AREF) and SDRAM select (RSEL).
        .align  2
scu_init:
        mova    scu_tab, r0
        mov     r0, r4
        bra     poke_l
        nop

! scsp_init: silence the sound chip. The 68000 is already held in reset by
! smpc_init, so sound RAM can be cleared from here.
        .align  2
scsp_init:
        mov     #0, r0
        mov.l   c_snd_ram, r1
        mov.l   c_snd_longs, r2
1:      mov.l   r0, @r1
        dt      r2
        bf/s    1b
        add     #4, r1
        mov.l   c_scsp, r1              ! zero the 32 slots x 32 bytes
        mov.w   c_slot_words, r2
2:      mov.w   r0, @r1
        dt      r2
        bf/s    2b
        add     #2, r1
        mova    scsp_tab, r0
        mov     r0, r4
        bra     poke_w
        nop

! vdp1_init: clear VDP1 VRAM, leave a lone END command so nothing is drawn,
! and set a 320x224 erase window.
        .align  2
vdp1_init:
        mov     #0, r0
        mov.l   c_vdp1_vram, r1
        mov.l   c_snd_longs, r2         ! also 512 KB
1:      mov.l   r0, @r1
        dt      r2
        bf/s    1b
        add     #4, r1
        mova    vdp1_tab, r0
        mov     r0, r4
        bra     poke_w
        nop

! poke_l / poke_w: r4 = table of (.long address, .long value) pairs ending in
! address 0; writes each value as a longword / word. Returns r0 = 0.
        .align  2
poke_l:
        mov.l   @r4+, r1
        tst     r1, r1
        bt      9f
        mov.l   @r4+, r0
        bra     poke_l
        mov.l   r0, @r1
9:      rts
        mov     #0, r0

        .align  2
poke_w:
        mov.l   @r4+, r1
        tst     r1, r1
        bt      9f
        mov.l   @r4+, r0
        bra     poke_w
        mov.w   r0, @r1
9:      rts
        mov     #0, r0

        .align  2
c_wram_low:     .long   WRAM_LOW
c_wram_high:    .long   WRAM_HIGH
c_wram_longs:   .long   0x100000 / 4
c_vbr:          .long   0x06000000
c_smpc_sf:      .long   SMPC_SF
c_smpc_comreg:  .long   SMPC_COMREG
c_timeout:      .long   0x00100000
c_snd_ram:      .long   SND_RAM
c_snd_longs:    .long   0x80000 / 4
c_scsp:         .long   SCSP
c_vdp1_vram:    .long   VDP1_VRAM
c_wtcsr:        .long   0xFFFFFE80
c_scr:          .long   0xFFFFFE02
c_wdt_stop:     .word   0xA518          ! 0xA5 = WTCSR write key
c_slot_words:   .word   0x400 / 2

        .align  2
cpu_tab:
        .long   0xFFFFFEE2, 0           ! IPRA: DIVU/DMAC/WDT priority 0
        .long   0xFFFFFE60, 0           ! IPRB: SCI/FRT priority 0
        .long   0

        .align  2
scu_tab:
        .long   SCU + 0x10, 0           ! D0EN: DMA level 0 off
        .long   SCU + 0x30, 0           ! D1EN: DMA level 1 off
        .long   SCU + 0x50, 0           ! D2EN: DMA level 2 off
        .long   SCU + 0x98, 0           ! T1MD: timer 1 off
        .long   SCU + 0xA0, 0x0000BFFF  ! IMS: mask every SCU interrupt
        .long   SCU + 0xA4, 0           ! IST: clear pending interrupts
        .long   0

        .align  2
scsp_tab:
        .long   SCSP + 0x000, 0x1000    ! KYONEX: apply key-off to all slots
        .long   SCSP + 0x400, 0x0200    ! MEM4MB (512 KB sound RAM), MVOL 0
        .long   SCSP + 0x41E, 0         ! SCIEB: 68000 interrupts off
        .long   SCSP + 0x422, 0x07FF    ! SCIRE: ack all
        .long   SCSP + 0x42A, 0         ! MCIEB: main CPU interrupts off
        .long   SCSP + 0x42E, 0x07FF    ! MCIRE: ack all
        .long   0

        .align  2
vdp1_tab:
        .long   VDP1_VRAM, 0x8000       ! command 0: END
        .long   VDP1_REGS + 0x0, 0      ! TVMR: 16-bit, no rotation
        .long   VDP1_REGS + 0x2, 0      ! FBCR: auto frame buffer change
        .long   VDP1_REGS + 0x4, 0      ! PTMR: no plotting until a game asks
        .long   VDP1_REGS + 0x6, 0      ! EWDR: erase to colour 0
        .long   VDP1_REGS + 0x8, 0      ! EWLR: erase window top-left 0,0
        .long   VDP1_REGS + 0xA, (39 << 9) | 223   ! EWRR: bottom-right 319,223
        .long   0
