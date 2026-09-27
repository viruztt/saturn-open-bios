! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - disc boot: IP.BIN, first read file, hand-over (clean-room)
!
! Written from the public disc format description (IP.BIN header layout,
! ISO 9660) with Yabause's quick-load path (YabauseQuickLoadGame,
! GPL-2.0-or-later) as a behavioural reference.
!
! No lockout: the security code area is only checked for presence (the IP
! size must cover it), never compared against Sega's code, and area symbols
! are shown but not enforced (region free by design).
!
! Steps follow the boot.s convention: clobber r0-r7, preserve r8-r15,
! return r0 = 0 on success.

        .section .text
        .global ip_load
        .global first_read
        .global boot_game
        .global FR_ADDR
        .global FR_SIZE
        .global IP_AREA

        .equ    IP_BUF,     0x26002000      ! 0x06002000, cache-through
        .equ    IP_SIZE,    IP_BUF + 0xE0
        .equ    IP_MSTACK,  IP_BUF + 0xE8
        .equ    IP_FIRST,   IP_BUF + 0xF0   ! first read file load address
        .equ    IP_MIN,     0xE00 + 0x20    ! header + security code + 1 area code
        .equ    IP_MAX,     0x8000          ! 16 sectors
        .equ    ENTRY,      0x06002E00      ! first code after the security code

        .equ    DISC_VARS,  0x26000F00      ! BIOS boot work area (see sys.s)
        .equ    FR_ADDR,    DISC_VARS + 0x00
        .equ    FR_SIZE,    DISC_VARS + 0x04
        .equ    IP_AREA,    DISC_VARS + 0x08 ! area symbols, 10 chars + NUL
        .equ    SCRATCH,    0x26001000      ! one sector, up to 0x060017FF

! ip_load: check the hardware ID of the sector cd_read_ip loaded, then read
! the whole IP.BIN (size from its header) to 0x06002000.
        .align  2
ip_load:
        sts.l   pr, @-r15
        mov.l   c_ip_buf, r1
        mova    sega_id, r0
        mov     r0, r2
        mov     #16, r3
1:      mov.b   @r1+, r0
        mov.b   @r2+, r4
        cmp/eq  r4, r0
        bf      8f
        dt      r3
        bf      1b
        mov.l   c_ip_size, r1
        mov.l   @r1, r7                 ! bytes
        mov.w   c_ip_min, r0
        cmp/hs  r0, r7
        bf      8f                      ! too small to hold the security code
        mov.l   c_ip_max, r0
        cmp/hi  r0, r7
        bt      8f
        mov     r7, r5                  ! sectors = (bytes + 2047) / 2048
        mov.w   c_2047, r0
        add     r0, r5
        shlr8   r5
        shlr2   r5
        shlr    r5
        mov.w   c_fad150, r4
        mov.l   c_ip_buf, r6
        mov.l   p_cd_read, r0
        jsr     @r0
        nop
        tst     r0, r0
        bf      9f
        mov.l   c_ip_area_src, r1       ! keep the area symbols for display
        mov.l   c_ip_area, r2
        mov     #10, r3
2:      mov.b   @r1+, r0
        mov.b   r0, @r2
        dt      r3
        bf/s    2b
        add     #1, r2
        mov     #0, r0
        bra     9f
        mov.b   r0, @r2
8:      mov     #1, r0
9:      lds.l   @r15+, pr
        rts
        nop

! first_read: find the first file in the root directory of the ISO 9660
! file system and load it to the address given in the IP.BIN header.
        .align  2
first_read:
        sts.l   pr, @-r15
        mov.l   r8, @-r15
        mov.l   r9, @-r15
        mov.w   c_fad166, r4            ! primary volume descriptor (LBA 16)
        bsr     read_scratch
        nop
        tst     r0, r0
        bf      9f
        mov.l   c_scratch, r1
        mov.b   @r1, r0
        cmp/eq  #1, r0                  ! type 1 = primary
        bf      8f
        mov.b   @(1, r1), r0
        cmp/eq  #'C', r0                ! "CD001"
        bf      8f
        mov.l   c_scratch, r4
        mov.w   c_root_lba, r0
        bsr     rd_be32
        add     r0, r4
        mov.w   c_fad150, r4            ! root directory, first sector
        bsr     read_scratch
        add     r0, r4
        tst     r0, r0
        bf      9f
        mov.l   c_scratch, r9           ! skip "." and ".."
        mov.b   @r9, r0
        extu.b  r0, r0
        tst     r0, r0
        bt      8f
        add     r0, r9
        mov.b   @r9, r0
        extu.b  r0, r0
        tst     r0, r0
        bt      8f
        add     r0, r9
        mov.b   @r9, r0
        extu.b  r0, r0
        tst     r0, r0
        bt      8f
        mov     r9, r4
        bsr     rd_be32                 ! extent LBA (big-endian copy)
        add     #6, r4
        mov     r0, r8
        mov     r9, r4
        bsr     rd_be32                 ! data length (big-endian copy)
        add     #14, r4
        mov     r0, r7
        tst     r7, r7
        bt      8f
        mov.l   c_fr_size, r1
        mov.l   r7, @r1
        mov.l   c_ip_first, r1
        mov.l   @r1, r6
        mov.l   c_fr_addr, r1
        mov.l   r6, @r1
        mov     r6, r4                  ! destination must lie in Work RAM
        bsr     check_dest
        mov     r7, r5
        tst     r0, r0
        bf      9f
        mov.l   c_uncached, r0
        or      r0, r6
        mov     r7, r5                  ! sectors = (bytes + 2047) / 2048
        mov.w   c_2047, r0
        add     r0, r5
        shlr8   r5
        shlr2   r5
        shlr    r5
        mov.w   c_fad150, r4
        add     r8, r4
        mov.l   p_cd_read, r0
        jsr     @r0
        nop
        bra     9f
        nop
8:      mov     #1, r0
9:      mov.l   @r15+, r9
        mov.l   @r15+, r8
        lds.l   @r15+, pr
        rts
        nop

! check_dest: r4 = load address, r5 = size. Returns r0 = 0 if the whole range
! is inside Work RAM Low (0x00200000-0x002FFFFF) or inside Work RAM High
! from 0x06002000 up (0x06002000-0x060FFFFF), i.e. never over the system
! area, vector tables or the BIOS stack below 0x06002000. Loading over the
! tail of IP.BIN is allowed: games do it (e.g. a first read file at
! 0x06003C00 with an IP size of 0x8000). Clobbers r1, r2.
        .align  2
check_dest:
        add     r4, r5                  ! r5 = end (exclusive)
        cmp/hs  r4, r5                  ! reject wrap-around
        bf      8f
        mov.l   c_low_start, r1
        cmp/hs  r1, r4
        bf      8f
        mov.l   c_low_end, r1
        cmp/hi  r1, r5
        bf      7f                      ! end <= low end: inside Low
        mov.l   c_high_start, r1
        cmp/hs  r1, r4
        bf      8f
        mov.l   c_high_end, r1
        cmp/hi  r1, r5
        bt      8f
7:      rts
        mov     #0, r0
8:      rts
        mov     #1, r0

! read_scratch: r4 = FAD; reads one sector into SCRATCH. Returns cd_read's r0.
        .align  2
read_scratch:
        mov     #1, r5
        mov.l   c_scratch, r6
        mov.w   c_2048, r7
        mov.l   p_cd_read, r0
        jmp     @r0
        nop

! rd_be32: r4 = address (any alignment); returns the big-endian longword there
! in r0. Clobbers r1, r2, r4.
        .align  2
rd_be32:
        mov     #4, r2
        mov     #0, r0
1:      shll8   r0
        mov.b   @r4+, r1
        extu.b  r1, r1
        or      r1, r0
        dt      r2
        bf      1b
        rts
        nop

! boot_game: hand over to the disc. State as a game expects it after the
! BIOS: VBR = 0x06000000 (vbr_init), stack from the IP.BIN header
! (0x06002000 if zero), R0-R14, GBR, MACH/MACL, PR and SR all zero, the
! cache purged and enabled, CD audio mixed in (slots 16/17) and execution
! at 0x06002E00. The header's slave stack (0x06001000 if zero) is kept at
! 0x060002AC for slave_start. Does not return.
        .align  2
boot_game:
        mov.l   c_ip_sstack, r1
        mov.l   @r1, r0
        tst     r0, r0
        bf      2f
        mov.l   c_def_sstack, r0
2:      mov.l   c_sys_sstack, r1
        mov.l   r0, @r1
        mov.l   c_ip_mstack, r1
        mov.l   @r1, r15
        tst     r15, r15
        bf      1f
        mov.l   c_def_stack, r15
1:
        .ifdef  DIAG                    ! diagnostics: watchdog PC sampling
        mov.l   p_diag_start_wdt, r0
        jsr     @r0
        nop
        .endif
        mov.l   c_efsdl16, r1           ! CD audio into the mix only now: while
        mov.w   c_mix_left, r0          ! the BIOS reads data, any sector the
        mov.w   r0, @r1                 ! drive plays as audio would be noise
        mov.w   c_mix_right, r0
        add     #0x20, r1               ! slot 17
        mov.w   r0, @r1
        mov.l   c_ccr, r1               ! purge the cache (code was loaded
        mov     #0x10, r0               ! through cache-through addresses) and
        mov.b   r0, @r1                 ! leave it enabled: many games never
        mov     #0x01, r0               ! write CCR and would run uncached
        mov.b   r0, @r1                 ! (Panzer Dragoon choppy on MiSTer)
        mov.l   c_entry, r1
        mov     #0, r0
        ldc     r0, gbr
        lds     r0, mach
        lds     r0, macl
        lds     r0, pr
        mov     #0, r2
        mov     #0, r3
        mov     #0, r4
        mov     #0, r5
        mov     #0, r6
        mov     #0, r7
        mov     #0, r8
        mov     #0, r9
        mov     #0, r10
        mov     #0, r11
        mov     #0, r12
        mov     #0, r13
        mov     #0, r14
        ldc     r0, sr
        jmp     @r1
        mov     #0, r1

        .align  2
c_ip_buf:       .long   IP_BUF
c_ip_size:      .long   IP_SIZE
c_ip_first:     .long   IP_FIRST
c_ip_mstack:    .long   IP_MSTACK
c_ip_sstack:    .long   IP_BUF + 0xEC
c_sys_sstack:   .long   0x260002AC
c_def_sstack:   .long   0x06001000
c_ip_area_src:  .long   IP_BUF + 0x40
c_ip_area:      .long   IP_AREA
c_fr_addr:      .long   FR_ADDR
c_fr_size:      .long   FR_SIZE
c_scratch:      .long   SCRATCH
c_uncached:     .long   0x20000000
c_low_start:    .long   0x00200000
c_low_end:      .long   0x00300000
c_high_start:   .long   0x06002000
c_high_end:     .long   0x06100000
c_def_stack:    .long   0x06002000
c_entry:        .long   ENTRY
c_efsdl16:      .long   0x25B00216
c_mix_left:     .word   0x00FF          ! EFSDL 7, EFPAN left
c_mix_right:    .word   0x00EF          ! EFSDL 7, EFPAN right
        .align  2
c_ccr:          .long   0xFFFFFE92
p_cd_read:      .long   cd_read
        .ifdef  DIAG
p_diag_start_wdt: .long diag_start_wdt
        .endif
c_ip_max:       .long   IP_MAX          ! .long: 0x8000 would sign-extend as a word
c_ip_min:       .word   IP_MIN
c_2047:         .word   2047
c_2048:         .word   2048
c_fad150:       .word   150
c_fad166:       .word   150 + 16
c_root_lba:     .word   156 + 6         ! root directory record + extent (BE)

        .align  2
sega_id:        .ascii  "SEGA SEGASATURN "
