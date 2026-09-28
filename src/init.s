! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - cold-boot hardware init (clean-room, from public hardware manuals)
!
! Each *_init routine is one boot step: it may clobber r0-r7 and must preserve
! r8-r15. It returns r0 = 0 on success, nonzero on failure (boot.s prints the
! result). Hardware is accessed through the cache-through mirrors (0x2xxxxxxx).

        .section .text
        .global cpu_init
        .global cpu_vectors
        .global slave_start
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
! DMAC, serial port, watchdog) and give them their usual vector numbers.
! TODO: bus state controller (BCR1/2, WCR, MCR, refresh) and SDRAM mode setup.
! Emulators ignore it, real hardware and MiSTer need it; values must come from
! the SH7604 manual and the Saturn memory map, not guessed.
        .align  2
cpu_init:
        mova    cpu_tab, r0
        mov     r0, r4
        mov.l   c_wtcsr, r1
        mov.l   c_wdt_stop, r0
        mov.w   r0, @r1                 ! WTCSR = 0x18: watchdog timer stopped
        mov.l   c_scr, r1
        mov     #0, r0
        mov.b   r0, @r1                 ! SCR = 0: serial port off
        mov.l   c_dmaor, r1             ! DMAOR = 1: DMA master enable, flags
        mov     #1, r0                  ! clear. Games start SH-2 DMA channels
        mov.l   r0, @r1                 ! and wait for TE (Virtua Cop hangs
                                        ! with DME left 0 on MiSTer)
        sts.l   pr, @-r15               ! (stack not used yet: WRAM not
        bsr     poke_w                  !  cleared, but pushes are harmless)
        nop
        bsr     cpu_vectors
        nop
        mova    vec_tab_l, r0
        bsr     poke_l
        mov     r0, r4
        lds.l   @r15+, pr
        rts
        mov     #0, r0

! cpu_vectors: vector numbers for the on-chip peripherals, the same on both
! CPUs (as Yabause sets them when it starts the slave): SCI 0x60-0x63, FRT
! 0x64-0x66, WDT 0x68, BSC 0x69, DMAC 0x6C/0x6D, DIVU 0x6E. Games use the
! FRT input capture interrupt (0x64) to signal between the two CPUs.
        .align  2
cpu_vectors:
        mova    vec_tab, r0
        mov     r0, r4
        bra     poke_w
        nop
! slave_start: the slave SH-2 lands here from _start. Set up its on-chip
! vectors, FRT input capture interrupt (priority 15, enabled: the master
! signals the slave through it) and VBR (0x06000400), take its stack from
! 0x060002AC (filled at hand-over from the IP.BIN header, 0x06001000 by
! default) and jump to the entry address the game stored at 0x06000250.
! Interrupts stay masked in SR; the game lowers the mask itself.
        .align  2
slave_start:
        mov.l   c_ssp_default, r15      ! temporary stack for the calls below
        .ifdef  DIAG
        mov.l   c_diag_slave, r1
        mov.l   @r1, r0
        add     #1, r0
        mov.l   r0, @r1
        .endif
        bsr     cpu_vectors
        nop
        mova    vec_tab_l, r0
        bsr     poke_l
        mov     r0, r4
        mova    slave_irq_tab, r0
        bsr     poke_w
        mov     r0, r4
        mov.l   c_tier, r1
        mov     #0x81, r0               ! TIER: input capture interrupt on
        mov.b   r0, @r1
        .ifdef  DIAG                    ! diagnostics: sample the slave too
        mov.l   c_diag_swdt, r0
        jsr     @r0
        nop
        .endif
        mov.l   c_slave_vbr, r0
        ldc     r0, vbr
        mov.l   c_slave_stack, r1
        mov.l   @r1, r15
        tst     r15, r15
        bf      1f
        mov.l   c_ssp_default, r15
1:      mov.l   c_slave_entry, r1
        mov.l   @r1, r1
        jmp     @r1
        nop

        .align  2
vec_tab:
        .long   0xFFFFFE62, 0x6061      ! VCRA: SCI receive error / receive
        .long   0xFFFFFE64, 0x6263      ! VCRB: SCI transmit / transmit end
        .long   0xFFFFFE66, 0x6465      ! VCRC: FRT input capture / compare
        .long   0xFFFFFE68, 0x6600      ! VCRD: FRT overflow
        .long   0xFFFFFEE4, 0x6869      ! VCRWDT: WDT / BSC refresh compare
        .long   0
        .align  2
slave_irq_tab:
        .long   0xFFFFFEE0, 0x0000      ! ICR
        .long   0xFFFFFEE2, 0x0000      ! IPRA: DIVU/DMAC/WDT off
        .long   0xFFFFFE60, 0x0F00      ! IPRB: FRT priority 15
        .long   0
        .align  2
vec_tab_l:
        .long   0xFFFFFFA8, 0x6C        ! VCRDMA1
        .long   0xFFFFFFA0, 0x6D        ! VCRDMA0
        .long   0xFFFFFF0C, 0x6E        ! VCRDIV
        .long   0


! wram_clear: zero both 1 MB Work RAM banks. Must run before anything is
! pushed on the stack (the boot stack is in Work RAM High, below 0x06002000).
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

! vbr_init: build the master (0x06000000) and slave (0x06000400) vector
! tables in Work RAM High and point the master's VBR at its table. Games read
! and patch these tables. Every vector defaults to an "rte" stub at 0x06000600
! so a stray interrupt just returns; the fatal CPU exceptions (illegal
! instruction, illegal slot instruction, CPU and DMA address error) go to the
! crash screen (crash.s).
        .align  2
vbr_init:
        mov.l   c_rte_nop, r0
        mov.l   c_stub_w, r1
        mov.l   r0, @r1
        mov.l   c_stub, r0
        mov.l   c_wram_high, r1
        mov.l   c_slave_tab, r2
        mov     #64, r3
        shll    r3                      ! 128 vectors each
1:      mov.l   r0, @r1
        mov.l   r0, @r2
        add     #4, r1
        dt      r3
        bf/s    1b
        add     #4, r2
        mov.l   c_fatal, r0             ! crash entries, 8 bytes apart
        mov.l   c_wram_high, r1
        mov.l   c_slave_tab, r2
        mov.l   r0, @(4*4, r1)          ! general illegal instruction
        mov.l   r0, @(4*4, r2)
        add     #8, r0
        mov.l   r0, @(6*4, r1)          ! slot illegal instruction
        mov.l   r0, @(6*4, r2)
        add     #8, r0
        mov.l   r0, @(9*4, r1)          ! CPU address error
        mov.l   r0, @(9*4, r2)
        add     #8, r0
        mov.l   r0, @(10*4, r1)         ! DMA address error
        mov.l   r0, @(10*4, r2)
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

! scu_init: stop SCU DMA and timers, mask and clear all SCU interrupts, and set
! the A-bus timing / refresh and SDRAM select to the state a game expects.
! Values match Yabause's post-BIOS state (YabauseSpeedySetup, GPL-2.0-or-later);
! TODO: cross-check ASR0/ASR1/AREF against the SCU manual on MiSTer.
        .align  2
scu_init:
        mova    scu_tab, r0
        mov     r0, r4
        bra     poke_l
        nop

! scsp_init: silence the sound chip (all slots keyed off) and route CD audio
! to the outputs at full level, as games expect after the BIOS. The 68000 is
! already held in reset by smpc_init, so sound RAM can be cleared from here.
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

! vdp1_init: clear VDP1 VRAM, set a 320x224 erase window, and run one command
! list that sets the system clip (319,223) and local origin (160,112) then
! ends, as games expect. Fails if VDP1 never reports the list as finished.
        .align  2
vdp1_init:
        sts.l   pr, @-r15
        mov     #0, r0
        mov.l   c_vdp1_vram, r1
        mov.l   c_snd_longs, r2         ! also 512 KB
1:      mov.l   r0, @r1
        dt      r2
        bf/s    1b
        add     #4, r1
        mova    vdp1_tab, r0
        bsr     poke_w
        mov     r0, r4
        mov.l   c_vdp1_edsr, r1
        mov.l   c_timeout, r2
2:      mov.w   @r1, r0
        tst     #2, r0                  ! CEF: current frame's list ended
        bf      3f
        dt      r2
        bf      2b
        bra     9f
        mov     #1, r0
3:      mov     #0, r0
9:      lds.l   @r15+, pr
        rts
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
c_slave_tab:    .long   WRAM_HIGH + 0x400
c_stub:         .long   0x06000600
c_stub_w:       .long   WRAM_HIGH + 0x600
c_rte_nop:      .long   0x002B0009      ! rte; nop
c_fatal:        .long   crash_entries
c_vdp1_edsr:    .long   VDP1_REGS + 0x10
c_smpc_sf:      .long   SMPC_SF
c_smpc_comreg:  .long   SMPC_COMREG
c_timeout:      .long   0x00100000
c_snd_ram:      .long   SND_RAM
c_snd_longs:    .long   0x80000 / 4
c_scsp:         .long   SCSP
c_vdp1_vram:    .long   VDP1_VRAM
c_wtcsr:        .long   0xFFFFFE80
c_dmaor:        .long   0xFFFFFFB0
c_slave_vbr:    .long   0x06000400
c_tier:         .long   0xFFFFFE10
        .ifdef  DIAG
c_diag_slave:   .long   DIAG_SLAVE
c_diag_swdt:    .long   diag_start_swdt
        .endif
c_slave_stack:  .long   0x260002AC      ! system variable: slave stack
c_slave_entry:  .long   0x26000250      ! system variable: slave entry point
c_ssp_default:  .long   0x06001000
c_scr:          .long   0xFFFFFE02
c_wdt_stop:     .long   0xA518          ! 0xA5 = WTCSR write key (word write)
c_slot_words:   .word   0x400 / 2

        .align  2
cpu_tab:
        .long   0xFFFFFEE0, 0x0001      ! ICR: VECMD = 1, take interrupt vector
                                        ! numbers from the SCU (external vector
                                        ! mode); with 0 the CPU would use
                                        ! auto-vectors and never ack the SCU
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
        .long   SCU + 0xA8, 1           ! AIACK: A-bus interrupts acknowledged
        .long   SCU + 0xB0, 0x1FF01FF0  ! ASR0: A-bus CS0/CS1 timing
        .long   SCU + 0xB4, 0x1FF01FF0  ! ASR1: A-bus CS2/spare timing
        .long   SCU + 0xB8, 0x1F        ! AREF: A-bus refresh on
        .long   SCU + 0xC4, 1           ! RSEL: SDRAM select
        .long   0

        .align  2
scsp_tab:
        .long   SCSP + 0x000, 0x1000    ! KYONEX: apply key-off to all slots
        .ifndef NOMIX                   ! (NOMIX test builds: leave the mixer
                                        ! and MEM4MB/MVOL at power-on values)
        .long   SCSP + 0x216, 0x001F    ! slot 16 = CD audio left: EFSDL 0,
        .long   SCSP + 0x236, 0x000F    ! slot 17 = CD audio right: EFSDL 0,
                                        ! EFPAN 0x1F left, 0x0F right; the
                                        ! level is raised at hand-over
                                        ! (boot_game), so CD audio plays for
                                        ! games that do not set up the mixer
        .long   SCSP + 0x400, 0x020F    ! MEM4MB (512 KB sound RAM), MVOL 15
        .endif
        .long   SCSP + 0x41E, 0         ! SCIEB: 68000 interrupts off
        .long   SCSP + 0x422, 0x07FF    ! SCIRE: ack all
        .long   SCSP + 0x42A, 0         ! MCIEB: main CPU interrupts off
        .long   SCSP + 0x42E, 0x07FF    ! MCIRE: ack all
        .long   0

        .align  2
vdp1_tab:
        .long   VDP1_VRAM + 0x00, 0x0009   ! command 0: system clipping
        .long   VDP1_VRAM + 0x14, 319      !   XC
        .long   VDP1_VRAM + 0x16, 223      !   YC
        .long   VDP1_VRAM + 0x20, 0x000A   ! command 1: local coordinates
        .long   VDP1_VRAM + 0x2C, 160      !   XA
        .long   VDP1_VRAM + 0x2E, 112      !   YA
        .long   VDP1_VRAM + 0x40, 0x8000   ! command 2: END
        .long   VDP1_REGS + 0x0, 0      ! TVMR: 16-bit, no rotation
        .long   VDP1_REGS + 0x2, 0      ! FBCR: auto frame buffer change
        .long   VDP1_REGS + 0x6, 0      ! EWDR: erase to colour 0
        .long   VDP1_REGS + 0x8, 0      ! EWLR: erase window top-left 0,0
        .long   VDP1_REGS + 0xA, (39 << 9) | 223   ! EWRR: bottom-right 319,223
        .long   VDP1_REGS + 0x4, 1      ! PTMR: draw the list once, now (last)
        .long   0
