! SPDX-License-Identifier: GPL-2.0-or-later
! SaturnOpenBios - backup RAM library (clean-room)
!
! Games call BUP_Init through the pointer at 0x06000358:
!   BUP_Init(r4 = library area, r5 = work area, r6 = BupConfig[3])
! It stores the work area address at 0x06000354 and a table of function
! pointers at the start of the work area; games call through that table:
!   +0x04 SelPart  +0x08 Format  +0x0C Stat    +0x10 Write  +0x14 Read
!   +0x18 Delete   +0x1C Dir     +0x20 Verify  +0x24 GetDate +0x28 SetDate
! Return codes: 0 ok, 1 device not connected, 2 unformatted, 4 not enough
! space, 5 not found, 6 already exists, 7 verify mismatch, 8 broken data.
!
! Devices: 0 = internal backup RAM (32 KB on the odd bytes of 0x00180000-
! 0x0018FFFF, 512 blocks of 64 bytes); 1 = backup RAM cartridge, present
! when the A-bus cartridge ID byte (0x24FFFFFF) is 0x21-0x24: 4, 8, 16 or 32
! Mbit on the odd bytes from 0x04000000, blocks of 512 bytes (1024 for 32
! Mbit), 1024 to 4096 blocks. Data byte i of block b is at
! base + b * blocksize * 2 + i * 2. The format is the same on both and is
! the one the console and emulators use, so saves stay interchangeable:
!   block 0      "BackUpRam Format" x 4; block 1 unused; saves from block 2
!   first block  [0] 0x80 = start of a save, [1..3] 0, [4..14] file name,
!                [15] language, [16..25] comment, [26..29] date,
!                [30..33] data size (big-endian), then from [34]:
!   stream       block list (2 bytes per further block, ends with 0x0000),
!                then the data. It continues at [4] of each listed block.
!
! Behaviour follows Yabause's HLE BIOS (bios.c, GPL-2.0-or-later) with two
! differences: the block list is followed through the listed blocks (not the
! physically next ones), and the date conversion is exact for every year of
! the leap cycle. BupDir layout is SBL's: name[12], comment[11], language,
! date, datasize, blocksize. There is no floppy device (2).
!
! All entry points follow the C convention: r8-r14 and PR are preserved.

        .section .text
        .global bup_init

        .equ    BUP1,       0x20180001      ! internal: data byte 0 of block 0
        .equ    CART_ID,    0x24FFFFFF      ! A-bus cartridge ID byte
        .equ    CART1,      0x24000001      ! cartridge: data byte 0 of block 0
        ! System variable: BUP work area. Written through the cached address:
        ! the game reads it cached, and a write through the cache-through
        ! alias would leave a stale copy in the game's cache (SH-2 caches
        ! are write-through, so memory is right either way).
        .equ    WORK_PTR,   0x06000354
        ! Work area (given by the game, 8 KB in SBL): function table at +0,
        ! the current device at +0x30 (data byte 0 of block 0, block size,
        ! block count; set by dev_setup), used-block map (u8 x up to 4096) at
        ! +0x40, block list (u16 x LISTCAP) at +0x1040 up to +0x2000.
        .equ    W_BASE,     0x30
        .equ    W_BSIZE,    0x34
        .equ    W_NBLK,     0x38
        .equ    W_MAP,      0x40
        .equ    LISTCAP,    3040            ! (0x2000 - 0x1040) / 2 entries

! LIST rd: rd = block list base (r11 + 0x1040). MAP rd: rd = used-block map
! base. NBLK rd / BSIZE rd: rd = the device's block count / block size.
! LCAP rd: rd = LISTCAP. (No literal pool needed.)
        .macro  LIST rd
        mov     #0x41, \rd
        shll2   \rd
        shll2   \rd
        shll2   \rd
        add     r11, \rd
        .endm
        .macro  MAP rd
        mov     r11, \rd
        add     #W_MAP, \rd
        .endm
        .macro  NBLK rd
        mov.l   @(W_NBLK, r11), \rd
        .endm
        .macro  BSIZE rd
        mov.l   @(W_BSIZE, r11), \rd
        .endm
        .macro  LCAP rd
        mov     #0x5F, \rd
        shll2   \rd
        shll2   \rd
        shll    \rd
        .endm

        .macro  ENTER
        mov.l   r14, @-r15
        mov.l   r13, @-r15
        mov.l   r12, @-r15
        mov.l   r11, @-r15
        mov.l   r10, @-r15
        mov.l   r9, @-r15
        mov.l   r8, @-r15
        sts.l   pr, @-r15
        .endm

! Common exit: r0 = return value
        .align  2
leave:
        lds.l   @r15+, pr
        mov.l   @r15+, r8
        mov.l   @r15+, r9
        mov.l   @r15+, r10
        mov.l   @r15+, r11
        mov.l   @r15+, r12
        mov.l   @r15+, r13
        rts
        mov.l   @r15+, r14

! ---- BUP_Init ------------------------------------------------------------
        .align  2
bup_init:
        sts.l   pr, @-r15
        mov.l   lp_work_ptr, r0
        mov.l   r5, @r0
        mova    functions, r0
        mov     r0, r1
        mov     #12, r2
1:      mov.l   @r1+, r0
        mov.l   r0, @r5
        dt      r2
        bf/s    1b
        add     #4, r5
        mov     #1, r0                  ! device 0: internal (unit 1),
        mov.w   r0, @r6                 ! 1 partition
        mov.w   r0, @(2, r6)
        mov     #0, r0                  ! floppy: none
        mov.w   r0, @(8, r6)
        mov.w   r0, @(10, r6)
        mov.l   r6, @-r15
        bsr     cart_info               ! device 1: a backup RAM cartridge
        nop                             ! (unit 2, 1 partition) if present
        mov.l   @r15+, r6
        tst     r0, r0
        bt/s    2f
        mov     #0, r3
        mov     #1, r3
2:      mov     r3, r0
        shll    r0
        mov.w   r0, @(4, r6)
        mov     r3, r0
        mov.w   r0, @(6, r6)
        lds.l   @r15+, pr
        rts
        nop

! cart_info: r0 = block count of the backup RAM cartridge (0 if none), r1 =
! its block size. The size code comes from the cartridge ID byte: 0x21-0x24
! are 4, 8, 16 and 32 Mbit, i.e. 1024, 2048 and 4096 blocks of 512 bytes
! and 4096 of 1024. Emulators may not provide the ID byte (reads return
! cartridge RAM); then a cartridge whose RAM starts with the format header
! is taken as present, and its size is where the address space first
! repeats that header (every 0x100000 << (code - 1) bytes; 32 Mbit if it
! never does). Clobbers r2-r7.
        .align  2
cart_info:
        sts.l   pr, @-r15
        mov.l   lp_cart_id, r1
        mov.b   @r1, r0
        and     #0xFF, r0
        mov     r0, r2                  ! r2 = ID
        and     #0xF0, r0
        cmp/eq  #0x20, r0
        bf      5f
        mov     r2, r0
        and     #0x0F, r0               ! r0 = size code 1-4
        tst     r0, r0
        bt      5f
        mov     #4, r1
        cmp/hi  r1, r0
        bf      6f
5:      mov.l   lp_cart1, r4            ! no ID: a formatted cartridge?
        bsr     hdr_at
        nop
        bf      9f
        mov     #1, r3                  ! r3 = size code, r5 = its span
        mov.l   lp_cart_span, r5
7:      mov     #4, r0
        cmp/eq  r0, r3
        bt      8f
        mov.l   lp_cart1, r4
        add     r5, r4
        bsr     hdr_at
        nop
        bt      8f
        shll    r5
        bra     7b
        add     #1, r3
8:      mov     r3, r0
6:      cmp/eq  #4, r0
        bt      4f
        mov     r0, r2                  ! 1-3: 512 << code blocks of 512
        mov     #2, r0
        shll8   r0
1:      dt      r2
        bf/s    1b
        shll    r0
        mov     #2, r1
        bra     10f
        shll8   r1
4:      mov     #16, r0                 ! 4: 4096 blocks of 1024
        shll8   r0
        mov     #4, r1
        bra     10f
        shll8   r1
9:      mov     #0, r0
10:     lds.l   @r15+, pr
        rts
        nop

! hdr_at: T = 1 if the data bytes from r4 (every other address) hold the
! format header "BackUpRam Format". Clobbers r0, r1, r4, r6, r7.
hdr_at:
        mova    header, r0
        mov     r0, r6
        mov     #16, r7
1:      mov.b   @r4, r0
        add     #2, r4
        mov.b   @r6+, r1
        cmp/eq  r1, r0
        bf      9f
        dt      r7
        bf      1b
        rts
        sett
9:      rts
        clrt

        .align  2
functions:
        .long   bup_nop, bup_selpart, bup_format, bup_stat
        .long   bup_write, bup_read, bup_delete, bup_dir
        .long   bup_verify, bup_getdate, bup_setdate, bup_nop

bup_nop:
bup_selpart:
        rts
        mov     #0, r0

! ---- device checks ----------------------------------------------------------

! dev_setup: r4 = device. Loads r11 = work area and stores the device's
! data base, block size and block count there (W_BASE, W_BSIZE, W_NBLK).
! Returns r0 = 0, or 1 if the device does not exist. Clobbers r1-r7.
        .align  2
dev_setup:
        mov.l   lp_work_ptr, r0
        mov.l   @r0, r11
        tst     r4, r4
        bf      1f
        mov.l   lp_bup1, r0             ! 0: internal, 512 blocks of 64
        mov.l   r0, @(W_BASE, r11)
        mov     #64, r0
        mov.l   r0, @(W_BSIZE, r11)
        mov     #2, r0
        shll8   r0
        mov.l   r0, @(W_NBLK, r11)
        rts
        mov     #0, r0
1:      mov     r4, r0
        cmp/eq  #1, r0
        bf      9f
        sts.l   pr, @-r15               ! 1: cartridge, if one is present
        bsr     cart_info
        nop
        lds.l   @r15+, pr
        tst     r0, r0
        bt      9f
        mov.l   r0, @(W_NBLK, r11)
        mov.l   r1, @(W_BSIZE, r11)
        mov.l   lp_cart1, r0
        mov.l   r0, @(W_BASE, r11)
        rts
        mov     #0, r0
9:      rts
        mov     #1, r0

! check_dev: r4 = device. dev_setup, then returns r0 = 0 if the device is
! present and formatted, 1 if it does not exist, 2 if unformatted.
! Clobbers r1-r7.
        .align  2
check_dev:
        sts.l   pr, @-r15
        bsr     dev_setup
        nop
        lds.l   @r15+, pr
        tst     r0, r0
        bf      8f
        mov.l   @(W_BASE, r11), r1
        mova    header, r0
        mov     r0, r2
        mov     #16, r3
1:      mov.b   @r1, r0
        add     #2, r1
        mov.b   @r2+, r4
        cmp/eq  r4, r0
        bf      9f
        dt      r3
        bf      1b
        rts
        mov     #0, r0
8:      rts
        mov     #1, r0
9:      rts
        mov     #2, r0


! ---- Format(r4 = device) ----------------------------------------------------
        .align  2
bup_format:
        ENTER
        bsr     dev_setup
        nop
        tst     r0, r0
        bf      9f
        mov.l   @(W_BASE, r11), r1
        mov     #4, r3                  ! "BackUpRam Format" x 4
1:      mova    header, r0
        mov     r0, r2
        mov     #16, r4
2:      mov.b   @r2+, r0
        mov.b   r0, @r1
        dt      r4
        bf/s    2b
        add     #2, r1
        dt      r3
        bf      1b
        NBLK    r3                      ! every other byte of the device: 0
        BSIZE   r0
        mulu.w  r0, r3
        sts     macl, r3
        add     #-64, r3
        mov     #0, r0
3:      mov.b   r0, @r1
        dt      r3
        bf/s    3b
        add     #2, r1
9:      bra     leave
        nop

        .align  2
header:         .ascii  "BackUpRam Format"
lp_work_ptr:    .long   WORK_PTR
lp_bup1:        .long   BUP1
lp_cart_id:     .long   CART_ID
lp_cart1:       .long   CART1
lp_cart_span:   .long   0x100000        ! 4 Mbit cartridge address span

! ---- Stat(r4 = device, r5 = data size, r6 = BupStat*) -------------------------
! BupStat: totalsize, totalblock, blocksize, freesize, freeblock, datanum
        .align  2
bup_stat:
        ENTER
        mov     r5, r13
        mov     r6, r14
        bsr     check_dev
        nop
        tst     r0, r0
        bf      9f
        bsr     used_map
        nop                             ! r0 = free blocks
        NBLK    r1
        mov.l   r1, @(4, r14)
        BSIZE   r2
        mulu.w  r1, r2
        sts     macl, r1                ! total bytes
        mov.l   r1, @r14
        mov.l   r2, @(8, r14)
        mov.l   r0, @(16, r14)
        mov     r2, r1                  ! free bytes = (blocksize - 6) * free
        add     #-6, r1                 ! - 30 (each block: 4 header bytes and
        mulu.w  r0, r1                  ! its 2-byte list entry; the first
        sts     macl, r1                ! also holds the save's header)
        add     #-30, r1
        cmp/pz  r1
        bt      1f
        mov     #0, r1
1:      mov.l   r1, @(12, r14)
        sub     r13, r1                 ! bytes left after a save of r5 bytes,
        cmp/pz  r1                      ! in blocks
        bt      2f
        mov     #0, r1
2:      mov     r1, r4
        bsr     udiv
        mov     r2, r5
        mov.l   r0, @(20, r14)
        mov     #0, r0
9:      bra     leave
        nop

! ---- Write(r4 = device, r5 = BupDir*, r6 = data, r7 = 1: do not overwrite) --
        .align  2
bup_write:
        ENTER
        mov     r5, r13                 ! r13 = dir entry
        mov     r6, r14                 ! r14 = data
        mov     r7, r12                 ! r12 = "do not overwrite" flag
        bsr     check_dev
        nop
        tst     r0, r0
        bt      97f
        bra     99f                     ! (out of reach of bf)
        nop
97:     mov     r13, r4                 ! existing save with this name?
        bsr     find_save
        mov     #2, r5
        tst     r0, r0
        bt      1f
        tst     r12, r12
        bt/s    0f
        mov     r0, r4                  ! r4 = its first block
        bra     99f
        mov     #6, r0                  ! exists and must not be overwritten
0:      bsr     delete_block
        nop
1:      bsr     used_map                ! r0 = free blocks
        nop
        mov.l   r0, @-r15
        mov     r13, r0
        mov.l   @(28, r0), r12          ! r12 = data size (dir offset 28)
        bsr     blocks_for              ! r0 = blocks needed
        mov     r12, r4
        mov     r0, r10                 ! r10 = blocks needed
        mov.l   @r15+, r0
        cmp/hi  r0, r10                 ! more than are free, or more than
        bt      98f                     ! the work area's block list holds
        LCAP    r0
        cmp/hi  r0, r10
        bf      2f
98:     bra     99f
        mov     #4, r0
2:      LIST    r1                      ! list[0..r10-1] = first free blocks
        MAP     r2
        mov     #2, r3
        mov     r10, r4
3:      mov     r3, r0
        mov.b   @(r0, r2), r0
        tst     r0, r0
        bf      4f
        mov.w   r3, @r1
        add     #2, r1
        dt      r4
        bt      5f
4:      bra     3b
        add     #1, r3
5:      LIST    r1                      ! first block header
        mov.w   @r1, r8
        extu.w  r8, r8                  ! r8 = first block
        mov     #0, r3                  ! [0..3] = 0 for now; [0] set last
        mov     #0, r9
        bsr     put_byte_at
        nop
        mov     #1, r9
        bsr     put_byte_at
        nop
        mov     #2, r9
        bsr     put_byte_at
        nop
        mov     #3, r9
        bsr     put_byte_at
        nop
        mov     #4, r9                  ! name: dir[0..10] -> [4..14]
        mov     r13, r7
        bsr     copy_in
        mov     #11, r6
        mov     r13, r0                 ! language: dir[23] -> [15]
        add     #23, r0
        mov.b   @r0, r3
        bsr     put_byte_at
        mov     #15, r9
        mov     #16, r9                 ! comment: dir[12..21] -> [16..25]
        mov     r13, r7
        add     #12, r7
        bsr     copy_in
        mov     #10, r6
        mov     #26, r9                 ! date, size: dir[24..31] -> [26..33]
        mov     r13, r7
        add     #24, r7
        bsr     copy_in
        mov     #8, r6
        mov     r10, r13                ! r13 = blocks (dir no longer needed)
        mov.l   r14, @-r15              ! keep the data pointer
        mov     #34, r9                 ! stream: list entries 1.., 0x0000, data
        mov     #1, r10                 ! r10 = next list index when crossing
        mov     #1, r14                 ! r14 = entry to write next
6:      cmp/hs  r13, r14
        bt      7f
        LIST    r1
        mov     r14, r0
        shll    r0
        mov.w   @(r0, r1), r3
        extu.w  r3, r3
        mov.l   r3, @-r15
        bsr     st_put
        shlr8   r3
        bsr     st_put
        mov.l   @r15+, r3
        bra     6b
        add     #1, r14
7:      bsr     st_put
        mov     #0, r3
        bsr     st_put
        mov     #0, r3
        mov.l   @r15+, r14              ! data
8:      tst     r12, r12
        bt      9f
        mov.b   @r14+, r3
        bsr     st_put
        nop
        bra     8b
        add     #-1, r12
9:      LIST    r1                      ! finally mark the save as started
        mov.w   @r1, r8
        extu.w  r8, r8
        mov     #0, r9
        mov     #0x80, r3
        bsr     put_byte_at
        extu.b  r3, r3
        mov     #0, r0
99:     bra     leave
        nop

! ---- Read(r4 = device, r5 = name, r6 = buffer) ---------------------------------
! ---- Verify(r4 = device, r5 = name, r6 = data) ---------------------------------
        .align  2
bup_read:
        ENTER
        bra     1f
        mov     #0, r13                 ! r13 = 0: read
bup_verify:
        ENTER
        mov     #1, r13                 ! r13 = 1: verify
1:      mov     r6, r14                 ! r14 = buffer / data
        mov     r5, r12
        bsr     check_dev
        nop
        tst     r0, r0
        bf      99f
        mov     r12, r4
        bsr     find_save
        mov     #2, r5
        tst     r0, r0
        bf/s    2f
        mov     r0, r4
        bra     99f
        mov     #5, r0
2:      mov.l   r4, @-r15
        bsr     block_size_field
        nop
        mov.l   @r15+, r4
        mov     r0, r12                 ! r12 = data size
        bsr     read_list               ! stream now at the data
        nop
        tst     r0, r0
        bf/s    99f
        mov     #8, r0
3:      tst     r12, r12
        bt      5f
        bsr     st_get
        nop
        tst     r13, r13
        bf      4f
        mov.b   r0, @r14                ! read
        add     #1, r14
        bra     3b
        add     #-1, r12
4:      mov.b   @r14+, r1               ! verify
        extu.b  r1, r1
        cmp/eq  r1, r0
        bf/s    99f
        mov     #7, r0
        bra     3b
        add     #-1, r12
5:      mov     #0, r0
99:     bra     leave
        nop

! ---- Delete(r4 = device, r5 = name) ---------------------------------------------
        .align  2
bup_delete:
        ENTER
        mov     r5, r12
        bsr     check_dev
        nop
        tst     r0, r0
        bf      99f
        mov     r12, r4
        bsr     find_save
        mov     #2, r5
        tst     r0, r0
        bf/s    1f
        mov     r0, r4
        bra     99f
        mov     #5, r0
1:      bsr     delete_block
        nop
        mov     #0, r0
99:     bra     leave
        nop

! ---- Dir(r4 = device, r5 = name prefix, r6 = max entries, r7 = BupDir table) -----
! Returns the number of entries; if the table is too small, minus the number
! of matching saves.
        .align  2
bup_dir:
        ENTER
        mov     r5, r12                 ! r12 = name
        mov     r6, r13                 ! r13 = table size
        mov     r7, r14                 ! r14 = table
        bsr     check_dev
        nop
        tst     r0, r0
        bf      99f
        mov     #0, r10                 ! count matches
        mov     #2, r9
1:      mov     r12, r4
        bsr     find_save
        mov     r9, r5
        tst     r0, r0
        bt      2f
        add     #1, r10
        mov     r0, r9
        bra     1b
        add     #1, r9
2:      cmp/hi  r13, r10
        bf      3f
        bra     99f
        neg     r10, r0
3:      mov     #0, r10                 ! fill entries
        mov     #2, r9
4:      cmp/hs  r13, r10
        bt      9f
        mov     r12, r4
        bsr     find_save
        mov     r9, r5
        tst     r0, r0
        bt      9f
        mov     r0, r8                  ! r8 = block (read_at uses r8/r9)
        mov.l   r0, @-r15
        mov     #4, r9                  ! name + NUL
        mov     r14, r7
        bsr     copy_out
        mov     #11, r6
        mov     #0, r0
        mov.b   r0, @(11, r14)
        mov     #16, r9                 ! comment + NUL
        mov     r14, r7
        add     #12, r7
        bsr     copy_out
        mov     #10, r6
        mov     r14, r1
        add     #22, r1
        mov     #0, r0
        mov.b   r0, @r1                 ! comment NUL
        mov     #15, r9                 ! language
        bsr     get_byte_at
        nop
        mov     r14, r1
        add     #23, r1
        mov.b   r0, @r1
        mov     #26, r9                 ! date, size
        mov     r14, r7
        add     #24, r7
        bsr     copy_out
        mov     #8, r6
        mov     r14, r0                 ! blocks
        bsr     blocks_for
        mov.l   @(28, r0), r4
        mov     r14, r1
        add     #32, r1
        mov.w   r0, @r1
        mov     #0, r0
        mov.w   r0, @(2, r1)
        add     #36, r14
        add     #1, r10
        mov.l   @r15+, r9
        bra     4b
        add     #1, r9
9:      mov     r10, r0
99:     bra     leave
        nop

! ---- GetDate(r4 = minutes since 1980-01-01 00:00, r5 = BupDate*) ---------------
! BupDate: year - 1980, month, day, hour, minute, week (0 = Sunday)
        .align  2
bup_getdate:
        ENTER
        mov     r5, r14
        mov     r4, r13
        mov.w   c_1440, r5              ! (no PC-relative loads in delay slots)
        bsr     udiv                    ! r0 = days, r1 = minute of the day
        nop
        mov     r0, r12                 ! r12 = days
        mov     r1, r4
        bsr     udiv
        mov     #60, r5
        mov.b   r0, @(3, r14)           ! hour
        mov     r1, r0
        mov.b   r0, @(4, r14)           ! minute
        mov     r12, r4                 ! week: 1980-01-01 was a Tuesday
        add     #2, r4
        bsr     udiv
        mov     #7, r5
        mov     r1, r0
        mov.b   r0, @(5, r14)
        mov     r12, r4                 ! 4-year cycles
        mov.w   c_1461, r5
        bsr     udiv
        nop
        shll2   r0
        mov     r0, r13                 ! r13 = year (so far)
        mov     r1, r4                  ! r4 = day in cycle
        mov.w   c_366, r5
        cmp/hs  r5, r4
        bt      1f
        bra     2f
        mov     #1, r10                 ! leap year
1:      sub     r5, r4
        mov.w   c_365, r5
        bsr     udiv
        nop
        add     #1, r0
        add     r0, r13
        mov     r1, r4
        mov     #0, r10
2:      mov     r13, r0
        mov.b   r0, @(0, r14)           ! year
        mova    month_days, r0          ! r4 = day of year
        mov     r0, r1
        mov     #1, r2                  ! r2 = month
3:      mov.b   @r1+, r3
        extu.b  r3, r3
        mov     #2, r0
        cmp/eq  r0, r2
        bf      4f
        add     r10, r3                 ! February in a leap year
4:      cmp/hs  r3, r4
        bf      5f
        sub     r3, r4
        bra     3b
        add     #1, r2
5:      mov     r2, r0
        mov.b   r0, @(1, r14)
        mov     r4, r0
        add     #1, r0
        mov.b   r0, @(2, r14)
        bra     leave
        nop

! ---- SetDate(r4 = BupDate*) -> r0 = minutes since 1980-01-01 00:00 -------------
        .align  2
bup_setdate:
        ENTER
        mov     r4, r14
        mov.b   @(0, r14), r0           ! year
        extu.b  r0, r0
        mov     r0, r13
        shlr2   r0                      ! days = (year / 4) * 1461
        mov.w   c_1461, r1
        mulu.w  r0, r1
        sts     macl, r12
        mov     r13, r0
        and     #3, r0
        mov     #0, r10                 ! r10 = 1 in a leap year
        tst     r0, r0
        bf      1f
        bra     2f
        mov     #1, r10
1:      mov.w   c_365, r1               ! + year_in_cycle * 365 + 1
        mulu.w  r0, r1
        sts     macl, r1
        add     r1, r12
        add     #1, r12
2:      mov.b   @(1, r14), r0           ! + days of the months before
        extu.b  r0, r0
        mov     r0, r2
        mova    month_days, r0
        mov     r0, r1
        mov     #1, r3
3:      cmp/hs  r2, r3
        bt      5f
        mov.b   @r1+, r0
        extu.b  r0, r0
        add     r0, r12
        mov     #2, r0
        cmp/eq  r0, r3
        bf      4f
        add     r10, r12
4:      bra     3b
        add     #1, r3
5:      mov.b   @(2, r14), r0           ! + day - 1
        extu.b  r0, r0
        add     r0, r12
        add     #-1, r12
        mov.w   c_1440, r1              ! minutes
        mul.l   r12, r1
        sts     macl, r12
        mov.b   @(3, r14), r0
        extu.b  r0, r0
        mov     #60, r1
        mulu.w  r0, r1
        sts     macl, r1
        add     r1, r12
        mov.b   @(4, r14), r0
        extu.b  r0, r0
        add     r0, r12
        mov     r12, r0
        bra     leave
        nop

        .align  2
month_days:     .byte   31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
c_1440:         .word   1440
c_1461:         .word   1461
c_366:          .word   366
c_365:          .word   365

! ---- internal helpers ---------------------------------------------------------
! Register conventions inside the library: r11 = work area (set by
! check_dev), r8/r9 = current block / byte index for the byte helpers and
! the stream, r10 = next block-list index used when the stream crosses into
! a new block (list at LIST, r11 + 0x1040).

! byte_addr: r1 = address of data byte r9 of block r8. Clobbers r0.
        .align  2
byte_addr:
        BSIZE   r0
        mulu.w  r8, r0
        sts     macl, r1
        shll    r1                      ! block * blocksize * 2
        mov     r9, r0
        shll    r0
        add     r0, r1
        mov.l   @(W_BASE, r11), r0
        rts
        add     r0, r1

! get_byte_at: r0 = data byte r9 of block r8
get_byte_at:
        sts.l   pr, @-r15
        bsr     byte_addr
        nop
        mov.b   @r1, r0
        extu.b  r0, r0
        lds.l   @r15+, pr
        rts
        nop

! put_byte_at: data byte r9 of block r8 = r3
put_byte_at:
        sts.l   pr, @-r15
        bsr     byte_addr
        nop
        mov.b   r3, @r1
        lds.l   @r15+, pr
        rts
        nop

! copy_in: r6 bytes from memory r7 to data bytes r9.. of block r8
copy_in:
        sts.l   pr, @-r15
1:      mov.b   @r7+, r3
        bsr     put_byte_at
        nop
        add     #1, r9
        dt      r6
        bf      1b
        lds.l   @r15+, pr
        rts
        nop

! copy_out: r6 bytes from data bytes r9.. of block r8 to memory r7
copy_out:
        sts.l   pr, @-r15
1:      bsr     get_byte_at
        nop
        mov.b   r0, @r7
        add     #1, r7
        add     #1, r9
        dt      r6
        bf      1b
        lds.l   @r15+, pr
        rts
        nop

! st_cross: if the stream is at the end of a block (r9 = block size),
! continue at byte 4 of block list[r10++]. Crossing only happens when a byte
! is actually read or written there, so the list is never read past its end.
! Returns T = 1 if it crossed. Clobbers r0, r1.
st_cross:
        BSIZE   r0
        cmp/eq  r0, r9
        bf      1f
        mov     r10, r0
        shll    r0
        LIST    r1
        mov.w   @(r0, r1), r8
        extu.w  r8, r8
        add     #1, r10
        mov     #4, r9
        sett
1:      rts
        nop

! st_get: r0 = next stream byte. Clobbers r1.
st_get:
        sts.l   pr, @-r15
        bsr     st_cross
        nop
        bsr     get_byte_at
        nop
        add     #1, r9
        lds.l   @r15+, pr
        rts
        nop

! st_put: write r3 as the next stream byte. A block entered here gets its
! header bytes [0..3] cleared (so it is never taken for a save start).
! Clobbers r0, r1.
st_put:
        sts.l   pr, @-r15
        bsr     st_cross
        nop
        bf      1f
        mov.l   r3, @-r15
        mov     #0, r3
        mov     #0, r9
        bsr     put_byte_at
        nop
        mov     #1, r9
        bsr     put_byte_at
        nop
        mov     #2, r9
        bsr     put_byte_at
        nop
        mov     #3, r9
        bsr     put_byte_at
        nop
        mov     #4, r9
        mov.l   @r15+, r3
1:      bsr     put_byte_at
        nop
        add     #1, r9
        lds.l   @r15+, pr
        rts
        nop

! read_list: r4 = first block of a save. Reads its block list into the work
! area and leaves the stream (r8/r9/r10) at the first data byte. Returns
! r0 = 0, or 1 if the list is broken. Clobbers r1-r7.
read_list:
        sts.l   pr, @-r15
        mov     r4, r8
        mov     #34, r9
        mov     #0, r10
        mov     #0, r7                  ! r7 = entries read
        LIST    r6
1:      bsr     st_get
        nop
        mov     r0, r5
        shll8   r5
        bsr     st_get
        nop
        or      r0, r5                  ! r5 = entry
        tst     r5, r5
        bt      8f
        mov     #2, r0                  ! must be a data block (2..count-1)
        cmp/hs  r0, r5
        bf      9f
        NBLK    r0
        cmp/hs  r0, r5
        bt      9f
        LCAP    r0                      ! and fit in the work area's list
        cmp/hs  r0, r7
        bt      9f
        mov     r7, r0
        shll    r0
        mov.w   r5, @(r0, r6)
        bra     1b
        add     #1, r7
8:      lds.l   @r15+, pr
        rts
        mov     #0, r0
9:      lds.l   @r15+, pr
        rts
        mov     #1, r0

! used_map: build the used-block map; returns r0 = number of free blocks.
! Clobbers r1-r10, r12.
used_map:
        sts.l   pr, @-r15
        MAP     r12                     ! r12 = map
        mov     r12, r1
        NBLK    r2
        mov     #0, r0
1:      mov.b   r0, @r1
        dt      r2
        bf/s    1b
        add     #1, r1
        mov     #1, r0
        mov.b   r0, @r12
        mov.b   r0, @(1, r12)
        mov     #2, r8                  ! scan for save starts
2:      mov.l   r8, @-r15
        mov     #0, r9
        bsr     get_byte_at
        nop
        mov.l   @r15+, r8
        tst     #0x80, r0
        bt      4f
        mov     #1, r0                  ! the first block
        mov     r8, r1
        add     r12, r1
        mov.b   r0, @r1
        mov.l   r8, @-r15
        bsr     read_list
        mov     r8, r4
        mov.l   @r15+, r8               ! the listed blocks (r7 of them)
        LIST    r1
3:      tst     r7, r7
        bt      4f
        mov.w   @r1+, r0
        extu.w  r0, r0
        add     r12, r0
        mov     #1, r2
        mov.b   r2, @r0
        bra     3b
        add     #-1, r7
4:      add     #1, r8
        NBLK    r0
        cmp/eq  r0, r8
        bf      2b
        mov     r12, r1                 ! count free blocks
        NBLK    r2
        mov     #0, r3
5:      mov.b   @r1+, r0
        tst     r0, r0
        bf      6f
        add     #1, r3
6:      dt      r2
        bf      5b
        mov     r3, r0
        lds.l   @r15+, pr
        rts
        nop

! find_save: r4 = name (NUL-terminated or 11 characters), r5 = first block
! to search. Returns r0 = block of the first matching save, or 0. An empty
! name matches every save. Clobbers r1-r3, r5-r7, r8, r9.
find_save:
        sts.l   pr, @-r15
        mov     r5, r8
1:      NBLK    r0
        cmp/hs  r0, r8
        bt      8f
        mov     #0, r9
        bsr     get_byte_at
        nop
        tst     #0x80, r0
        bt      4f
        mov     r4, r7                  ! compare up to 11 characters
        mov     #4, r9
        mov     #11, r6
2:      mov.b   @r7+, r5
        extu.b  r5, r5
        tst     r5, r5
        bt      7f                      ! end of the name: match
        bsr     get_byte_at
        nop
        cmp/eq  r5, r0
        bf      4f
        add     #1, r9
        dt      r6
        bf      2b
        bra     7f
        nop
4:      bra     1b
        add     #1, r8
7:      mov     r8, r0
        lds.l   @r15+, pr
        rts
        nop
8:      lds.l   @r15+, pr
        rts
        mov     #0, r0

! delete_block: r4 = first block of a save; clears its start flag
delete_block:
        sts.l   pr, @-r15
        mov     r4, r8
        mov     #0, r9
        bsr     put_byte_at
        mov     #0, r3
        lds.l   @r15+, pr
        rts
        nop

! block_size_field: r4 = first block; r0 = data size stored in [30..33].
! Clobbers r1-r3, r8, r9.
block_size_field:
        sts.l   pr, @-r15
        mov     r4, r8
        mov     #30, r9
        mov     #4, r3
        mov     #0, r2
1:      shll8   r2
        bsr     get_byte_at
        nop
        or      r0, r2
        add     #1, r9
        dt      r3
        bf      1b
        mov     r2, r0
        lds.l   @r15+, pr
        rts
        nop

! blocks_for: r4 = data size; r0 = blocks a save of that size takes:
! 1 + (size + 29) / (blocksize - 6). The first block holds the 34-byte save
! header, every block 4 header bytes, and each further block needs a 2-byte
! list entry (the list ends with 0x0000). Clobbers r1, r2, r4, r5.
blocks_for:
        sts.l   pr, @-r15
        add     #29, r4
        BSIZE   r5
        bsr     udiv
        add     #-6, r5
        add     #1, r0
        lds.l   @r15+, pr
        rts
        nop

! udiv: r0 = r4 / r5, r1 = r4 % r5 (unsigned). Clobbers r2, r4.
udiv:
        mov     #0, r1
        mov     #32, r2
1:      shll    r4
        rotcl   r1
        cmp/hs  r5, r1
        bf      2f
        sub     r5, r1
        add     #1, r4
2:      dt      r2
        bf      1b
        rts
        mov     r4, r0

