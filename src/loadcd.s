! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - "load CD" system calls (clean-room)
!
! Boot loaders such as Pseudo Saturn and Action Replay style cartridges
! boot a disc through three system calls, used in this order (as described
! by the GPL iapetus library's bios.h):
!   0x0600029C  init: reset the CD block's selectors and the BIOS's own
!               boot state (and start a disc authentication)
!   0x060002CC  read: start reading the disc's first 16 sectors
!   0x06000288  boot: take IP.BIN to 0x06002000, check it and boot the disc
! Each returns an int, negative on failure. Here init and read only prepare
! the CD block, and boot runs the BIOS's own disc boot (the same steps as
! at power-on: TOC, IP.BIN, first read file, hand-over), so a loader gets
! exactly the start-up a game gets from the BIOS. Boot returns -1 if the
! disc cannot be booted.

        .section .text
        .global sc_cd_init2
        .global sc_loadcd_read
        .global sc_loadcd_boot

        .align  2
sc_cd_init2:                            ! 0x0600029C: load CD init
        sts.l   pr, @-r15
        mov.l   p_lc_handover, r0       ! end transfers, no connection,
        jsr     @r0                     ! selectors reset
        nop
        lds.l   @r15+, pr
        rts
        mov     #0, r0

sc_loadcd_read:                         ! 0x060002CC: load CD read
        rts                             ! (boot reads what it needs)
        mov     #0, r0

        .align  2
sc_loadcd_boot:                         ! 0x06000288: load CD boot
        sts.l   pr, @-r15
        mov.l   p_lc_handover, r0       ! drop whatever the caller buffered
        jsr     @r0
        nop
        mov.l   p_lc_toc, r0
        jsr     @r0
        nop
        tst     r0, r0
        bf      9f
        mov.l   p_lc_read_ip, r0
        jsr     @r0
        nop
        tst     r0, r0
        bf      9f
        mov.l   p_lc_ip_load, r0
        jsr     @r0
        nop
        tst     r0, r0
        bf      9f
        mov.l   p_lc_first_read, r0
        jsr     @r0
        nop
        tst     r0, r0
        bf      9f
        mov.l   p_lc_boot_game, r0      ! does not return
        jmp     @r0
        nop
9:      lds.l   @r15+, pr
        rts
        mov     #-1, r0

        .align  2
p_lc_handover:  .long   cd_handover
p_lc_toc:       .long   cd_toc
p_lc_read_ip:   .long   cd_read_ip
p_lc_ip_load:   .long   ip_load
p_lc_first_read: .long  first_read
p_lc_boot_game: .long   boot_game
