# SaturnOpenBios

Free, clean-room replacement boot ROM for the Sega Saturn (emulators and MiSTer).

    sudo apt install binutils-sh-elf yabause xvfb x11-apps imagemagick
    make          # -> build/saturn-open-bios.bin (512 KB)
    make run      # boots it in Yabause headlessly, saves build/screen.png

Layout: `src/` SH-2 sources and linker script, `testdisc/` sources of the
test disc (our own IP.BIN and program, built into `build/testdisc.iso`),
`tools/` build and test scripts, `docs/PLAN.md` roadmap and research notes.

## Licence

GPL-2.0-or-later (see `COPYING`). Clean-room: no code or data from Sega's BIOS.
