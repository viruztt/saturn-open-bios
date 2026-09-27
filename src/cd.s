! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - CD block driver (clean-room)
!
! Command protocol, from public CD block notes and Yabause's cs2.c
! (GPL-2.0-or-later) as a behavioural reference:
!   clear CMOK in HIRQ, write CR1..CR4 (CR4 last starts the command), wait for
!   CMOK, then read the reply from CR1..CR4 (CR4 last releases the registers
!   for the periodic status report).
! Sector data is read as longwords from the data port, TOC data as words
! from the info port.
!
! Steps follow the boot.s convention: clobber r0-r7, preserve r8-r15,
! return r0 = 0 on success.

        .section .text
        .global cd_init
        .global cd_auth
        .global cd_toc
        .global cd_read_ip
        .global CD_STAT
        .global CD_AUTH
        .global CD_TOC
        .global CD_HDR

        .equ    CD_HIRQ,    0x25890008
        .equ    CD_CR1,     0x25890018      ! CR2..CR4 follow at +4, +8, +12
        .equ    CD_DATA,    0x25818000      ! sector data port (longword reads)
        .equ    CD_INFO,    0x25898000      ! TOC / file info port (word reads)

        .equ    HIRQ_CMOK,  0x0001          ! command accepted, reply ready
        .equ    HIRQ_DRDY,  0x0002          ! data transfer ready

        ! BIOS scratch below the stack in Work RAM High (cache-through).
        ! Only needed until the BIOS hands over to the game.
        .equ    CD_VARS,    0x260F0000
        .equ    CD_RESP,    CD_VARS + 0x000 ! last reply: CR1..CR4 (words)
        .equ    CD_STAT,    CD_VARS + 0x008 ! first status report: CR1:CR2
        .equ    CD_AUTH,    CD_VARS + 0x00C ! authentication status (word)
        .equ    CD_TOC,     CD_VARS + 0x010 ! 102 longwords
        .equ    CD_HDR,     CD_VARS + 0x1B0 ! first 16 bytes of IP.BIN + NUL
        .equ    IP_BUF,     0x26002000      ! IP.BIN goes to 0x06002000

! cd_init: reset the CD block software state and record a status report.
        .align  2
cd_init:
        sts.l   pr, @-r15
        mova    cmd_init, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mova    cmd_endxfer, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mova    cmd_status, r0
        bsr     cd_cmdt
        mov     r0, r4
        mov.l   c_cd_resp, r1
        mov.l   @r1, r2                 ! CR1:CR2
        mov.l   c_cd_stat, r1
        mov.l   r2, @r1
9:      lds.l   @r15+, pr
        rts
        nop

! cd_auth: ask the CD block to authenticate the disc, then poll the
! authentication status until it is non-zero.
        .align  2
cd_auth:
        sts.l   pr, @-r15
        mov.l   r8, @-r15
        mova    cmd_auth, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mov.w   c_polls, r8
1:      mova    cmd_authst, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mov.l   c_cd_resp, r1
        mov.w   @(2, r1), r0            ! CR2 = status
        mov.l   c_cd_auth, r1
        extu.w  r0, r0
        mov.w   r0, @r1
        tst     r0, r0
        bf      2f
        dt      r8
        bf      1b
        bra     9f
        mov     #1, r0
2:      mov     #0, r0
9:      mov.l   @r15+, r8
        lds.l   @r15+, pr
        rts
        nop

! cd_toc: read the 102-entry table of contents into CD_TOC.
        .align  2
cd_toc:
        sts.l   pr, @-r15
        mova    cmd_gettoc, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        bsr     cd_wait
        mov     #HIRQ_DRDY, r4
        tst     r0, r0
        bf      9f
        mov.l   c_cd_info, r1
        mov.l   c_cd_toc, r2
        mov.w   c_toc_words, r3
1:      mov.w   @r1, r0
        mov.w   r0, @r2
        dt      r3
        bf/s    1b
        add     #2, r2
        mova    cmd_endxfer, r0
        bsr     cd_cmdt
        mov     r0, r4
9:      lds.l   @r15+, pr
        rts
        nop

! cd_read_ip: read FAD 150 (the first data sector, start of IP.BIN) into
! 0x06002000 and keep its first 16 bytes as a string in CD_HDR.
        .align  2
cd_read_ip:
        sts.l   pr, @-r15
        mov.l   r8, @-r15
        mova    cmd_seclen, r0          ! 2048-byte sectors
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mova    cmd_resetsel, r0        ! empty buffer partition 0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mova    cmd_cdconn, r0          ! drive -> filter 0 -> partition 0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mova    cmd_play, r0            ! read 1 sector from FAD 150
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mov.w   c_polls, r8
1:      mova    cmd_secnum, r0          ! wait until the sector is buffered
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mov.l   c_cd_resp, r1
        mov.w   @(6, r1), r0            ! CR4 = sectors in partition 0
        tst     r0, r0
        bf      2f
        dt      r8
        bf      1b
        bra     9f
        mov     #1, r0
2:      mova    cmd_getdel, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        bsr     cd_wait
        mov     #HIRQ_DRDY, r4
        tst     r0, r0
        bf      9f
        mov.l   c_cd_data, r1
        mov.l   c_ip_buf, r2
        mov.w   c_sector_longs, r3
3:      mov.l   @r1, r0
        mov.l   r0, @r2
        dt      r3
        bf/s    3b
        add     #4, r2
        mova    cmd_endxfer, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mov.l   c_ip_buf, r1
        mov.l   c_cd_hdr, r2
        mov     #16, r3
4:      mov.b   @r1+, r0
        mov.b   r0, @r2
        dt      r3
        bf/s    4b
        add     #1, r2
        mov     #0, r0
        mov.b   r0, @r2
9:      mov.l   @r15+, r8
        lds.l   @r15+, pr
        rts
        nop

! cd_cmdt: r4 = pointer to 4 words (CR1..CR4); runs the command.
        .align  2
cd_cmdt:
        mov     r4, r3
        mov.w   @r3+, r4
        mov.w   @r3+, r5
        mov.w   @r3+, r6
        bra     cd_cmd
        mov.w   @r3+, r7

! cd_cmd: r4..r7 = CR1..CR4. Returns r0 = 0 with the reply in CD_RESP, or
! r0 = 1 if CMOK never came.
        .align  2
cd_cmd:
        mov.l   c_cd_hirq, r2
        mov.l   c_cd_cr1, r1
        mov.w   c_not_cmok, r0
        mov.w   r0, @r2                 ! HIRQ bits written as 0 are cleared
        mov     r4, r0
        mov.w   r0, @(0, r1)
        mov     r5, r0
        mov.w   r0, @(4, r1)
        mov     r6, r0
        mov.w   r0, @(8, r1)
        mov     r7, r0
        mov.w   r0, @(12, r1)
        mov.l   c_timeout, r3
1:      mov.w   @r2, r0
        tst     #HIRQ_CMOK, r0
        bf      2f
        dt      r3
        bf      1b
        rts
        mov     #1, r0
2:      mov.l   c_cd_resp, r3
        mov.w   @(0, r1), r0
        mov.w   r0, @(0, r3)
        mov.w   @(4, r1), r0
        mov.w   r0, @(2, r3)
        mov.w   @(8, r1), r0
        mov.w   r0, @(4, r3)
        mov.w   @(12, r1), r0
        mov.w   r0, @(6, r3)
        rts
        mov     #0, r0

! cd_wait: r4 = HIRQ bit(s). Returns r0 = 0 once any is set, 1 on timeout.
        .align  2
cd_wait:
        mov.l   c_cd_hirq, r1
        mov.l   c_timeout, r2
1:      mov.w   @r1, r0
        tst     r4, r0
        bf      2f
        dt      r2
        bf      1b
        rts
        mov     #1, r0
2:      rts
        mov     #0, r0

        .align  2
c_cd_hirq:      .long   CD_HIRQ
c_cd_cr1:       .long   CD_CR1
c_cd_data:      .long   CD_DATA
c_cd_info:      .long   CD_INFO
c_cd_resp:      .long   CD_RESP
c_cd_stat:      .long   CD_STAT
c_cd_auth:      .long   CD_AUTH
c_cd_toc:       .long   CD_TOC
c_cd_hdr:       .long   CD_HDR
c_ip_buf:       .long   IP_BUF
c_timeout:      .long   0x00100000
c_not_cmok:     .word   ~HIRQ_CMOK & 0xFFFF
c_polls:        .word   0x4000
c_toc_words:    .word   0xCC
c_sector_longs: .word   2048 / 4

! Commands: CR1, CR2, CR3, CR4
        .align  2
cmd_status:     .word   0x0000, 0x0000, 0x0000, 0x0000  ! Get CD status
cmd_gettoc:     .word   0x0200, 0x0000, 0x0000, 0x0000  ! Get TOC
cmd_init:       .word   0x0400, 0xFFFF, 0xFFFF, 0xFFFF  ! Initialize CD system (no changes)
cmd_endxfer:    .word   0x0600, 0x0000, 0x0000, 0x0000  ! End data transfer
cmd_play:       .word   0x1080, 0x0096, 0x0080, 0x0001  ! Play from FAD 150, 1 sector
cmd_cdconn:     .word   0x3000, 0x0000, 0x0000, 0x0000  ! CD device -> filter 0
cmd_resetsel:   .word   0x4800, 0x0000, 0x0000, 0x0000  ! Reset selector: partition 0
cmd_secnum:     .word   0x5100, 0x0000, 0x0000, 0x0000  ! Get sector number: partition 0
cmd_seclen:     .word   0x6000, 0x0000, 0x0000, 0x0000  ! Set sector length: 2048 get/put
cmd_getdel:     .word   0x6300, 0x0000, 0x0000, 0x0001  ! Get then delete 1 sector, partition 0
cmd_auth:       .word   0xE000, 0x0000, 0x0000, 0x0000  ! Authenticate disc
cmd_authst:     .word   0xE100, 0x0000, 0x0000, 0x0000  ! Get authentication status
