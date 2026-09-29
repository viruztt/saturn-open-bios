# SaturnOpenBios plan

Goal: a free, open-source 512 KB boot ROM for the Sega Saturn that boots discs in
emulators and on the MiSTer Saturn core. Clean-room: written only from public
hardware documentation and observed behaviour. No Sega ROM bytes are copied or
disassembled.

## Status (2026-09-28)
- Stage 0 done: SH-2 vector table + reset code builds to a 512 KB image with
  GNU binutils (`sh-elf-as`), boots in Yabause 0.9.15 and paints the VDP2 back
  screen blue (`docs/stage0-yabause.png`). `make run` reproduces it headlessly.
- Stage 1 done: VDP2 text console (NBG0, own 5x7 font from `tools/mkfont.py`)
  with `con_puts` / `con_puthex`; prints a banner and a live VDP2 register
  (`docs/stage1-console.png`).
- Stage 3 in progress: cold-boot init steps in `src/init.s`, each reported
  OK/FAIL on screen, plus live readbacks (`docs/stage3-init.png`): SH-2
  on-chip peripherals off, Work RAM clear, master/slave vector tables at
  0x06000000/0x06000400 with VBR, SMPC SSHOFF/SNDOFF, SCU DMA/timer off +
  interrupts masked + A-bus/RSEL set, SCSP silenced + sound RAM clear, VDP1
  system clip/local origin set, VDP2 colour RAM clear. All OK in Yabause.
  The SH-2 bus state controller (BCR1/BCR2/WCR/MCR) is set on both CPUs
  since the MiSTer runs of 2026-09-28; SDRAM refresh (RTCSR/RTCOR) and mode
  setup for real hardware are still to do.
- Stage 4 done in Yabause: CD block driver in `src/cd.s` (command/reply
  protocol, HIRQ waits with timeouts, data and info ports). Boot now runs
  Initialize CD system, authenticate disc (0xE0/0xE1), read the TOC, and reads
  FAD 150 into 0x06002000 (`docs/stage4-cd.png`: status PAUSE on track 1,
  auth 4, TOC track 1 at FAD 150, lead-out at FAD 450, "SEGA SEGASATURN").
  Still open: behaviour with no disc / open tray, and timeouts sized for a
  real drive (authentication takes seconds on hardware).
- Stage 5 done in Yabause: disc boot in `src/disc.s`. Reads the whole IP.BIN
  (size from its header) to 0x06002000, checks the hardware ID and that the IP
  is big enough to hold the security code, finds the first file in the ISO
  9660 root directory and loads it to the IP's first-read address (rejected
  if outside Work RAM or over the BIOS scratch/stack), then hands over at
  0x06002E00 with the documented register state. `make run` now boots our own
  test disc (`testdisc/`, built by `tools/mktestdisc.py`), whose program turns
  the screen green (`docs/stage5-boot.png`). A bad header or load address
  stops boot with FAIL (`docs/stage5-rejects.png`). The boot stops at the
  first failed step.
- Stage 6 in progress: system calls and SCU interrupt dispatch in `src/sys.s`.
  Implemented: set/get SCU interrupt (0x06000300/304), set/get SH-2 interrupt
  (310/314), change system clock (320), semaphores (330/334), set/change SCU
  mask (340/344) with the shadow at 0x06000348, change SCU interrupt priority
  (280), and a dispatcher for SCU vectors 0x40-0x5F that saves registers,
  masks by priority, calls the game's handler and restores. CD player, MPEG
  check, CD init and power-on memory clear are no-ops, backup RAM init is a
  stub (milestone 7). The test disc calls each service and reports on screen
  (`docs/stage6-services.png`, all OK in Yabause, including ten VBlank
  interrupts through the dispatcher after a clock change).
  The BIOS work area and boot stack moved into the system area
  (0x06000D00-0x060017FF, stack below 0x06002000), so the whole of Work RAM
  High above IP.BIN is loadable.
- Stage 7 done in Yabause: backup RAM library in `src/bup.s`, reached
  through BUP_Init (0x06000358), which fills the function table in the game's
  work area and stores its address at 0x06000354. SelPart, Format, Stat,
  Write, Read, Delete, Dir, Verify, GetDate and SetDate work on the internal
  backup RAM in the standard on-chip format (block list followed through the
  listed blocks). The test disc writes, reads, verifies, lists and deletes a
  3000-byte, 53-block save and checks dates against independently computed
  values (`docs/stage7-bup.png`, all 12 service tests OK).
  Since 2026-09-28 also the backup RAM cartridge (device 1): the test disc
  formats it if needed and writes, reads back and deletes a save, showing
  the cartridge size found (OK in Kronos with 4, 8, 16 and 32 Mbit carts;
  NONE without one).
- First commercial game boots (see Compatibility). Found and fixed on the way:
  the slave SH-2 starts at the reset vector too, so `_start` now checks the
  BCR1 MASTER bit and sends the slave to `slave_start` (on-chip vectors, FRT
  input capture interrupt, VBR 0x06000400, stack from 0x060002AC, entry from
  0x06000250) instead of re-initialising the machine under the game; the CD
  block is left without the "disc changed" state (Get Hardware Info at boot);
  first read files may load over the tail of IP.BIN.
- Boot screen readouts include the last CD error code (01 = no CMOK for a
  command, 02 = no sector arrived, 03 = HIRQ bit never set, 04 =
  authentication never finished, 05 = drive never ready), the next FAD and
  sectors left of the last read.
- First MiSTer run (2026-09-27): all hardware init steps OK (so the missing
  bus state controller setup is not fatal there), then CD READ TOC failed:
  authentication was taken as done while the CD block still answered 0xFFFF
  ("busy"), and the TOC data never came within 0.5 s. CD waits now use VDP2
  VBlank (1/60 s) as the time base; authentication waits up to 30 s for a
  definite disc type (1-4); the drive must report PAUSE/STANDBY/PLAY before
  authentication and TOC (up to 30 s); data-ready waits up to 10 s.
- Second MiSTer run: authentication (4) and TOC now fine, but the IP.BIN
  header check failed on what FAD 150 delivered. The CD block is on the
  16-bit A-bus; 32-bit reads of the data port are split in two, which may
  not match real hardware. The first read is now 32-bit (what Yabause
  0.9.15 supports); if the header is not "SEGA SEGASATURN" the sector is
  read again 16 bits at a time and that width is kept. On a failed boot the
  last screen row shows the first 16 bytes of the first try in hex.
- Third MiSTer run: the hex row showed FFFFFFFF 41010000 01150000 01043BCB,
  the last four TOC entries: the sector read got 16 bytes left over from
  the TOC transfer. MiSTer's CD block serves TOC and sectors through one
  FIFO and sets DRDY before the FIFO has filled; reads of the empty FIFO
  return junk without consuming, leaving data behind. The BIOS now waits
  one frame after DRDY before reading any transfer, and checks the End Data
  Transfer word count (TOC 204, sector 1024), recording CD_ERR 06xxxxxx on
  a mismatch.
- Fourth MiSTer run: IP.BIN loads and passes (32-bit data port reads are
  fine), then 1ST READ FILE failed on the ISO 9660 volume descriptor (FAD
  166): most likely a sector left over from the previous request (a real
  drive keeps reading ahead). cd_read now asks Get Sector Info for the FAD
  of the first buffered sector and deletes any sector that is not the one
  it expects. MiSTer answers End Data Transfer with FFFFFF (no count), so
  CD_ERR 06FFFFFF there is informational. On a failed boot the hex row
  shows the start of the last sector read (or FAD 150 if IP.BIN was bad).
- Fifth MiSTer run: volume descriptor and root directory read fine and the
  first read file was found (0x38574 bytes at FAD 0xB2 to 0x06004000), but
  none of its sectors arrived. That read was the only one started with the
  CD block's Change Directory + Read File; on a real-drive CD block Change
  Directory completes asynchronously and the file read never started. The
  first read file is now loaded with Play like every other read (Read File
  had been added while chasing the Kronos stall that turned out to be ICR).
- Sixth MiSTer run: the whole boot passes and the BIOS hands over; the disc
  code at 0x06002E00 then hits an illegal instruction (vector 4, PC
  0x06002E08, registers as handed over). IP.BIN past its first sector is
  probably not what the disc holds. The crash screen now also dumps the 32
  bytes around PC to show what is in memory there.
- Seventh MiSTer run (Sonic R EU, IP size 0x1800): the dump at 0x06002DF0
  showed a repeating 16-byte pattern, not IP.BIN's second sector (FAD 151).
  For the bring-up the BIOS now shows a "Hand-over check" page for 5 s
  before starting the game: 16 bytes at IP.BIN +0000/+0800/+0E00/+1000 and
  at the first read address, and the CD sector checks (Get Sector Info
  rejected count, sectors dropped for a wrong FAD). Removed on 2026-09-28
  once MiSTer booted the games.
- Eighth MiSTer run: IP.BIN now fine; the first read file (113 sectors)
  stopped after 96 (64 + 32), with the drive paused and no sector arriving
  even after three fresh Play requests. On a read that gives up, the BIOS
  now records the free buffer blocks (Get Buffer Size) and HIRQ, and a
  failed boot shows Get Sector Info rejects, dropped sectors, free blocks
  and HIRQ on the row under the failed step. (Also fixed: the saved raw
  bytes had been placed over the first-read variables.)
- Ninth MiSTer run (hand-over page): IP.BIN +0000 and the first read file
  were right, but IP.BIN's second and third sectors held a repeating
  16-byte pattern, and 574 read-ahead sectors had been dropped for a wrong
  FAD. On real hardware HIRQ DRDY stays set until the host clears it, so
  waiting for DRDY passed at once and an empty data port was read. The BIOS
  now clears DRDY before Get TOC and before each Get Then Delete, and treats
  a rejected Get Then Delete (status 0xFF) as "not there yet".
- Tenth MiSTer run: IP.BIN load stopped after its first sector: the second
  Get Then Delete was accepted but DRDY never came (CD_ERR 03000FD5). After
  End Data Transfer a real CD block deletes the sectors and signals EHST;
  the next command must wait for that. The BIOS now clears EHST before End
  Data Transfer and waits for it afterwards.
- Eleventh MiSTer run: all of IP.BIN and the first read file correct; the
  BIOS hands over and Sonic R runs, then calls BUP_Stat through
  *(0x06000354) + 12 and lands at 0x06002000: it read 0 from 0x06000354
  although BUP_Init had stored the work area there. BUP_Init wrote through
  the cache-through alias; the game reads the cached address, and its cache
  still held the old line (MiSTer emulates the SH-2 cache, Kronos and
  Yabause do not). Services now write the variables games read (0x06000354,
  0x06000348, 0x06000324, the SCU handler table at 0x06000900) through their
  cached addresses; the caches are write-through, so memory stays right.
- Twelfth MiSTer run: Sonic R (EU), Clockwork Knight and Die Hard Arcade
  run; House of the Dead, Virtua Cop, Virtua Cop 2 and Shutsudo! Minisuka
  Police show a black screen; Panzer Dragoon failed loading its first read
  file after two 64-sector requests, the drive stuck in SEEK (CD_ERR
  02000400, buffer empty). cd_read now waits for the drive to be idle
  (PAUSE/STANDBY/PLAY) before every Play request.
- Thirteenth MiSTer run: Panzer Dragoon's drive then stayed in SEEK for
  30 s at that request boundary (CD_ERR 05000400). Reads are now one Play
  request per file (the CD block pauses the drive while its buffer is full
  and resumes as sectors are taken); before a retry the BIOS waits up to
  3 s for the drive to be idle and then sends Play anyway. Also: Sonic R had
  no CD audio on MiSTer. scsp_init had cleared the CD audio mix and left
  master volume 0; it now sets MVOL 15 and routes CD audio left/right
  through slots 16/17 (EFSDL 7, panned hard left/right).
- MiSTer runs 14 onwards (2026-09-27/28), with the diagnostics below:
  - Hand-over with the cache off made Panzer Dragoon run slowly with broken
    graphics: several games never write CCR themselves. The cache is purged
    and left on again.
  - Panzer Dragoon's first read always stopped at the same FAD with the drive
    in error. The dump's cue gives track 2 both a PREGAP line and a
    one-frame INDEX 00; with that INDEX 00 line removed the game loads, so
    this is the MiSTer's cue handling, not the BIOS.
  - CD audio routed through slots 16/17 had left and right swapped (measured
    on a generated tone); fixed. The mix is now raised only at the hand-over,
    so a failed read during boot is not heard as noise. A BIN/CUE tone test
    disc (`make build/testdisc-audio.bin`, two audio tracks, plus a cue in the
    PREGAP layout dumps use) plays cleanly on MiSTer.
  - House of the Dead, Virtua Cop, Virtua Cop 2 and Shutsudo stayed black.
    Their master CPU waited on a TAS.B lock that the slave takes and releases
    in a tight loop. The BIOS had left the bus state controller at its reset
    values (WCR 0xAAFF, the longest waits); setting BCR1/BCR2/WCR/MCR on both
    CPUs made all four games boot on MiSTer.
  - Games other than Clockwork Knight played no CD music. Diagnostics showed
    the drive stuck in SEEK at the start of the requested music track while
    the game had set up the SCSP. The BIOS left the drive connected to
    filter 0 from its own reads; the hand-over now ends any transfer,
    disconnects the drive and resets all selectors (authentication kept).
    That was not it: with the new diagnostics Sonic R's drive still seeks at
    track 2 with an empty buffer, crackling. The MiSTer core runs the real
    CD block firmware and emulates only the drive (Main_MiSTer
    `support/saturn/saturncdd.cpp`); for a cue PREGAP that is not stored in
    the image, its audio reads compute the file position as if it were and
    so play the end of the data track, which the firmware starts reading
    just before track 2. The tone disc's PREGAP cue did not show it because
    its image stores silence there. Confirmed on 2026-09-28: with the
    PREGAP line removed from its cue, Sonic R plays its CD music on MiSTer
    with this BIOS. A MiSTer image-handling issue, not the BIOS;
    workarounds: such cues, or CHD images (which store the pregap).
  - Die Hard Arcade lost parts of characters and Panzer Dragoon's FMV had
    missing bands: the slave ran the game's code with its cache off (only
    the master's was enabled at hand-over). slave_start now purges and
    enables the slave's cache; both games play properly on MiSTer.
- Post-BIOS state compared by observation (2026-09-28): `testdisc/statedump.s`
  records the registers a BIOS leaves, run from a private image with a
  game's IP.BIN on MiSTer with our BIOS and with another one. Differences,
  now matched: the master's FRT input capture interrupt was off (IPRB
  0x0F00 and TIER 0x81 expected, so the slave can signal the master:
  Virtua Cop dropped parts of its 3D scene without it), SDRAM refresh
  (MCR 0x78, RTCOR 0x36, RTCSR 0x08), DMAOR left 0, SCSP left with MVOL 0
  and slots 16/17 not mixed in, CD HIRQ without DRDY/CSCT/PEND, TVMD
  0x8000. A second page starts the slave the way games do (entry at
  0x06000250, SSHON) and shows its state: the other BIOS enters the
  slave's code with SR = 0, ours with 0xF0. Now SR = 0 too, with a default
  FRT input capture handler (clears ICF) on both CPUs so a pending
  capture does not loop; the slave no longer runs SDRAM refresh. Page 3 runs a
  handler through the BIOS services: priority and mask handling matched,
  but a level-0 DMA end reached the handler about 6 FRT ticks (48 cycles)
  later than with the other BIOS. With the SCU entries and dispatcher
  copied to Work RAM (0x06000620) Virtua Cop's zoom-out no longer drops
  3D on MiSTer (owner's report), although the measured latency stayed
  about the same; the remaining gap is not explained yet.
- Backup RAM manager (`src/menu.s`, 2026-09-28): opens when the drive
  reports no disc or an open tray, when Start is held at the end of the
  boot, or with Start on a failed boot. Lists the saves on the internal
  backup RAM and the cartridge (name, comment, size in blocks, free space)
  and deletes, copies between the two, or formats, each after an A/B
  confirmation. Start leaves (boots the disc, or starts the BIOS over).
  Pad input is SMPC INTBACK (port 1, standard pad). Its work area is in
  Low Work RAM, so a loaded game is untouched. Test builds: MENUTEST
  always opens it, MENUSCRIPT=1/2 replay a button script (copy to the
  cartridge / delete from it); both OK in Kronos.
- Debug tools: fatal exceptions (vectors 4/6/9/10) show a crash screen with
  vector, PC, SR, PR, SP and the 32 bytes around PC. `make diag` builds a
  diagnostics BIOS (`src/diag.s`): it counts system calls, samples the
  game's PC on VBlank and on a watchdog tick (its priority is set again on
  every system call, as some games clear IPRA), samples the slave the same
  way, and after ~30 s shows those plus a live CD status and CD block, SCU,
  SMPC, VDP and SCSP mixer registers. For games that hang with interrupts
  masked, a reset that keeps Work RAM shows a post-mortem page (counters,
  PC ring, slave samples, stack windows). `make run-image IMAGE=...` /
  `run-image-diag` boot a disc image in place.

## Compatibility
The owner reports that the rest of their dumps load too (not tested in
depth). Tested with the owner's own disc dumps, read in place (never copied, and no
game data or screenshots in this repository). Kronos 2.7 (libretro core in
RetroArch on Windows) is the main reference; Yabause 0.9.15 (WSL, headless)
is the quick automated check.

| Title | MiSTer | Kronos | Yabause 0.9.15 | Notes |
|---|---|---|---|---|
| Sonic R (EU) | Runs; CD music with a cue without PREGAP | Title screen | | CD music: see status |
| Clockwork Knight (JP) | Runs, CD music | Runs | | |
| Die Hard Arcade (JP) | Runs | Title screen | | Needed the slave cache enabled on MiSTer |
| Virtua Cop (JP) | Boots, no CD music | Boots, attract mode | Boots, attract mode | Needed the bus state controller setup on MiSTer |
| Virtua Cop 2 (EU) | Boots, no CD music | Boots | | Needed the bus state controller setup on MiSTer |
| Panzer Dragoon (JP) | Runs with a corrected cue | Boots, intro plays | Boots, intro movie plays | The dump's cue trips the MiSTer (see status) |
| The House of the Dead (JP) | Boots, no CD music | Boots to title screen | Crashes (jumps into VDP1 RAM) | Yabause also fails with its own HLE BIOS |
| Shutsudo! Minisuka Police (JP) | Boots | Black screen | Black screen | Same in the emulators with their own HLE BIOS; boots on MiSTer |

"No CD music" was before the CD hand-over change of 2026-09-28. On
2026-09-28 the owner reports that all eight games load on MiSTer with CD
music, using cues without the PREGAP line (see status). Virtua Cop's
missing 3D in its first zoom-out is fixed (see status).

Fixes found this way:
- Slave SH-2 start path (it starts at the reset vector too).
- CD block left without the "disc changed" state.
- First read file may load over the tail of IP.BIN.
- ICR VECMD = 1 on the master: the SCU supplies interrupt vectors. With 0,
  Kronos uses auto-vectors and never acknowledges the SCU, so no game gets
  its VBlank and the CPU drowns in interrupts.
- Reads are one Play request per file, retried for any missing sectors,
  with time-based limits; each sector's FAD is checked; DRDY and EHST are
  cleared before and awaited after each transfer.

## Test loop
| Target | Custom BIOS accepted? | Notes |
|---|---|---|
| Yabause (`-b file`) | Yes | Current loop. Also has an HLE BIOS (`-nb`), useful as a behavioural reference. |
| Kronos (libretro) | Yes | Main emulator reference; optional SH-2 cache emulation (`kronos_usecache`). |
| Mednafen 1.29 | **No** | Rejects any `sega_101.bin`/`mpr-17933.bin` whose hash isn't Sega's. Needs a small patch or a new setting upstream. |
| MiSTer Saturn core | Yes (`boot.rom` is user supplied) | Boots the tested games; models the SH-2 caches, CD block FIFO timing and bus contention that emulators skip. |
| Real hardware | Later | 27C4096 EPROM swap. |

## What a BIOS must do (public knowledge, to be verified per step)
1. **Reset & hardware init**: master SH-2 from vectors at 0x0, stack in
   Work RAM High (0x06000000–0x060FFFFF). Init SCU, VDP1, VDP2, SCSP (hold the
   68000 in reset), SMPC, and start the slave SH-2 via SMPC `SSHON` only when
   the game asks.
2. **System data area in Work RAM High (0x06000000–0x06001FFF)**: games call
   BIOS services through function pointers stored at fixed addresses (e.g.
   interrupt vector set/get, SCU mask, clock change, semaphores, CD helpers,
   Backup RAM library). This table is the compatibility contract; populate it
   from the Sega SDK docs (SBL/SGL "System Library" chapter) and Yabause's HLE
   BIOS as a behavioural reference.
3. **Disc boot**: talk to the CD block (registers at 0x25890000: HIRQ, CR1–CR4),
   authenticate the disc (command 0xE0/0xE1), read the 16-sector IP.BIN to
   0x06002000, check the "SEGA SEGASATURN " header, area symbols and the
   security code, load the first-read file to the address in the IP header,
   then jump to it with the documented register/memory state.
4. **User-facing extras (optional)**: boot logo (our own art), CD audio player,
   Backup RAM manager, clock set, language settings. Region free by design.

## Milestones
1. ~~Stage 0: code runs, screen colour~~
2. ~~Text console on VDP2 (own 8x8 font) for on-screen debug output~~
3. Full cold-boot hardware init matching the documented post-BIOS state (in progress)
4. ~~CD block driver: status, TOC, sector reads~~ (no-disc handling and real-drive timeouts still open)
5. ~~IP.BIN load + checks, jump to game~~ (own test disc; next: third-party homebrew discs)
6. ~~System call table + interrupt handling~~ (needs checking against real SGL/SBL games)
7. ~~Backup RAM library~~ (internal device; cartridge RAM later), SMPC peripheral helpers
8. MiSTer + real-hardware testing; boot menu, CD player
9. Mednafen: upstream a setting to allow a custom BIOS

## Known limits
- The system area layout below 0x06002000 beyond the documented system
  call addresses (priority table at 0x06000C00, boot work area
  0x06000D00-0x060017FF) is our own choice; check it against real games.
- ChangeSystemClock skips the standby/NMI handshake of the real hardware.
- Backup RAM: internal device (0) and backup RAM cartridge (1, 4-32 Mbit,
  ID byte at 0x24FFFFFF; emulators that do not provide the ID are handled
  by finding the format header and the address span where it repeats). No
  floppy (2). A save may use up to 3040 blocks (the block list in SBL's
  8 KB work area). Write deletes an existing save before checking for space
  (as Yabause's HLE BIOS does). The BupDir language byte is at offset 23
  (SBL layout); Yabause's HLE uses 22. Save format not yet checked against a
  dump from real hardware. BUP_Init ignores the library area.
  Blank internal backup RAM is formatted at boot. On MiSTer the core keeps
  backup RAM in memory and writes the game's .sav only with Autosave on
  (or "Save Backup RAM" in the OSD); confirmed across a power cycle
  2026-09-29. The manager (Start at boot, or no disc) works on MiSTer since
  the pad fixes of 2026-09-29 (INTBACK after VBlank-out, status compare).
- System settings (X in the manager): language in SMEM byte 3 low nibble
  (0 English .. 5 Japanese, as the emulators read it), written with
  SETSMEM; the SMPC clock is shown, not set (MiSTer and the emulators take
  it from the host). Stereo/mono is not offered: its SMEM bit is not
  publicly documented. The MiSTer core keeps SMEM only until the core is
  reloaded.
- Cartridge boot: a ROM at 0x02000000 (A-bus CS0) starting with the
  "SEGA SEGASATURN " hardware ID is booted like a disc IP.BIN (its IP,
  size from +0xE0, copied to 0x06002000, run from 0x06002E00) right after
  the CD block init. Start pressed earlier in the boot skips it. Pseudo
  Saturn Kai Lite (PSKAI256.BIN) reaches its main menu in Yabause (Action
  Replay cart type; Yabause's AR emulation does not start with the 1 MB
  full version).
- SetScuInterruptMask writes the SCU mask from the slave CPU too (Yabause
  only does it on the master).
- The first read file is loaded whole; sizes above the CD buffer (200
  sectors) are untested.

## Post-BIOS state checklist
What a game sees when the BIOS jumps to it, from Yabause's HLE BIOS
(`YabauseSpeedySetup` in `yabause.c`, `BiosInit` in `bios.c`, GPL-2.0-or-later),
compared on 2026-09-27. Values Yabause copies from Sega's ROM are not used.

| Item | Yabause state | Ours | Milestone |
|---|---|---|---|
| VBR | 0x06000000 | same | 3, done |
| Master / slave vector tables | 0x06000000 / 0x06000400, default `rte` stub at 0x06000600, vectors 4/6/9/10 halt | same (halt is in ROM) | 3, done |
| SCU ASR0/ASR1, AREF, RSEL, AIACK | 0x1FF01FF0, 0x1F, 1, 1 | same | 3, done |
| SCU IMS | all masked (shadow 0xFFFFFFFF at 0x06000348) | same | 6, done |
| VDP1 system clip / local origin, EDSR | 319x223, (160,112), 3 | same (EDSR 2 after one list) | 3, done |
| VDP2 | display on, NBG0, leftovers from the boot logo | our console | games reinit; revisit at 5 |
| Master SH-2 registers at jump | R0-R14 = 0, SR = 0, GBR = 0, PC = 0x06002E00 (IP.BIN code) | same, cache purged and left on | 5, done |
| SH-2 bus state controller | BCR1 0x03F1, BCR2 0x00FC, WCR 0x5555, MCR 0x0070 (set for the slave) | same, on both CPUs | 3, done |
| Stack at jump | from IP.BIN header (master stack), 0x06002000 if zero | same | 5, done |
| CD block | HIRQ 0xFC1, CR1-4 = status report, disc authenticated | authenticated, no transfer, drive connected to no filter, selectors reset | 4, done; exact HIRQ at 5 |
| SMPC | last command INTBACK | - | 7 |
| System calls 0x06000210-0x06000358, SCU dispatch 0x06000100-0x0600017F, 0x06000A00 table | BIOS service pointers | same, backup RAM library via 0x06000358 | 6, 7 done |

## Toolchain
- Now: Debian/Ubuntu `binutils-sh-elf` (assembler only).
- Next: SH-2 GCC for C code (build via crosstool-ng or the Yaul toolchain);
  keep hot paths and vectors in assembly.

## Prior art to build on
- No existing open Saturn BIOS found in a web search on 2026-09-27.
- Yabause/Kronos HLE BIOS (`src/bios.c`, GPL-2.0): best public description of
  the system call table and boot state. Using it as reference is fine; copying
  code would make this project GPL (see Licence).
- Yaul (open Saturn SDK): register definitions and homebrew test discs.
- Public docs: Sega Saturn hardware manuals (SCU, VDP1, VDP2, SMPC, SCSP),
  "Disc Format Standards Specification", CD block notes by Charles MacDonald.

## Decisions
- No lockout (owner, 2026-09-27): the IP.BIN security code is only checked for
  presence (IP size >= 0xE20), never compared with Sega's bytes, and Sega's
  code is never embedded in the ROM or put on our test disc. Area symbols
  are shown but not enforced (region free).
- Licence: GPL-2.0-or-later (owner, 2026-09-27). Yabause HLE code may be reused
  with attribution.
- Code lives in a local git repo in this folder; no GitHub remote for now.
