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
3. Full cold-boot hardware init matching the documented post-BIOS state
4. CD block driver: status, TOC, sector reads
5. IP.BIN load + checks, jump to game; test with homebrew discs (Yaul/Jo Engine samples, free to redistribute)
6. System call table + interrupt handling, so SGL/SBL-based commercial games boot
7. Backup RAM library, SMPC clock / peripheral helpers
8. MiSTer + real-hardware testing; boot menu, CD player
9. Mednafen: upstream a setting to allow a custom BIOS

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

## Open decisions
- Licence: default GPL-2.0-or-later, so Yabause's HLE code can be reused if
  useful. MIT is the alternative if we want maximum reuse in other projects.
- Where the code lives: needs a GitHub repository from the owner.
