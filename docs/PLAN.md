# SaturnOpenBios plan

Goal: a free, open-source 512 KB boot ROM for the Sega Saturn that boots discs in
emulators and on the MiSTer Saturn core. Clean-room: written only from public
hardware documentation and observed behaviour. No Sega ROM bytes are copied or
disassembled.

## Status (2026-09-27)
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
  Still to do: SH-2 bus state controller / SDRAM setup (ignored by emulators,
  required on real hardware and MiSTer; values from the SH7604 manual).
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
  rejected count, sectors dropped for a wrong FAD). Remove once MiSTer
  boots games.
- Eighth MiSTer run: IP.BIN now fine; the first read file (113 sectors)
  stopped after 96 (64 + 32), with the drive paused and no sector arriving
  even after three fresh Play requests. On a read that gives up, the BIOS
  now records the free buffer blocks (Get Buffer Size) and HIRQ, and a
  failed boot shows Get Sector Info rejects, dropped sectors, free blocks
  and HIRQ on the row under the failed step. (Also fixed: the saved raw
  bytes had been placed over the first-read variables.)
- Debug tools: fatal exceptions (vectors 4/6/9/10) show a crash screen with
  vector, PC, SR, PR, SP and the 32 bytes around PC; `make diag` builds a diagnostics BIOS
  (`src/diag.s`) that counts system calls, samples the game's PC on VBlank,
  and after ~15 s shows those plus a CD block/SCU/SMPC/VDP status snapshot;
  `make run-image IMAGE=...` / `run-image-diag` boot a disc image in place.

## Compatibility
The owner reports that the rest of their dumps load too (not tested in
depth). Tested with the owner's own disc dumps, read in place (never copied, and no
game data or screenshots in this repository). Kronos 2.7 (libretro core in
RetroArch on Windows) is the main reference; Yabause 0.9.15 (WSL, headless)
is the quick automated check.

| Title | Kronos | Yabause 0.9.15 | Notes |
|---|---|---|---|
| Virtua Cop (JP) | Boots, attract mode | Boots, attract mode | |
| Panzer Dragoon (JP) | Boots, intro plays | Boots, intro movie plays | |
| The House of the Dead (JP) | Boots to title screen | Crashes (jumps into VDP1 RAM) | Also fails with Yabause's own HLE BIOS: emulator limit |
| Shutsudo! Minisuka Police (JP) | Black screen | Black screen | Same with Kronos's and Yabause's own HLE BIOS. Game runs (VBlank interrupts, 10 SCU handlers, SCU mask changed every frame) but waits in a loop; not yet attributable to our BIOS |

Fixes found this way:
- Slave SH-2 start path (it starts at the reset vector too).
- CD block left without the "disc changed" state.
- First read file may load over the tail of IP.BIN.
- ICR VECMD = 1 on the master: the SCU supplies interrupt vectors. With 0,
  Kronos uses auto-vectors and never acknowledges the SCU, so no game gets
  its VBlank and the CPU drowns in interrupts.
- Reads are Play requests of up to 64 sectors, retried for any missing
  sectors, with time-based limits; each sector's FAD is checked.

## Test loop
| Target | Custom BIOS accepted? | Notes |
|---|---|---|
| Yabause (`-b file`) | Yes | Current loop. Also has an HLE BIOS (`-nb`), useful as a behavioural reference. |
| Kronos / Yaba Sanshiro | Expected yes (Yabause forks) | Not tried yet. |
| Mednafen 1.29 | **No** | Rejects any `sega_101.bin`/`mpr-17933.bin` whose hash isn't Sega's. Needs a small patch or a new setting upstream. |
| MiSTer Saturn core | Expected yes (`boot.rom` is user supplied) | Needs real-hardware-accurate init; test once disc boot works. |
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
- Backup RAM: only the internal device; cartridge RAM (device 1) reports
  "not connected". Write deletes an existing save before checking for space
  (as Yabause's HLE BIOS does). The BupDir language byte is at offset 23
  (SBL layout); Yabause's HLE uses 22. Save format not yet checked against a
  dump from real hardware. BUP_Init ignores the library area.
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
| Master SH-2 registers at jump | R0-R14 = 0, SR = 0, GBR = 0, PC = 0x06002E00 (IP.BIN code) | same, cache purged | 5, done |
| Stack at jump | from IP.BIN header (master stack), 0x06002000 if zero | same | 5, done |
| CD block | HIRQ 0xFC1, CR1-4 = status report, disc authenticated | authenticated, TOC read, IP sector read | 4, done; exact HIRQ at 5 |
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
