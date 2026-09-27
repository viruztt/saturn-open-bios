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
        .global cd_read
        .global cd_read_file
        .global CD_STAT
        .global CD_AUTH
        .global CD_TOC
        .global CD_HDR
        .global CD_ERR
        .global CD_FAD
        .global CD_LEFT
        .global CD_RAW0

        .equ    CD_HIRQ,    0x25890008
        .equ    CD_CR1,     0x25890018      ! CR2..CR4 follow at +4, +8, +12
        .equ    CD_DATA,    0x25818000      ! sector data port (longword reads)
        .equ    CD_INFO,    0x25898000      ! TOC / file info port (word reads)

        .equ    HIRQ_CMOK,  0x0001          ! command accepted, reply ready
        .equ    HIRQ_DRDY,  0x0002          ! data transfer ready

        ! BIOS boot work area in the system area (cache-through, see sys.s).
        ! Only needed until the BIOS hands over to the game.
        .equ    CD_VARS,    0x26000D00
        .equ    CD_RESP,    CD_VARS + 0x000 ! last reply: CR1..CR4 (words)
        .equ    CD_STAT,    CD_VARS + 0x008 ! first status report: CR1:CR2
        .equ    CD_AUTH,    CD_VARS + 0x00C ! authentication status (word)
        .equ    CD_TOC,     CD_VARS + 0x010 ! 102 longwords
        .equ    CD_HDR,     CD_VARS + 0x1B0 ! first 16 bytes of IP.BIN + NUL
        ! Last CD failure: 01xxxxxx command xxxx got no CMOK, 02xxxxxx no
        ! sector arrived (xxxx = CR1 of the last status), 03xxxxxx HIRQ bits
        ! never came (xxxx = HIRQ), 04xxxxxx authentication never finished
        ! (xxxx = last status), 05xxxxxx drive never ready (xxxx = CR1:
        ! status in the high byte, e.g. 06 tray open, 07 no disc),
        ! 06xxxxxx a data transfer moved xxxxxx words instead of the
        ! expected count (recorded only). 0 = none.
        .equ    CD_ERR,     CD_VARS + 0x1C4
        .equ    CD_FAD,     CD_VARS + 0x1C8 ! next FAD the last cd_read wanted
        .equ    CD_LEFT,    CD_VARS + 0x1CC ! sectors it still had to read
        .equ    CD_CHUNK,   CD_VARS + 0x1D0 ! sectors left in the current Play
        .equ    CHUNK,      64              ! sectors per Play request
        .equ    CD_MODE,    CD_VARS + 0x1D4 ! 1: start with Read File (fid 2)
        .equ    CD_WMODE,   CD_VARS + 0x1D8 ! data port reads: 0 = 32-bit, 1 = 16-bit
        .equ    CD_RAW0,    CD_VARS + 0x1E0 ! first 16 bytes of FAD 150, first try
        .equ    IP_BUF,     0x26002000      ! IP.BIN goes to 0x06002000

! cd_init: reset the CD block software state, read the hardware info (which
! also clears the "disc changed" state, as games expect after the BIOS), and
! record a status report.
        .align  2
cd_init:
        sts.l   pr, @-r15
        mova    cmd_init_e, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mova    cmd_hwinfo_e, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mov.l   c_cd_hirq_e, r1           ! acknowledge DCHG
        mov.l   c_not_dchg_e, r0
        mov.w   r0, @r1
        mova    cmd_endxfer_e, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mova    cmd_status_e, r0
        bsr     cd_cmdt
        mov     r0, r4
        mov.l   c_cd_resp_e, r1
        mov.l   @r1, r2                 ! CR1:CR2
        mov.l   c_cd_stat_e, r1
        mov.l   r2, @r1
9:      lds.l   @r15+, pr
        rts
        nop

! cd_auth: wait for the drive to be ready, ask the CD block to authenticate
! the disc, then poll the authentication status once per frame until it is a
! definite disc type: 1 audio CD, 2 data CD, 3 unlicensed data disc, 4 Saturn
! disc. While it works the CD block answers 0 or 0xFFFF; a real drive takes
! seconds. Gives up after AUTH_FRAMES (CD_ERR = 04xxxxxx, last answer).
        .align  2
cd_auth:
        sts.l   pr, @-r15
        mov.l   r8, @-r15
        bsr     cd_ready
        nop
        tst     r0, r0
        bf      9f
        mova    cmd_auth_e, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mov.l   c_auth_frames_e, r8
1:      bsr     vbl_wait
        nop
        mova    cmd_authst_e, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mov.l   c_cd_resp_e, r1
        mov.w   @(2, r1), r0            ! CR2 = authentication status
        extu.w  r0, r0
        mov.l   c_cd_auth_e, r1
        mov.w   r0, @r1
        mov     r0, r1                  ! done when 1 <= status <= 4
        add     #-1, r1
        mov     #4, r2
        cmp/hs  r2, r1
        bf      2f
        dt      r8
        bf      1b
        mov.l   c_err_noauth_e, r1        ! give up: record the last answer
        or      r1, r0
        mov.l   c_cd_err_e, r1
        mov.l   r0, @r1
        bra     9f
        mov     #1, r0
2:      mov     #0, r0
9:      mov.l   @r15+, r8
        lds.l   @r15+, pr
        rts
        nop

! cd_ready: poll Get Status once per frame until the drive reports PAUSE,
! STANDBY or PLAY (spun up and idle), for up to READY_FRAMES. A tray that is
! open or a missing disc simply never gets there. Returns r0 = 0, or 1 with
! CD_ERR = 05xxxxxx (last CR1: status in the high byte).
        .align  2
cd_ready:
        sts.l   pr, @-r15
        mov.l   r8, @-r15
        mov.l   c_ready_frames_e, r8
1:      mova    cmd_status_e, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mov.l   c_cd_resp_e, r1
        mov.w   @r1, r0
        shlr8   r0
        and     #0x0F, r0
        cmp/eq  #1, r0                  ! PAUSE
        bt      8f
        cmp/eq  #2, r0                  ! STANDBY
        bt      8f
        cmp/eq  #3, r0                  ! PLAY
        bt      8f
        bsr     vbl_wait
        nop
        dt      r8
        bf      1b
        mov.l   c_cd_resp_e, r1           ! give up: record the drive status
        mov.w   @r1, r0
        extu.w  r0, r0
        mov.l   c_err_notready_e, r1
        or      r1, r0
        mov.l   c_cd_err_e, r1
        mov.l   r0, @r1
        bra     9f
        mov     #1, r0
8:      mov     #0, r0
9:      mov.l   @r15+, r8
        lds.l   @r15+, pr
        rts
        nop

! cd_toc: wait for the drive, then read the 102-entry table of contents into
! CD_TOC.
        .align  2
cd_toc:
        sts.l   pr, @-r15
        bsr     cd_ready
        nop
        tst     r0, r0
        bf      9f
        mova    cmd_gettoc_e, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        bsr     cd_wait
        mov     #HIRQ_DRDY, r4
        tst     r0, r0
        bf      9f
        bsr     vbl_wait                ! let the data FIFO fill (see cd_read)
        nop
        mov.l   c_cd_info_e, r1
        mov.l   c_cd_toc_e, r2
        mov.l   c_toc_words_l_e, r3
1:      mov.w   @r1, r0
        mov.w   r0, @r2
        dt      r3
        bf/s    1b
        add     #2, r2
        mova    cmd_endxfer_e, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      9f
        mov.l   c_toc_words_l_e, r4     ! all 204 words moved?
        bsr     check_xfer
        nop
        mov     #0, r0
9:      lds.l   @r15+, pr
        rts
        nop

! vbl_wait: wait for the next VBlank to begin (VDP2 TVSTAT bit 3 going from
! 0 to 1), about 1/60 s. This is the real time base for all CD waits, since
! loop counts depend on CPU and bus speed. A loop bound keeps it from
! hanging if VDP2 is not scanning. Clobbers r0-r2.
        .align  2
vbl_wait:
        mov.l   c_tvstat_e, r1
        mov.l   c_vbl_guard_e, r2
1:      mov.w   @r1, r0                 ! let the current VBlank end
        tst     #8, r0
        bt      2f
        dt      r2
        bf      1b
        rts
        nop
2:      mov.w   @r1, r0                 ! then wait for the next one
        tst     #8, r0
        bf      3f
        dt      r2
        bf      2b
3:      rts
        nop

! check_xfer: r4 = words the transfer should have moved. Reads the End Data
! Transfer reply in CD_RESP (CR1 low byte : CR2 = words transferred) and, if
! it differs and no error is recorded yet, sets CD_ERR = 06xxxxxx (the
! count). Not fatal: it documents short transfers for the boot screen.
! Clobbers r0-r2.
check_xfer:
        mov.l   c_cd_resp_e, r1
        mov.w   @(2, r1), r0            ! CR2
        extu.w  r0, r2
        mov.w   @r1, r0                 ! CR1 low byte
        and     #0xFF, r0
        shll16  r0
        or      r2, r0
        cmp/eq  r4, r0
        bt      9f
        mov.l   c_cd_err_e, r1
        mov.l   @r1, r2
        tst     r2, r2
        bf      9f
        mov.l   c_err_xfer_e, r2
        or      r2, r0
        mov.l   r0, @r1
9:      rts
        nop

        .align  2
! Constants for the routines above (literal loads only reach forward)
c_err_xfer_e:   .long   0x06000000
c_auth_frames_e:.long   30 * 60         ! authentication: up to 30 s
c_cd_auth_e:    .long   CD_AUTH
c_cd_err_e:     .long   CD_ERR
c_cd_hirq_e:    .long   CD_HIRQ
c_cd_info_e:    .long   CD_INFO
c_cd_resp_e:    .long   CD_RESP
c_cd_stat_e:    .long   CD_STAT
c_cd_toc_e:     .long   CD_TOC
c_err_noauth_e: .long   0x04000000
c_err_notready_e:.long   0x05000000
c_not_dchg_e:   .long   0xFFDF          ! HIRQ write: acknowledge DCHG
c_ready_frames_e:.long   30 * 60         ! spin-up / seek: up to 30 s
c_toc_words_l_e:.long   0xCC
c_tvstat_e:     .long   0x25F80004      ! VDP2 TVSTAT, bit 3 = VBLANK
c_vbl_guard_e:  .long   0x00200000
        .align  2
cmd_auth_e:     .word   0xE000, 0x0000, 0x0000, 0x0000  ! Authenticate disc
cmd_authst_e:   .word   0xE100, 0x0000, 0x0000, 0x0000  ! Get authentication status
cmd_endxfer_e:  .word   0x0600, 0x0000, 0x0000, 0x0000  ! End data transfer
cmd_gettoc_e:   .word   0x0200, 0x0000, 0x0000, 0x0000  ! Get TOC
cmd_hwinfo_e:   .word   0x0100, 0x0000, 0x0000, 0x0000  ! Get hardware info
cmd_init_e:     .word   0x0400, 0xFFFF, 0xFFFF, 0xFFFF  ! Initialize CD system (no changes)
cmd_status_e:   .word   0x0000, 0x0000, 0x0000, 0x0000  ! Get CD status

! cd_read_ip: read FAD 150 (the first data sector, start of IP.BIN) into
! 0x06002000 and keep its first 16 bytes as a string in CD_HDR. The CD
! block sits on a 16-bit bus: the first try reads the data port 32 bits at a
! time; if the sector does not start with "SEGA SEGASATURN", it is read again
! 16 bits at a time and that width is kept for all later reads. The bytes of
! the first try are kept in CD_RAW0 for the boot screen.
        .align  2
cd_read_ip:
        sts.l   pr, @-r15
        mov.l   c_cd_wmode, r1
        mov     #0, r0
        mov.l   r0, @r1
        bsr     read_fad150
        nop
        tst     r0, r0
        bf      9f
        mov.l   c_ip_buf, r1            ! keep what arrived
        mov.l   c_cd_raw0, r2
        mov     #4, r3
1:      mov.l   @r1+, r0
        mov.l   r0, @r2
        dt      r3
        bf/s    1b
        add     #4, r2
        mov.l   c_ip_buf, r1            ! "SEGA SEGASATURN"?
        mova    sega_id15, r0
        mov     r0, r2
        mov     #15, r3
2:      mov.b   @r1+, r0
        mov.b   @r2+, r4
        cmp/eq  r4, r0
        bf      3f
        dt      r3
        bf      2b
        bra     5f
        nop
3:      mov.l   c_cd_wmode, r1          ! no: try 16-bit data port reads
        mov     #1, r0
        mov.l   r0, @r1
        bsr     read_fad150
        nop
        tst     r0, r0
        bf      9f
5:      mov.l   c_ip_buf, r1
        mov.l   c_cd_hdr, r2
        mov     #16, r3
4:      mov.b   @r1+, r0
        mov.b   r0, @r2
        dt      r3
        bf/s    4b
        add     #1, r2
        mov     #0, r0
        mov.b   r0, @r2
9:      lds.l   @r15+, pr
        rts
        nop

read_fad150:
        mov.l   c_fad150_l, r4
        mov     #1, r5
        mov.l   c_ip_buf, r6
        mov.l   c_sector_bytes_l, r7
        bra     cd_read
        nop

        .align  2
sega_id15:      .ascii  "SEGA SEGASATURN"

! cd_read_file: as cd_read, for the first file of the root directory
! (file ID 2), which starts at FAD r4. The first attempt uses the CD block's
! own Change Directory + Read File commands; retries use Play.
        .align  2
cd_read_file:
        mov.l   c_cd_mode, r1
        mov     #1, r0
        bra     cd_read_common
        mov.l   r0, @r1

        .align  2
cd_read:
        mov.l   c_cd_mode, r1
        mov     #0, r0
        mov.l   r0, @r1
cd_read_common:
        sts.l   pr, @-r15
        mov.l   r8, @-r15
        mov.l   r9, @-r15
        mov.l   r10, @-r15
        mov.l   r11, @-r15
        mov     r5, r8                  ! r8 = sectors left
        mov     r6, r9                  ! r9 = destination
        mov     r7, r10                 ! r10 = bytes left to store
        mov.l   c_cd_fad, r1
        mov.l   r4, @r1
        mov.l   c_cd_left, r1
        mov.l   r5, @r1
        mov     #3, r0
        mov.l   r0, @-r15               ! retries left
        mova    cmd_seclen, r0          ! 2048-byte sectors
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      8f
0:      mova    cmd_resetsel, r0        ! empty buffer partition 0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      8f
        mova    cmd_cdconn, r0          ! drive -> filter 0 -> partition 0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      8f
        mov.l   c_cd_mode, r1           ! first attempt of a file read?
        mov.l   @r1, r0
        tst     r0, r0
        bt      10f
        mov     #0, r0                  ! (retries use Play)
        mov.l   r0, @r1
        bsr     cd_start_file
        nop
        bra     11f
        nop
10:     bsr     cd_play_rest            ! Play CD_LEFT sectors from CD_FAD
        nop
11:     tst     r0, r0
        bf      8f
1:      mov.l   c_polls_l, r11
2:      mova    cmd_secnum, r0          ! wait until a sector is buffered
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      8f
        mov.l   c_cd_resp, r1
        mov.w   @(6, r1), r0            ! CR4 = sectors in partition 0
        tst     r0, r0
        bf      3f
        bsr     vbl_wait                ! one poll per frame
        nop
        .ifdef  DIAG                    ! live: polls left, retries left
        mov     r11, r4
        mov     #2, r5
        mov.l   p_puthex, r0
        jsr     @r0
        mov     #27, r6
        mov.l   @r15, r4
        mov     #11, r5
        mov.l   p_puthex, r0
        jsr     @r0
        mov     #27, r6
        .endif
        dt      r11
        bf      2b
        mov.l   @r15, r0                ! nothing came: retry the rest
        tst     r0, r0
        bt      7f
        add     #-1, r0
        bra     0b
        mov.l   r0, @r15
7:      mov.l   c_cd_resp, r1           ! give up: record the drive status
        mov.w   @r1, r0
        extu.w  r0, r0
        mov.l   c_err_nosector, r1
        or      r1, r0
        mov.l   c_cd_err, r1
        mov.l   r0, @r1
        bra     8f
        mov     #1, r0
3:      mova    cmd_getdel, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      8f
        bsr     cd_wait
        mov     #HIRQ_DRDY, r4
        tst     r0, r0
        bf      8f
        bsr     vbl_wait                ! DRDY can come before the data FIFO has
        nop                             ! filled: on MiSTer, reads of an empty
                                        ! FIFO return junk and leave the data
                                        ! behind for the next transfer
        mov.l   c_cd_data, r1
        mov.l   c_cd_wmode, r0
        mov.l   @r0, r0
        tst     r0, r0
        bf      12f
        mov.l   c_sector_longs_l, r3    ! 32-bit reads
4:      mov.l   @r1, r0
        cmp/pl  r10
        bf      5f
        mov.l   r0, @r9
        add     #4, r9
        add     #-4, r10
5:      dt      r3
        bf      4b
        bra     13f
        nop
12:     mov.l   c_sector_words_l, r3    ! 16-bit reads
14:     mov.w   @r1, r0
        cmp/pl  r10
        bf      15f
        mov.w   r0, @r9
        add     #2, r9
        add     #-2, r10
15:     dt      r3
        bf      14b
13:
        mova    cmd_endxfer, r0
        bsr     cd_cmdt
        mov     r0, r4
        tst     r0, r0
        bf      8f
        mov.l   c_sector_words_l, r4    ! all 1024 words moved?
        bsr     check_xfer
        nop
        mov.l   c_cd_fad, r1            ! next FAD, one sector fewer left
        mov.l   @r1, r0
        add     #1, r0
        mov.l   r0, @r1
        mov.l   c_cd_left, r1
        add     #-1, r8
        mov.l   r8, @r1
        .ifdef  DIAG                    ! live progress: FAD and sectors left
        mov.l   c_cd_fad, r1
        mov.l   @r1, r4
        mov     #20, r5
        mov.l   p_puthex, r0
        jsr     @r0
        mov     #27, r6
        mov     r8, r4
        mov     #30, r5
        mov.l   p_puthex, r0
        jsr     @r0
        mov     #27, r6
        .endif
        tst     r8, r8
        bt      9f
        mov.l   c_cd_chunk, r1          ! end of this Play: start the next one
        mov.l   @r1, r0
        add     #-1, r0
        mov.l   r0, @r1
        tst     r0, r0
        bf      1b
        bra     0b
        nop
9:      mov     #0, r0
8:      add     #4, r15                 ! drop the retry counter
        mov.l   @r15+, r11
        mov.l   @r15+, r10
        mov.l   @r15+, r9
        mov.l   @r15+, r8
        lds.l   @r15+, pr
        rts
        nop

! cd_start_file: Change Directory to the root, then Read File (file ID 2,
! offset 0) into filter 0 / partition 0. The whole file is one request, so
! CD_CHUNK = CD_LEFT. Returns cd_cmd's r0.
        .align  2
cd_start_file:
        sts.l   pr, @-r15
        mov.l   c_cmd_chdir, r4         ! CR1 = 0x7000
        mov     #0, r5
        mov.w   c_root_cr3, r6          ! filter 0, file ID 0xFFFFFF = root
        bsr     cd_cmd
        mov     #-1, r7
        tst     r0, r0
        bf      9f
        mov.l   c_cd_left, r1
        mov.l   @r1, r0
        mov.l   c_cd_chunk, r1
        mov.l   r0, @r1
        mov.l   c_cmd_readfile, r4      ! CR1 = 0x7400, offset 0
        mov     #0, r5
        mov     #0, r6                  ! filter 0, file ID high = 0
        bsr     cd_cmd
        mov     #2, r7                  ! file ID 2
9:      lds.l   @r15+, pr
        rts
        nop

! cd_play_rest: Play min(CD_LEFT, CHUNK) sectors starting at CD_FAD (FAD
! mode) and set CD_CHUNK to that count. Returns cd_cmd's r0.
        .align  2
cd_play_rest:
        mov.l   c_cd_fad, r1
        mov.l   @r1, r2                 ! r2 = FAD
        mov.l   c_cd_left, r1
        mov.l   @r1, r3                 ! r3 = count
        mov     #CHUNK, r0
        cmp/hi  r0, r3
        bf      1f
        mov     r0, r3
1:      mov.l   c_cd_chunk, r1
        mov.l   r3, @r1
        mov     r2, r0                  ! CR1 = 0x10 | FAD flag | FAD[22:16]
        shlr16  r0
        and     #0x7F, r0
        mov.w   c_play, r4
        or      r0, r4
        extu.w  r2, r5                  ! CR2 = FAD[15:0]
        mov     r3, r0                  ! CR3 = mode 0 | count flag | count[22:16]
        shlr16  r0
        and     #0x7F, r0
        or      #0x80, r0
        mov     r0, r6
        bra     cd_cmd
        extu.w  r3, r7                  ! CR4 = count[15:0]

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
        .ifdef  DIAG                    ! live: CMOK wait counter, HIRQ
        mov     r3, r0
        tst     #0xFF, r0
        bf      3f
        mov.l   r1, @-r15
        mov.l   r2, @-r15
        mov.l   r4, @-r15
        mov.l   r5, @-r15
        mov.l   r6, @-r15
        sts.l   pr, @-r15
        mov.w   @r2, r4
        extu.w  r4, r4
        shll16  r4
        or      r3, r4
        mov     #2, r5
        mov.l   p_puthex, r0
        jsr     @r0
        mov     #26, r6
        mov.l   @(12, r15), r4          ! the command (CR1) being waited on
        extu.w  r4, r4
        mov     #12, r5
        mov.l   p_puthex, r0
        jsr     @r0
        mov     #26, r6
        lds.l   @r15+, pr
        mov.l   @r15+, r6
        mov.l   @r15+, r5
        mov.l   @r15+, r4
        mov.l   @r15+, r2
        mov.l   @r15+, r1
3:
        .endif
        dt      r3
        bf      1b
        extu.w  r4, r0                  ! record: command without CMOK
        mov.l   c_err_nocmok, r1
        or      r1, r0
        mov.l   c_cd_err, r1
        mov.l   r0, @r1
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

! cd_wait: r4 = HIRQ bit(s). Returns r0 = 0 once any is set, or 1 after
! WAIT_FRAMES frames (CD_ERR = 03xxxxxx, HIRQ at that time).
        .align  2
cd_wait:
        sts.l   pr, @-r15
        mov.l   r8, @-r15
        mov.l   c_wait_frames, r8
1:      mov.l   c_cd_hirq, r1
        mov.w   @r1, r0
        tst     r4, r0
        bf      2f
        bsr     vbl_wait
        nop
        dt      r8
        bf      1b
        mov.l   c_cd_hirq, r1           ! record: HIRQ bits never came
        mov.w   @r1, r0
        extu.w  r0, r0
        mov.l   c_err_nohirq, r1
        or      r1, r0
        mov.l   c_cd_err, r1
        mov.l   r0, @r1
        bra     9f
        mov     #1, r0
2:      mov     #0, r0
9:      mov.l   @r15+, r8
        lds.l   @r15+, pr
        rts
        nop

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
c_timeout:      .long   0x00400000      ! about 0.5 s of polling
c_cd_err:       .long   CD_ERR
c_cd_fad:       .long   CD_FAD
c_cd_left:      .long   CD_LEFT
c_cd_chunk:     .long   CD_CHUNK
c_cd_mode:      .long   CD_MODE
c_cmd_chdir:    .long   0x7000
c_cmd_readfile: .long   0x7400
c_err_nocmok:   .long   0x01000000
c_err_nosector: .long   0x02000000
c_err_nohirq:   .long   0x03000000
c_err_noauth:   .long   0x04000000
c_err_notready: .long   0x05000000
c_tvstat:       .long   0x25F80004      ! VDP2 TVSTAT, bit 3 = VBLANK
c_vbl_guard:    .long   0x00200000
c_auth_frames:  .long   30 * 60         ! authentication: up to 30 s
c_ready_frames: .long   30 * 60         ! spin-up / seek: up to 30 s
c_wait_frames:  .long   10 * 60         ! data ready etc.: up to 10 s
        .ifdef  DIAG
p_puthex:       .long   con_puthex
        .endif
c_not_dchg:     .long   0xFFDF          ! HIRQ write: acknowledge DCHG
c_polls_l:      .long   5 * 60          ! frames without a sector before retrying
c_sector_longs_l: .long 2048 / 4
c_sector_words_l: .long 2048 / 2
c_cd_wmode:     .long   CD_WMODE
c_cd_raw0:      .long   CD_RAW0
c_toc_words_l:  .long   0xCC
c_fad150_l:     .long   150
c_sector_bytes_l: .long 2048
c_not_cmok:     .word   ~HIRQ_CMOK & 0xFFFF
c_toc_words:    .word   0xCC
c_sector_longs: .word   2048 / 4
c_sector_bytes: .word   2048
c_fad150:       .word   150
c_play:         .word   0x1080          ! Play disc, start given as FAD
c_root_cr3:     .word   0x00FF

! Commands: CR1, CR2, CR3, CR4
        .align  2
cmd_status:     .word   0x0000, 0x0000, 0x0000, 0x0000  ! Get CD status
cmd_hwinfo:     .word   0x0100, 0x0000, 0x0000, 0x0000  ! Get hardware info
cmd_gettoc:     .word   0x0200, 0x0000, 0x0000, 0x0000  ! Get TOC
cmd_init:       .word   0x0400, 0xFFFF, 0xFFFF, 0xFFFF  ! Initialize CD system (no changes)
cmd_endxfer:    .word   0x0600, 0x0000, 0x0000, 0x0000  ! End data transfer
cmd_cdconn:     .word   0x3000, 0x0000, 0x0000, 0x0000  ! CD device -> filter 0
cmd_resetsel:   .word   0x4800, 0x0000, 0x0000, 0x0000  ! Reset selector: partition 0
cmd_secnum:     .word   0x5100, 0x0000, 0x0000, 0x0000  ! Get sector number: partition 0
cmd_seclen:     .word   0x6000, 0x0000, 0x0000, 0x0000  ! Set sector length: 2048 get/put
cmd_getdel:     .word   0x6300, 0x0000, 0x0000, 0x0001  ! Get then delete 1 sector, partition 0
cmd_auth:       .word   0xE000, 0x0000, 0x0000, 0x0000  ! Authenticate disc
cmd_authst:     .word   0xE100, 0x0000, 0x0000, 0x0000  ! Get authentication status
